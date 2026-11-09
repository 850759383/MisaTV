import 'dart:async';

import '../../core/net/app_http.dart';
import 'discover_models.dart';
import 'discover_service.dart';

typedef CoverLookup = Future<String?> Function(String name, String year);

/// 豆瓣封面兜底：把 `subject_suggest` 返回的图床地址转成中继地址。
///
/// 豆瓣图床对没有 `Referer` 的请求返回 418（反盗链），Flutter 的
/// `Image.network` 默认不带 Referer，直接用原始地址会全部显示占位图。
/// 统一走本地 `/img?u=...&ref=https://m.douban.com/`，由中继补齐 UA / Referer。
String? doubanCoverUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return null;
  return relayImageUrl(url, referer: 'https://m.douban.com/');
}

/// 豆瓣图床地址（`doubanio.com` / `douban.com`）：不带 Referer 会返回 418。
bool isDoubanImageUrl(String raw) {
  final host = Uri.tryParse(raw.trim())?.host.toLowerCase() ?? '';
  return host.endsWith('doubanio.com') ||
      host.endsWith('douban.com') ||
      host.endsWith('doubanio.com.cn');
}

/// 源里直接给的豆瓣封面：先换成本地 `/img` 中继地址，由中继补 Referer。
///
/// 不这样处理时，蜘蛛返回的豆瓣图在卡片上全是 418，表现为「大面积无封面」。
String doubanImageDisplayUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty || !isDoubanImageUrl(url)) return url;
  return relayImageUrl(url, referer: 'https://movie.douban.com/');
}

/// 豆瓣封面补全：按片名查 `subject_suggest`，给源里缺图/坏图的卡片兜底。
///
/// 卡片是成屏出现的，所以这里做了三件事，避免把豆瓣打成 403：
///   · 同片名（含年份）只查一次，结果（含「查不到」）进内存缓存；
///   · 并发查询共享同一个 Future（同一部片不会发两次）；
///   · 最多 3 个并发，每个请求之间留一点间隔。
class CoverResolver {
  CoverResolver({
    required this.lookup,
    this.maxConcurrent = 3,
    this.spacing = const Duration(milliseconds: 120),
    this.maxEntries = 600,
  });

  final CoverLookup lookup;
  final int maxConcurrent;
  final Duration spacing;
  final int maxEntries;

  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};
  final List<Completer<void>> _waiters = [];
  int _active = 0;

  /// 返回封面直链；查不到 / 失败返回 null（结果同样缓存，避免反复请求）。
  Future<String?> resolve(String name, {String year = ''}) {
    final title = name.trim();
    if (title.isEmpty) return Future.value(null);
    final key = '$title|${year.trim()}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached.isEmpty ? null : cached);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _run(key, title, year.trim());
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  Future<String?> _run(String key, String name, String year) async {
    await _acquire();
    try {
      if (spacing > Duration.zero) await Future<void>.delayed(spacing);
      String? url;
      try {
        url = await lookup(name, year);
      } catch (_) {
        url = null;
      }
      final value = (url ?? '').trim();
      if (_cache.length >= maxEntries) _cache.remove(_cache.keys.first);
      _cache[key] = value;
      return value.isEmpty ? null : value;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

/// 进程内共享的封面服务（卡片直接调用，不依赖 AppState）。
class CoverImages {
  CoverImages._();

  static final CoverImages instance = CoverImages._();

  late final DiscoverService _douban = DiscoverService(AppHttp());
  late final CoverResolver _resolver = CoverResolver(
    lookup: (name, year) async {
      // subject_suggest 会被豆瓣限流（连续几次后直接返回空数组），
      // 拿不到图时再走 Rexxar 搜索接口兜底。
      final subject = await _douban.findSubject(name, year: year);
      final img = subject?.img ?? '';
      if (img.isNotEmpty) return doubanCoverUrl(img);
      final viaSearch = await _douban.searchSubject(name, year: year);
      return doubanCoverUrl(viaSearch?.img ?? '');
    },
  );

  Future<String?> resolve(String name, {String year = ''}) =>
      _resolver.resolve(name, year: year);
}
