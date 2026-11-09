import 'dart:async';

import '../core/logging/app_log.dart';
import '../models/site_config.dart';
import '../models/vod.dart';
import 'source_service.dart';

class SearchService {
  SearchService(this.sourceService);
  final SourceService sourceService;

  static const _emitInterval = Duration(milliseconds: 80);
  static const _cacheTtl = Duration(minutes: 5);
  static const _cacheMax = 300;

  /// CMS 先进先出：慢的蜘蛛/JAR 源延迟启动，让 CMS 结果先上屏。
  static const _spiderStartDelay = Duration(milliseconds: 1200);

  /// 同源同关键词的短期结果缓存：搜索页来回切关键词时不必重复打源站。
  final Map<String, _SearchCacheEntry> _cache = {};

  void clearCache() => _cache.clear();

  /// [sites] 应是已按当前运行时就绪情况筛过的可用站点（见 `AppState.usableSites`）。
  ///
  /// 这里不能再按 `SourceBean.supported` 过滤：JAR 蜘蛛的 `supported` 恒为 false，
  /// 只能由 `AppState.isSiteUsable` 结合 `jarReady` 判定；旧写法会把全部 JAR 源
  /// 排除在搜索之外，表现为「搜什么都是 0 条」。
  Stream<SearchProgress> search(String keyword, List<SourceBean> sites) {
    final query = keyword.trim();
    final usable = sites.where((s) => s.searchable == 1).toList();
    final siteByKey = <String, SourceBean>{
      for (final site in usable) site.key: site,
    };

    /// 结果排序：CMS 优先，其次 Kazumi，再 JS/PY，最后 JAR/加固壳。
    /// 慢源（尤其需要启动 JVM 的 JAR）不把 CMS 结果往后挤。
    int tierOf(VodItem item) {
      final site = siteByKey[item.sourceKey];
      if (site == null) return 4;
      if (site.isJarSpider) return 3;
      if (site.type == 3) return 2;
      if (site.isKazumi) return 1;
      return 0;
    }

    final controller = StreamController<SearchProgress>();
    var cancelled = false;
    var closed = false;
    Timer? emitTimer;
    controller.onCancel = () {
      cancelled = true;
      emitTimer?.cancel();
    };

    if (query.isEmpty || usable.isEmpty) {
      controller.add(
        SearchProgress(
          items: const [],
          perSource: const [],
          done: 0,
          total: usable.length,
          finished: true,
        ),
      );
      controller.close();
      return controller.stream;
    }

    // 增量合并：不再每来一个源就重新扫描全部结果。
    final merged = <String, VodItem>{};
    final counts = <String, int>{};
    final perSource = <SearchPerSource>[];
    final sourceItems = <String, List<VodItem>>{};
    var done = 0;

    void absorb(VodItem item) {
      final key = _dedupeKey(item);
      counts[key] = (counts[key] ?? 0) + 1;
      final existing = merged[key];
      if (existing == null) {
        merged[key] = item;
        return;
      }
      // 同片多源：保留响应更快的源类型（CMS），顺带补封面。
      final keep = tierOf(item) < tierOf(existing) ? item : existing;
      final other = identical(keep, item) ? existing : item;
      final pic = keep.pic.isEmpty && other.pic.isNotEmpty ? other.pic : null;
      merged[key] = (pic == null && identical(keep, existing))
          ? existing
          : _copyItem(keep, pic: pic);
    }

    List<VodItem> snapshot() {
      final out = <VodItem>[];
      for (final entry in merged.entries) {
        final others = (counts[entry.key] ?? 1) - 1;
        final same = others > 0 ? others : 0;
        final item = entry.value;
        out.add(
          same == item.sameFromOtherSources
              ? item
              : _copyItem(item, sameFromOtherSources: same),
        );
      }
      // 相关度优先：名称完全一致 > 前缀 > 包含 > 无关；同级再按源类型。
      final ranked = [
        for (final item in out)
          (item: item, score: _relevance(item.name, query)),
      ];
      ranked.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byTier = tierOf(a.item).compareTo(tierOf(b.item));
        if (byTier != 0) return byTier;
        return a.item.name.compareTo(b.item.name);
      });
      return [for (final row in ranked) row.item];
    }

    void emit({required bool finished}) {
      if (cancelled || closed) return;
      controller.add(
        SearchProgress(
          items: snapshot(),
          perSource: List.of(perSource),
          sourceItems: Map<String, List<VodItem>>.from(sourceItems),
          done: done,
          total: usable.length,
          finished: finished,
        ),
      );
      if (finished) {
        closed = true;
        unawaited(controller.close());
      }
    }

    // 搜索页每个源完成都会 setState 重建结果网格；把高频事件压到 80ms
    // 一次，既保持流式上屏，又避免十几个源同时返回时连续掉帧。
    void scheduleEmit() {
      emitTimer?.cancel();
      if (done >= usable.length) {
        emit(finished: true);
      } else {
        emitTimer = Timer(_emitInterval, () => emit(finished: false));
      }
    }

    Future<void> run(SourceBean site) async {
      final started = DateTime.now().millisecondsSinceEpoch;
      try {
        // 同源同关键词 2 分钟内直接复用结果，不重复请求源站。
        final cacheKey = '${site.key}\u0000$query';
        final cached = _cache[cacheKey];
        final fresh =
            cached != null &&
            DateTime.now().difference(cached.at) < _cacheTtl;
        if (cached != null && !fresh) _cache.remove(cacheKey);
        List<VodItem>? cachedItems;
        if (cached != null && fresh) cachedItems = cached.items;
        List<VodItem> rawItems;
        if (cachedItems != null) {
          rawItems = cachedItems;
        } else {
          // 蜘蛛源（尤其常驻 JVM 首次 init）比 CMS 慢得多；给它更宽的窗口，
          // 避免常驻 host 还在跑就被上层 Future.timeout 提前判死。
          final timeoutSeconds = site.type == 3
              ? site.timeout + 35
              : site.timeout + 3;
          rawItems = await sourceService
              .search(site, query)
              .timeout(Duration(seconds: timeoutSeconds));
          _remember(cacheKey, rawItems);
        }
        if (cancelled) return;
        final items = rawItems
            .map(
              (e) => VodItem(
                id: e.id,
                name: e.name,
                pic: e.pic,
                remarks: e.remarks,
                year: e.year,
                area: e.area,
                type: e.type,
                sourceKey: e.sourceKey,
                tag: e.tag,
                sourceName: site.displayName,
              ),
            )
            .toList();
        for (final item in items) {
          absorb(item);
        }
        sourceItems[site.key] = items;
        final ms = DateTime.now().millisecondsSinceEpoch - started;
        perSource.add(
          SearchPerSource(
            key: site.key,
            name: site.displayName,
            status: items.isEmpty ? 'empty' : 'ok',
            count: items.length,
            ms: ms,
          ),
        );
        AppLog.i(
          'search',
          '源 ${site.key} ${cachedItems != null ? '缓存 ' : ''}'
              '${items.isEmpty ? '空' : '${items.length} 条'} ${ms}ms',
        );
      } catch (e) {
        if (cancelled) return;
        final ms = DateTime.now().millisecondsSinceEpoch - started;
        perSource.add(
          SearchPerSource(
            key: site.key,
            name: site.displayName,
            status: 'error',
            error: e.toString(),
            ms: ms,
          ),
        );
        AppLog.e('search', '源 ${site.key} 失败 ${ms}ms', e);
      } finally {
        if (!cancelled) {
          done++;
          scheduleEmit();
        }
      }
    }

    // CMS 与蜘蛛各自独立并发：以前只要订阅里有一个 type=3 源，所有源都退化为
    // 3 个 worker，几十个普通 CMS 要排队几十轮，整体搜索比原版慢一个量级。
    // CMS 用 10 个 worker；蜘蛛受常驻 host 数量限制（serve 是主线程顺序执行，
    // 多派只会排队），仍用 3 个。CMS 先启动，蜘蛛池稍后启动。
    const cmsConcurrency = 10;
    const spiderConcurrency = 3;
    final cmsSites = usable.where((s) => s.type != 3).toList();
    // 同类（type=3）里 JS / PY 先跑，需要冷启动 JVM 的 JAR / 加固壳排最后，
    // 避免几个 JAR 源一上来就把 3 个 worker 全占住。
    final spiderSites = usable.where((s) => s.type == 3).toList()
      ..sort((a, b) => (a.isJarSpider ? 1 : 0).compareTo(b.isJarSpider ? 1 : 0));

    Future<void> runPool(List<SourceBean> pool, int concurrency) async {
      var cursor = 0;
      Future<void> worker() async {
        while (!cancelled) {
          final index = cursor++;
          if (index >= pool.length) return;
          await run(pool[index]);
        }
      }

      final count = pool.length < concurrency ? pool.length : concurrency;
      await Future.wait([for (var i = 0; i < count; i++) worker()]);
    }

    unawaited(() async {
      // CMS 先跑，结果先上屏；蜘蛛/JAR 源延迟启动，避免 JVM 冷启动抢占
      // CPU 拖慢 CMS 请求。没有 CMS 源时立即启动蜘蛛池。
      final cmsRun = runPool(cmsSites, cmsConcurrency);
      final spiderRun = () async {
        if (spiderSites.isEmpty) return;
        if (cmsSites.isNotEmpty) {
          await Future<void>.delayed(_spiderStartDelay);
        }
        await runPool(spiderSites, spiderConcurrency);
      }();
      await Future.wait([cmsRun, spiderRun]);
    }());
    return controller.stream;
  }

  void _remember(String key, List<VodItem> items) {
    if (_cache.length >= _cacheMax && !_cache.containsKey(key)) {
      String? oldestKey;
      DateTime? oldestAt;
      for (final entry in _cache.entries) {
        if (oldestAt == null || entry.value.at.isBefore(oldestAt)) {
          oldestAt = entry.value.at;
          oldestKey = entry.key;
        }
      }
      if (oldestKey != null) _cache.remove(oldestKey);
    }
    _cache[key] = _SearchCacheEntry(DateTime.now(), items);
  }

  VodItem _copyItem(
    VodItem item, {
    String? pic,
    int? sameFromOtherSources,
  }) => VodItem(
        id: item.id,
        name: item.name,
        pic: pic ?? item.pic,
        remarks: item.remarks,
        year: item.year,
        area: item.area,
        type: item.type,
        sourceKey: item.sourceKey,
        tag: item.tag,
        sourceName: item.sourceName,
        sameFromOtherSources:
            sameFromOtherSources ?? item.sameFromOtherSources,
      );

  String _dedupeKey(VodItem item) {
    final name = item.name.toLowerCase().replaceAll(
      RegExp(r'[\s\-_:：·,，。!！?？]'),
      '',
    );
    return '$name|${item.year}';
  }

  /// 搜索相关度：完全一致 > 前缀 > 包含 > 名称片段 > 字符顺序命中。
  /// 只用于同一关键词下的排序，分数高低不改变结果是否保留。
  static int _relevance(String name, String query) {
    final n = _searchKey(name);
    final q = _searchKey(query);
    if (n.isEmpty || q.isEmpty) return 0;
    if (n == q) return 1000;
    int penalty(int diff) => diff <= 0 ? 0 : (diff > 200 ? 200 : diff);
    if (n.startsWith(q)) return 900 - penalty(n.length - q.length);
    final index = n.indexOf(q);
    if (index >= 0) {
      final score = 700 - index * 2 - penalty(n.length - q.length);
      return score > 0 ? score : 1;
    }
    if (n.length >= 2 && q.contains(n)) {
      final score = 500 - penalty(q.length - n.length);
      return score > 0 ? score : 1;
    }
    var pos = 0;
    for (final rune in q.runes) {
      final found = n.indexOf(String.fromCharCode(rune), pos);
      if (found < 0) return 0;
      pos = found + 1;
    }
    final score = 300 - penalty(n.length - q.length);
    return score > 0 ? score : 1;
  }

  static String _searchKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );
}

class _SearchCacheEntry {
  const _SearchCacheEntry(this.at, this.items);

  final DateTime at;
  final List<VodItem> items;
}
