import 'dart:async';
import 'dart:convert';

import '../../core/logging/app_log.dart';
import '../../core/net/app_http.dart';
import '../../models/user_data.dart';
import '../discover/discover_models.dart';
import '../discover/discover_service.dart';

/// 沉浸观影的横图封面来源：豆瓣 / TMDB / IMDb。
///
/// 统一返回可直接显示的网络地址：
///   · 豆瓣：走本地 `/img` 中继（图床校验 Referer）；
///   · TMDB / IMDb：直接使用官方图床地址。
class ArtworkService {
  ArtworkService(this.http, this.config);

  final AppHttp http;

  /// 读取当前封面设置（优先级 / TMDB Key）。
  final PlayerSettings Function() config;

  late final DiscoverService _douban = DiscoverService(http);

  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};
  final Map<String, List<String?>> _stillCache = {};
  final Map<String, Future<List<String?>>> _stillInflight = {};
  String? _biliCookie;
  DateTime? _biliCookieAt;
  final List<Completer<void>> _waiters = [];
  int _active = 0;

  static const int _maxConcurrent = 3;
  static const Duration _spacing = Duration(milliseconds: 90);
  static const String _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 按片名解析一张横图封面；没有则返回 null（调用方回落到竖版海报）。
  Future<String?> backdrop(String name, {String year = ''}) {
    final rawTitle = name.trim();
    if (rawTitle.isEmpty) return Future.value(null);
    final title = dramaTitle(rawTitle);
    final artworkTitle = title.isEmpty ? rawTitle : title;
    final settings = config();
    final effectiveYear = year.trim().isEmpty
        ? metadataYear(rawTitle)
        : year.trim();
    final key =
        '${normalizeArtworkPriority(settings.artworkPriority)}|'
        '${settings.tmdbApiKey}|$artworkTitle|$effectiveYear';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached.isEmpty ? null : cached);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _run(key, artworkTitle, effectiveYear);
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  /// 设置页「测试封面源」：逐个来源探测，返回每个来源的结果或错误。
  Future<List<ArtworkProbeResult>> probe(
    String name, {
    String year = '',
  }) async {
    final rawTitle = name.trim();
    final title = dramaTitle(rawTitle);
    final artworkTitle = title.isEmpty ? rawTitle : title;
    final results = <ArtworkProbeResult>[];
    final effectiveYear = year.trim().isEmpty
        ? metadataYear(rawTitle)
        : year.trim();
    for (final source in const ['douban', 'tmdb', 'imdb']) {
      try {
        final url = await _trySource(source, artworkTitle, effectiveYear);
        results.add(
          ArtworkProbeResult(
            source: source,
            url: (url ?? '').trim(),
            error: (url ?? '').trim().isEmpty ? '没有找到横图' : '',
          ),
        );
      } catch (e) {
        results.add(ArtworkProbeResult(source: source, url: '', error: '$e'));
      }
    }
    return results;
  }

  /// TMDB 分集封面：按剧名/年份找到剧集，再按季/集号取 `still_path`。
  ///
  /// 先试 B 站番剧（无需 Key、国内可直连），没有结果且配置了 TMDB Key 时再走
  /// TMDB。返回值长度固定为 [episodeCount]，没有封面的集用 null 占位。
  Future<List<String?>> episodeStills(
    String name, {
    String year = '',
    int episodeCount = 0,
    int? seasonHint,
    List<int> episodeNumbers = const [],
  }) {
    final rawTitle = name.trim();
    if (rawTitle.isEmpty || episodeCount <= 0) {
      return Future.value(const <String?>[]);
    }
    final title = dramaTitle(rawTitle);
    final artworkTitle = title.isEmpty ? rawTitle : title;
    final settings = config();
    final effectiveYear = year.trim().isEmpty
        ? metadataYear(rawTitle)
        : year.trim();
    final hint = seasonHint ?? seasonHintOf(rawTitle, trailingSequel: true);
    final numbers =
        episodeNumbers.length == episodeCount &&
            episodeNumbers.every((number) => number > 0)
        ? episodeNumbers
        : const <int>[];
    final key =
        'still|${settings.tmdbApiKey}|$artworkTitle|$effectiveYear|'
        '$episodeCount|${hint ?? 0}|${numbers.join(',')}';
    final cached = _stillCache[key];
    if (cached != null) return Future.value(cached);
    final pending = _stillInflight[key];
    if (pending != null) return pending;
    final future = _runEpisodeStills(
      artworkTitle,
      effectiveYear,
      episodeCount,
      hint,
      numbers,
    );
    _stillInflight[key] = future;
    return future
        .then((value) {
          _rememberStills(key, value);
          return value;
        })
        .whenComplete(() => _stillInflight.remove(key));
  }

  void _rememberStills(String key, List<String?> value) {
    if (_stillCache.length >= 500) _stillCache.remove(_stillCache.keys.first);
    _stillCache[key] = value;
  }

  Future<String?> _run(String key, String name, String year) async {
    await _acquire();
    try {
      if (_spacing > Duration.zero) await Future<void>.delayed(_spacing);
      final settings = config();
      final priority = normalizeArtworkPriority(settings.artworkPriority);
      final order = <String>[
        priority,
        ...const ['douban', 'tmdb', 'imdb'].where((s) => s != priority),
      ];
      for (final source in order) {
        if (source == 'tmdb' && settings.tmdbApiKey.trim().isEmpty) continue;
        try {
          final url = await _trySource(source, name, year);
          if (url != null && url.trim().isNotEmpty) {
            AppLog.i('artwork', '$name（$year）封面来源：$source');
            _remember(key, url.trim());
            return url.trim();
          }
        } catch (e) {
          AppLog.w('artwork', '$name 的 $source 封面获取失败：$e');
        }
      }
      _remember(key, '');
      return null;
    } finally {
      _release();
    }
  }

  void _remember(String key, String value) {
    if (_cache.length >= 800) _cache.remove(_cache.keys.first);
    _cache[key] = value;
  }

  Future<String?> _trySource(String source, String name, String year) {
    return switch (source) {
      'tmdb' => _tmdbBackdrop(name, year),
      'imdb' => _imdbBackdrop(name, year),
      _ => _doubanBackdrop(name, year),
    };
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
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

  // ------------------------------------------------------------------ 豆瓣

  Future<String?> _doubanBackdrop(String name, String year) async {
    for (final candidate in titleCandidates(name)) {
      final subject =
          await _douban.findSubject(candidate, year: year) ??
          await _douban.searchSubject(candidate, year: year);
      if (subject == null) continue;
      // 只取剧照横图；没有合格横图就换下一个候选片名，
      // 不用竖版海报裁切铺底（低分辨率竖图放大后非常模糊）。
      final photo = await _widestDoubanPhoto(subject.mediaType, subject.id);
      if (photo != null && photo.trim().isNotEmpty) return photo;
    }
    return null;
  }

  /// 豆瓣剧照里挑一张最宽、分辨率最高的图（横图宽高比 > 1.2）。
  Future<String?> _widestDoubanPhoto(String mediaType, String id) async {
    final type = mediaType == 'tv' ? 'tv' : 'movie';
    final res = await http.getText(
      'https://m.douban.com/rexxar/api/v2/$type/$id/photos'
      '?start=0&count=20&for_mobile=1',
      headers: {
        'User-Agent': _desktopUa,
        'Referer': 'https://m.douban.com/$type/subject/$id/',
      },
      timeout: const Duration(seconds: 12),
    );
    final decoded = jsonDecode(res.body);
    final photos = decoded is Map ? decoded['photos'] : null;
    if (photos is! List) return null;
    String? best;
    double bestScore = 0;
    for (final item in photos) {
      if (item is! Map) continue;
      final image = item['image'];
      if (image is! Map) continue;
      final large = image['large'] is Map ? image['large'] as Map : image;
      final url = (large['url'] ?? '').toString().trim();
      final width = (large['width'] as num?)?.toDouble() ?? 0;
      final height = (large['height'] as num?)?.toDouble() ?? 0;
      if (url.isEmpty || width <= 0 || height <= 0) continue;
      final ratio = width / height;
      // 分辨率太低的图放到大屏上一样糊，直接跳过。
      if (ratio < 1.2 || width < 1200) continue;
      final score = width * ratio;
      if (score > bestScore) {
        bestScore = score;
        best = url;
      }
    }
    return best?.isNotEmpty == true
        ? relayImageUrl(best!, referer: 'https://m.douban.com/')
        : null;
  }

  // ------------------------------------------------------------------ B 站

  /// B 站番剧分集封面：无需 Key，国内可直连。
  Future<List<String?>> _biliEpisodeStills(
    String name,
    String year,
    int episodeCount,
    List<int> episodeNumbers,
    int? seasonHint,
  ) async {
    final cookie = await _biliCookieValue();
    if (cookie.isEmpty) return const <String?>[];
    for (final candidate in episodeTitleCandidates(name)) {
      final hit = await _biliSearch(
        candidate,
        year,
        cookie,
        episodeCount,
        seasonHint,
      );
      if (hit == null) continue;
      final seasonId = (hit['season_id'] as num?)?.toInt() ?? 0;
      if (seasonId <= 0) continue;
      final result = await _biliSeason(seasonId, cookie);
      final stills = _biliStillsFromSeason(
        result,
        episodeCount,
        episodeNumbers,
      );
      if (stills.any((still) => still != null)) return stills;
    }
    return const <String?>[];
  }

  static List<String?> _biliStillsFromSeason(
    Object? result,
    int episodeCount,
    List<int> episodeNumbers,
  ) {
    final episodes = result is Map ? result['episodes'] : null;
    if (episodes is! List) return const <String?>[];
    final numbered = <(int, String)>[];
    final unnumbered = <String>[];
    for (final raw in episodes) {
      if (raw is! Map) continue;
      final cover = (raw['cover'] ?? raw['ep_cover'] ?? '').toString().trim();
      if (cover.isEmpty) continue;
      final url = cover.startsWith('http://')
          ? 'https://${cover.substring(7)}'
          : cover;
      final number = episodeNumber((raw['title'] ?? '').toString());
      if (number > 0) {
        numbered.add((number, url));
      } else {
        unnumbered.add(url);
      }
    }
    if (numbered.isEmpty && unnumbered.isEmpty) return const <String?>[];
    numbered.sort((a, b) => a.$1.compareTo(b.$1));
    final byNumber = <int, String>{
      for (final entry in numbered) entry.$1: entry.$2,
    };
    final max = numbered.isEmpty ? 0 : numbered.last.$1;
    final stills = List<String?>.filled(episodeCount, null);
    if (episodeNumbers.length == episodeCount &&
        episodeNumbers.toSet().length == episodeCount &&
        max > 0) {
      final valid = episodeNumbers.every(
        (number) => number > 0 && number <= max && byNumber.containsKey(number),
      );
      if (valid) {
        for (var i = 0; i < episodeCount; i++) {
          stills[i] = byNumber[episodeNumbers[i]];
        }
        return stills;
      }
    }
    // 集号对不上时按集号顺序回填。预告 / 花絮没有集号，不能混进正片序列，
    // 否则会把「预告」封面当成第一集，后面全部错位。
    final ordered = numbered.isNotEmpty
        ? [for (final entry in numbered) entry.$2]
        : unnumbered;
    for (var i = 0; i < episodeCount && i < ordered.length; i++) {
      stills[i] = ordered[i];
    }
    return stills;
  }

  Future<String> _biliCookieValue() async {
    final now = DateTime.now();
    final cached = _biliCookie;
    final at = _biliCookieAt;
    if (cached != null &&
        at != null &&
        now.difference(at) < const Duration(hours: 6)) {
      return cached;
    }
    try {
      final res = await http.getText(
        'https://api.bilibili.com/x/frontend/finger/spi',
        headers: {
          'User-Agent': _desktopUa,
          'Referer': 'https://www.bilibili.com/',
          'Accept': 'application/json',
        },
        timeout: const Duration(seconds: 12),
      );
      final decoded = jsonDecode(res.body);
      final data = decoded is Map ? decoded['data'] : null;
      final b3 = data is Map ? (data['b_3'] ?? '').toString().trim() : '';
      final b4 = data is Map ? (data['b_4'] ?? '').toString().trim() : '';
      final cookie = [
        if (b3.isNotEmpty) 'buvid3=$b3',
        if (b4.isNotEmpty) 'buvid4=$b4',
      ].join('; ');
      if (cookie.isNotEmpty) {
        _biliCookie = cookie;
        _biliCookieAt = now;
      }
      return cookie;
    } catch (e) {
      AppLog.w('artwork', 'B 站指纹获取失败：$e');
      return '';
    }
  }

  Future<Map<String, dynamic>?> _biliSearch(
    String name,
    String year,
    String cookie,
    int episodeCount,
    int? seasonHint,
  ) async {
    final query = _titleInfo(name, trailingSequel: true);
    if (query.key.isEmpty) return null;
    // 显式季号优先；否则用片名里的季号（`第二季` / `2`）。
    final wantedSeason =
        seasonHint ?? (query.explicitSeason ? query.season : null);
    final res = await http.getText(
      Uri.parse('https://api.bilibili.com/x/web-interface/search/type')
          .replace(
            queryParameters: {
              'search_type': 'media_bangumi',
              'keyword': name,
              // 默认只返回 10 条，正片（第一季）常被续作/中配版挤出列表；
              // 放宽到 30 条才能看到全部候选。
              'page_size': '30',
            },
          )
          .toString(),
      headers: {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.bilibili.com/',
        'Accept': 'application/json',
        'Cookie': cookie,
      },
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final code = decoded['code'];
    if (code is num && code.toInt() != 0) return null;
    final data = decoded['data'];
    final results = data is Map ? data['result'] : null;
    if (results is! List) return null;
    Map<String, dynamic>? best;
    var bestScore = 0;
    var bestYear = '';
    for (final item in results) {
      if (item is! Map) continue;
      final title = _cleanBiliText((item['title'] ?? '').toString());
      final original = _cleanBiliText((item['org_title'] ?? '').toString());
      final titleInfo = _titleInfo(title, trailingSequel: true);
      final originalInfo = _titleInfo(original, trailingSequel: true);
      // 只认归一后完全一致的片名。以前用 contains 通配，
      // 「鬼灭之刃 柱训练篇」「鬼灭之刃 第二季」都会被当成「鬼灭之刃」，
      // 再按集数决胜就会刮到完全错误的季。
      final hitInfo = titleInfo.key == query.key
          ? titleInfo
          : (originalInfo.key == query.key ? originalInfo : null);
      if (hitInfo == null) continue;
      final hitSeason = titleInfo.explicitSeason
          ? titleInfo.season
          : (originalInfo.explicitSeason ? originalInfo.season : null);
      if (wantedSeason != null) {
        // 没有季号标记的条目按第一季处理：搜第二季时不能拿第一季来顶。
        if ((hitSeason ?? 1) != wantedSeason) continue;
      } else if (hitSeason != null && hitSeason > 1) {
        continue;
      }
      final epSize = (item['ep_size'] as num?)?.toInt() ?? 0;
      var score = 100;
      if (wantedSeason == null && hitSeason == null) score += 10;
      final pubYear = _yearFromBiliTime(item['pubtime']);
      if (year.isNotEmpty && pubYear == year) score += 10;
      if (episodeCount > 0 && epSize > 0) {
        final diff = (epSize - episodeCount).abs();
        if (diff == 0) {
          score += 8;
        } else if (diff <= 2) {
          score += 3;
        } else if (diff > 6) {
          score -= 6;
        }
      }
      // 同一部番的中配/粤配封面相同：没有指定配音时优先原版条目。
      final hitDub = titleInfo.dub || originalInfo.dub;
      if (hitDub) score += query.dub ? 2 : -2;
      if (score > bestScore) {
        bestScore = score;
        bestYear = pubYear;
        best = Map<String, dynamic>.from(item);
      }
    }
    final picked = best == null
        ? '无结果'
        : '选中 ${_cleanBiliText((best['title'] ?? '').toString())} '
              'ep=${best['ep_size']} 年份=$bestYear';
    AppLog.i(
      'artwork',
      'B 站匹配 $name → key=${query.key} 季=${wantedSeason ?? 1} $picked',
    );
    return best;
  }

  static String _yearFromBiliTime(Object? raw) {
    if (raw is num && raw > 0) {
      final value = raw.toInt();
      final millis = value > 1000000000000 ? value : value * 1000;
      return '${DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).year}';
    }
    final text = raw?.toString().trim() ?? '';
    final match = RegExp(r'(19|20)\d{2}').firstMatch(text);
    return match?.group(0) ?? '';
  }

  Future<Map<String, dynamic>?> _biliSeason(int seasonId, String cookie) async {
    final res = await http.getText(
      Uri.parse('https://api.bilibili.com/pgc/view/web/season')
          .replace(queryParameters: {'season_id': '$seasonId'})
          .toString(),
      headers: {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.bilibili.com/',
        'Accept': 'application/json',
        'Cookie': cookie,
      },
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final code = decoded['code'];
    if (code is num && code.toInt() != 0) return null;
    final result = decoded['result'];
    return result is Map ? Map<String, dynamic>.from(result) : null;
  }

  static String _cleanBiliText(String raw) {
    var text = raw.replaceAll(RegExp('<[^>]*>'), '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return text.trim();
  }

  // ------------------------------------------------------------------ TMDB

  Future<Map<String, dynamic>?> _tmdbFind(
    String name,
    String year, {
    bool preferTv = false,
    bool trailingSequel = false,
  }) async {
    final key = config().tmdbApiKey.trim();
    if (key.isEmpty) return null;
    final query = _titleInfo(name, trailingSequel: trailingSequel);
    if (query.key.isEmpty) return null;
    final token = _looksLikeTmdbToken(key);
    final headers = token
        ? {'Authorization': 'Bearer $key'}
        : <String, String>{};
    final params = <String, String>{
      'language': 'zh-CN',
      'query': name,
      'include_adult': 'false',
      if (!token) 'api_key': key,
    };
    final res = await http.getText(
      Uri.parse('https://api.themoviedb.org/3/search/multi')
          .replace(queryParameters: params)
          .toString(),
      headers: headers,
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(res.body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) return null;
    Map<String, dynamic>? best;
    var bestScore = -1;
    var bestPopularity = -1.0;
    for (final item in results) {
      if (item is! Map) continue;
      final mediaType = (item['media_type'] ?? '').toString();
      if (mediaType != 'movie' && mediaType != 'tv') continue;
      // 分集剧照只接受剧集条目，同名电影不能拿来配电视剧的某一集。
      if (preferTv && mediaType != 'tv') continue;
      final title = (item['title'] ?? item['name'] ?? '').toString();
      final original = (item['original_title'] ?? item['original_name'] ?? '')
          .toString();
      final titleInfo = _titleInfo(title, trailingSequel: trailingSequel);
      final originalInfo = _titleInfo(original, trailingSequel: trailingSequel);
      // 与 B 站一致：只认归一后完全相等的片名，避免续作 / 同名前缀串片。
      if (titleInfo.key != query.key && originalInfo.key != query.key) {
        continue;
      }
      final date = (item['release_date'] ?? item['first_air_date'] ?? '')
          .toString();
      var score = 100;
      if (year.isNotEmpty && date.startsWith(year)) score += 10;
      if (preferTv) score += mediaType == 'tv' ? 10 : 0;
      final popularity = (item['popularity'] as num?)?.toDouble() ?? 0;
      if (score > bestScore ||
          (score == bestScore && popularity > bestPopularity)) {
        bestScore = score;
        bestPopularity = popularity;
        best = Map<String, dynamic>.from(item);
      }
    }
    AppLog.i(
      'artwork',
      'TMDB 匹配 $name → key=${query.key} 季=${query.explicitSeason ? query.season : '-'} '
          '${best == null ? '无结果' : '选中 ${best['name'] ?? best['title']} '
                    '(${best['media_type']}) id=${best['id']}'}',
    );
    return best;
  }

  Future<Map<String, dynamic>?> _tmdbJson(
    String path,
    Map<String, String> query,
  ) async {
    final key = config().tmdbApiKey.trim();
    if (key.isEmpty) return null;
    final token = _looksLikeTmdbToken(key);
    final headers = token
        ? {'Authorization': 'Bearer $key'}
        : <String, String>{};
    final res = await http.getText(
      Uri.parse('https://api.themoviedb.org/3/$path')
          .replace(queryParameters: {...query, if (!token) 'api_key': key})
          .toString(),
      headers: headers,
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(res.body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<String?> _tmdbBackdrop(String name, String year) async {
    for (final candidate in titleCandidates(name)) {
      // 「… 2」可能是第二季，也可能是《玩具总动员2》这种片名的一部分：
      // 先按完整片名找，找不到再把结尾数字当季号剥掉重试。
      final trailingSequel =
          seasonHintOf(candidate, trailingSequel: true) != null &&
          seasonHintOf(candidate) == null;
      for (final stripSequel in [false, if (trailingSequel) true]) {
        final best = await _tmdbFind(
          candidate,
          year,
          trailingSequel: stripSequel,
        );
        if (best == null) continue;
        final backdrop = (best['backdrop_path'] ?? '').toString().trim();
        if (backdrop.isNotEmpty) return _tmdbImage(backdrop);
        // 搜索结果没带 backdrop 时，再查一次 images 接口（TV/电影分开）。
        final mediaType = (best['media_type'] ?? '').toString();
        final id = (best['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final imagesJson = await _tmdbJson('$mediaType/$id/images', {
          'include_image_language': 'zh,en,null',
        });
        final backdrops = imagesJson?['backdrops'];
        if (backdrops is List) {
          Map? bestImage;
          var bestWidth = 0;
          for (final item in backdrops) {
            if (item is! Map) continue;
            final path = (item['file_path'] ?? '').toString().trim();
            if (path.isEmpty) continue;
            final width = (item['width'] as num?)?.toInt() ?? 0;
            if (width < 1200) continue;
            final language = (item['iso_639_1'] ?? '').toString();
            // 优先挑最宽的无文字横图，其次英文 / 中文，最后退而求其次。
            final score =
                width +
                (language == 'zh' || language == 'en' ? 40 : 0) +
                (language.isEmpty ? 60 : 0);
            if (score > bestWidth) {
              bestWidth = score;
              bestImage = item;
            }
          }
          if (bestImage != null) {
            return _tmdbImage((bestImage['file_path'] ?? '').toString());
          }
        }
      }
    }
    return null;
  }

  Future<List<String?>> _runEpisodeStills(
    String name,
    String year,
    int episodeCount,
    int? seasonHint,
    List<int> episodeNumbers,
  ) async {
    await _acquire();
    try {
      if (_spacing > Duration.zero) await Future<void>.delayed(_spacing);
      final bili = await _biliEpisodeStills(
        name,
        year,
        episodeCount,
        episodeNumbers,
        seasonHint,
      );
      if (bili.any((still) => still != null)) return bili;
      if (config().tmdbApiKey.trim().isEmpty) return const <String?>[];
      for (final candidate in episodeTitleCandidates(name)) {
        final stills = await _tmdbEpisodeStillsForName(
          candidate,
          year,
          episodeCount,
          seasonHint,
          episodeNumbers,
        );
        if (stills.any((still) => still != null)) return stills;
      }
      return const <String?>[];
    } catch (e) {
      AppLog.w('artwork', '$name 的分集封面获取失败：$e');
      return const <String?>[];
    } finally {
      _release();
    }
  }

  Future<List<String?>> _tmdbEpisodeStillsForName(
    String name,
    String year,
    int episodeCount,
    int? seasonHint,
    List<int> episodeNumbers,
  ) async {
    final best = await _tmdbFind(
      name,
      year,
      preferTv: true,
      trailingSequel: true,
    );
    if (best == null) return const <String?>[];
    if ((best['media_type'] ?? '').toString() != 'tv') {
      return const <String?>[];
    }
    final id = (best['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return const <String?>[];
    final detail = await _tmdbJson('tv/$id', {'language': 'zh-CN'});
    if (detail == null) return const <String?>[];
    final seasonNumbers = pickSeasons(
      detail['seasons'],
      episodeCount,
      seasonHint,
    );
    if (seasonNumbers.isEmpty) return const <String?>[];
    final seasonEpisodes = <int, List<String?>>{};
    for (final number in seasonNumbers) {
      final season = await _tmdbJson('tv/$id/season/$number', {
        'language': 'zh-CN',
      });
      seasonEpisodes[number] = _seasonStills(season);
    }
    return _alignEpisodeStills(seasonEpisodes, episodeCount, episodeNumbers);
  }

  /// 选出与站点集数对应的 TMDB 季：季号提示 → 集数完全一致 → 单季取前 N 集
  /// → 多季集数之和一致。与 Kazumi/AVBox 的 mapEpisodes 口径一致。
  static List<int> pickSeasons(
    Object? seasons,
    int episodeCount,
    int? seasonHint,
  ) {
    if (seasons is! List || episodeCount <= 0) return const [];
    final parsed = <({int number, int count})>[];
    for (final raw in seasons) {
      if (raw is! Map) continue;
      final number = (raw['season_number'] as num?)?.toInt() ?? 0;
      final count = (raw['episode_count'] as num?)?.toInt() ?? 0;
      if (number > 0 && count > 0) parsed.add((number: number, count: count));
    }
    parsed.sort((a, b) => a.number.compareTo(b.number));
    if (parsed.isEmpty) return const [];
    if (seasonHint != null) {
      final hintedIndex = parsed.indexWhere(
        (season) => season.number == seasonHint,
      );
      if (hintedIndex >= 0) {
        final hinted = parsed[hintedIndex];
        // 站点集数不超过该季（更新中 / 缺集）→ 直接用该季。
        if (episodeCount <= hinted.count + 1) return [hinted.number];
        // 站点把连续两季合并编号（第二季 12 集 + 第三季 12 集，
        // 资源站按 24 集排）→ 合并相邻季。
        var total = hinted.count;
        final numbers = <int>[hinted.number];
        for (
          var i = hintedIndex + 1;
          i < parsed.length && numbers.length < 3;
          i++
        ) {
          if (parsed[i].number != numbers.last + 1) break;
          total += parsed[i].count;
          numbers.add(parsed[i].number);
          if (total >= episodeCount) return numbers;
        }
      }
    }
    final exact = parsed.where((season) => season.count == episodeCount);
    if (exact.length == 1) return [exact.first.number];
    if (parsed.length == 1 && episodeCount <= parsed.first.count) {
      return [parsed.first.number];
    }
    final total = parsed.fold<int>(0, (sum, season) => sum + season.count);
    if (total == episodeCount) {
      return [for (final season in parsed) season.number];
    }
    return const [];
  }

  static List<String?> _seasonStills(Object? json) {
    final episodes = json is Map ? json['episodes'] : null;
    if (episodes is! List) return const <String?>[];
    final pairs = <(int, String)>[];
    var max = 0;
    for (final raw in episodes) {
      if (raw is! Map) continue;
      final number = (raw['episode_number'] as num?)?.toInt() ?? 0;
      if (number <= 0) continue;
      final path = (raw['still_path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      pairs.add((number, _tmdbStill(path)));
      if (number > max) max = number;
    }
    if (max == 0) return const <String?>[];
    final out = List<String?>.filled(max, null);
    for (final pair in pairs) {
      out[pair.$1 - 1] = pair.$2;
    }
    return out;
  }

  static List<String?> _alignEpisodeStills(
    Map<int, List<String?>> seasonEpisodes,
    int episodeCount,
    List<int> episodeNumbers,
  ) {
    final stills = List<String?>.filled(episodeCount, null);
    if (episodeNumbers.length == episodeCount &&
        episodeNumbers.toSet().length == episodeCount) {
      if (seasonEpisodes.length == 1) {
        final list = seasonEpisodes.values.first;
        final max = episodeNumbers.reduce((a, b) => a > b ? a : b);
        if (max <= list.length) {
          for (var i = 0; i < episodeCount; i++) {
            stills[i] = list[episodeNumbers[i] - 1];
          }
          return stills;
        }
      }
    }
    var index = 0;
    final numbers = seasonEpisodes.keys.toList()..sort();
    for (final season in numbers) {
      for (final still in seasonEpisodes[season]!) {
        if (index >= episodeCount) return stills;
        stills[index++] = still;
      }
    }
    return stills;
  }

  /// 从标题识别季号：`第2季` / `Season 2` / `S02`。
  ///
  /// [trailingSequel] 为 true 时，额外把结尾的 ` 2` / ` II` / ` 2nd` 当成
  /// 第二季（动漫站常见「赛博朋克：边缘行者 2」这种写法）。只在分集刮削
  /// 里开启；电影片名（如《玩具总动员2》）仍按完整片名匹配。
  static int? seasonHintOf(String text, {bool trailingSequel = false}) {
    final value = _toHalfWidth(text.trim());
    if (value.isEmpty) return null;
    final zh = RegExp(r'第\s*([0-9]+|[一二三四五六七八九十百零两]+)\s*[季部]')
        .firstMatch(value);
    if (zh != null) {
      final number = _cnNumber(zh.group(1)!);
      if (number != null && number > 0) return number;
    }
    final en = RegExp(
      r'(?:season|series)\s*([0-9]{1,2})',
      caseSensitive: false,
    ).firstMatch(value);
    if (en != null) return int.tryParse(en.group(1)!);
    final ordinal = RegExp(
      r'([0-9]{1,2})(?:st|nd|rd|th)\s+season',
      caseSensitive: false,
    ).firstMatch(value);
    if (ordinal != null) return int.tryParse(ordinal.group(1)!);
    final short = RegExp(
      r'(?:^|[\s._\-:：])S(?:eason)?\s*([0-9]{1,2})(?:[\s._\-]|$)',
      caseSensitive: false,
    ).firstMatch(value);
    if (short != null) return int.tryParse(short.group(1)!);
    if (!trailingSequel) return null;
    final tail = RegExp(
      r'[\s：:\-–—_]\s*(?:第\s*)?'
      r'([2-9]|1[0-9]|II|III|IV|V|VI|VII|VIII|IX|X|2nd|3rd|4th|5th)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (tail == null) return null;
    final token = tail.group(1)!;
    final numeric = int.tryParse(token);
    if (numeric != null) return numeric;
    final ordinalNumber = int.tryParse(
      RegExp(r'^[0-9]+').firstMatch(token)?.group(0) ?? '',
    );
    if (ordinalNumber != null) return ordinalNumber;
    return _romanNumber(token);
  }

  static int? _romanNumber(String raw) {
    const values = {
      'I': 1,
      'II': 2,
      'III': 3,
      'IV': 4,
      'V': 5,
      'VI': 6,
      'VII': 7,
      'VIII': 8,
      'IX': 9,
      'X': 10,
    };
    return values[raw.toUpperCase()];
  }

  static int? _cnNumber(String raw) {
    final direct = int.tryParse(raw);
    if (direct != null) return direct;
    const digits = {
      '零': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (raw == '十') return 10;
    final ten = raw.indexOf('十');
    if (ten >= 0) {
      final tens = ten == 0 ? 1 : digits[raw[0]];
      final ones = ten == raw.length - 1 ? 0 : digits[raw[ten + 1]];
      if (tens == null || ones == null) return null;
      return tens * 10 + ones;
    }
    return digits[raw];
  }

  /// 从站点剧集名提取集号（`第3集` / `EP03` / `03`），与 AVBox 同口径。
  static int episodeNumber(String raw) {
    var text = raw.replaceAll(RegExp(r'\[.*?\]|\(.*?\)|【.*?】'), '');
    text = text.replaceAll(
      RegExp(r'\d+(?:\.\d+)?\s*(?:gb|mb|gib|mib)\b', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '');
    text = text.toLowerCase().replaceAll(
      RegExp(
        r'2160p|1080p|720p|480p|4k|h26[45]|x26[45]|hevc|avc|'
        r'\b\d{3,4}[pi]\b|mp4|mkv',
      ),
      '',
    );
    final strong = RegExp(r'(?:ep|第|e)\s?(\d{1,4})').firstMatch(text);
    if (strong != null) return int.tryParse(strong.group(1)!) ?? -1;
    // `Show - 03` 这类用分隔符接集号的形态只接受 1~2 位且必须完整，
    // 避免把 `The.Covenant.2006.108...` 里的 108 当成集号。
    final weak = RegExp(r'[\-.\s]\s?(\d{1,2})(?![0-9])').firstMatch(text);
    if (weak != null) return int.tryParse(weak.group(1)!) ?? -1;
    // 没有 EP/第/Sxx 这类标记时，只接受纯数字集名。
    if (RegExp(r'[a-z\u4e00-\u9fa5]').hasMatch(text)) return -1;
    final digits = text.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) return -1;
    return int.tryParse(digits) ?? -1;
  }

  /// 从资源名里提取真正的剧名，用于封面匹配。
  ///
  /// `XXX【甄彩】` → `XXX`；`20261026【玉置秋】直播…` → `玉置秋`；
  /// `《玉置秋》尺度…` → `玉置秋`。取不到时保留原片名。
  static String dramaTitle(String raw) {
    final extracted = _extractDramaTitle(raw);
    final cleaned = cleanMetadataTitle(extracted);
    return cleaned.isEmpty ? extracted.trim() : cleaned;
  }

  static String _extractDramaTitle(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    // 前缀日期：20261026 / 2026-10-26 / [2026-10-26]
    text = text.replaceAll(RegExp(r'^\s*\d{8}\s*'), ' ');
    text = text.replaceAll(
      RegExp(r'^\s*(?:19|20)\d{2}[-./年]\d{1,2}[-./月]\d{1,2}日?\s*'),
      ' ',
    );
    // 前缀演员/频道标签，只去「…」，保留【…】给剧名判断。
    text = text.replaceAll(RegExp(r'^\s*「[^」]{1,30}」\s*'), ' ').trim();
    // 《标题》优先
    final book = RegExp(r'《([^》]{1,80})》').firstMatch(text);
    if (book != null) {
      final inner = book.group(1)!.trim();
      if (inner.isNotEmpty && !_isGenericResourceText(inner)) return inner;
    }
    // 结尾资源标签：XXX【甄彩】/ [HD] / （国语）
    for (var i = 0; i < 3; i++) {
      final before = text;
      text = text
          .replaceAll(
            RegExp(
              r'\s*(?:【[^】]{1,40}】|\[[^\]]{1,40}\]|（[^）]{1,40}）|\([^)]{1,40}\))\s*$',
            ),
            ' ',
          )
          .trim();
      if (text == before) break;
    }
    // 日期后面跟【剧名】直播…：括号里才是剧名
    final bracket = RegExp(r'【([^】]{1,60})】').firstMatch(text);
    if (bracket != null) {
      final inner = bracket.group(1)!.trim();
      final outside = text.replaceAll(RegExp(r'【[^】]*】'), ' ').trim();
      if (inner.isNotEmpty && _isGenericResourceText(outside)) return inner;
    }
    // 演员标签 + 多名字用 / 分隔时取第一个
    text = text
        .replaceAll(RegExp(r'^\s*(?:「[^」]{1,30}」|【[^】]{1,30}】)\s*'), ' ')
        .trim();
    final parts = text.split(RegExp(r'\s*/\s*'));
    if (parts.length > 1 && parts.first.trim().length <= 24) {
      text = parts.first.trim();
    }
    // 开头的直播/回顾等泛词与秒数
    text = text
        .replaceAll(RegExp(r'^\s*(?:直播|回看|回顾|解说|剪辑|花絮|片段|正片片段|二创|混剪)\s*'), ' ')
        .trim();
    text = text.replaceAll(RegExp(r'^\s*\d+秒\s*'), ' ').trim();
    return text;
  }

  static bool _isGenericResourceText(String text) {
    final value = text.trim();
    if (value.isEmpty) return true;
    const words = [
      '直播',
      '回看',
      '回顾',
      '解说',
      '剪辑',
      '花絮',
      '完整版',
      '加长版',
      '抢先版',
      '片段',
      '正片',
      '预告',
      '二创',
      '混剪',
      '第',
    ];
    for (final word in words) {
      if (value.startsWith(word)) return true;
    }
    return value
        .replaceAll(RegExp(r'[\d\s\p{P}\p{S}]', unicode: true), '')
        .isEmpty;
  }

  static const List<String> _metadataTags = [
    '2160p',
    '1080p',
    '720p',
    '480p',
    '4k',
    'hdr',
    'hdr10',
    'dolby',
    'bluray',
    'blu-ray',
    'web-dl',
    'webrip',
    'remux',
    'proper',
    'x265',
    'x264',
    'h264',
    'h265',
    'hevc',
    'avc',
    'aac',
    'dts',
    'atmos',
    '10bit',
    '8bit',
    '国语',
    '粤语',
    '中字',
    '中英',
    '双语',
    '无删减',
    '完整版',
    '加长版',
    '导演剪辑版',
    '中配版',
    '日语版',
    '国语版',
    '粤语版',
  ];

  /// 片名归一：去掉括号里的版本说明、清晰度/压制/语言标签和结尾年份。
  static String cleanMetadataTitle(String raw) {
    var text = raw.replaceAll(
      RegExp(r'\[[^\]]*\]|\([^)]*\)|【[^】]*】|（[^）]*）'),
      ' ',
    );
    for (final tag in _metadataTags) {
      text = text.replaceAll(
        RegExp(RegExp.escape(tag), caseSensitive: false),
        ' ',
      );
    }
    text = text.replaceAll(
      RegExp(r'\d+(?:\.\d+)?\s*(?:gb|mb|gib|mib)\b', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(
        r'\.(mkv|mp4|avi|ts|rmvb|flv|m2ts|mov|wmv)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    text = text.replaceAll(RegExp(r'[_\.]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.replaceAll(RegExp(r'^[-–—]+|[-–—]+$'), '').trim();
  }

  /// 去掉季号后缀，得到适合元数据搜索的主标题。
  static String stripSeasonSuffix(String value, {bool trailingSequel = false}) {
    var text = value.replaceAll(RegExp(r'第\s*[0-9一二三四五六七八九十两]+\s*[季部]'), ' ');
    text = text.replaceAll(
      RegExp(r'season\s*[0-9]{1,2}', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'([0-9]{1,2})(?:st|nd|rd|th)\s+season', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'(?:^|[\s._-])S[0-9]{1,2}(?:[\s._-]|$)', caseSensitive: false),
      ' ',
    );
    if (trailingSequel) {
      text = text.replaceAll(
        RegExp(
          r'[\s：:\-–—_]\s*(?:第\s*)?'
          r'(?:[2-9]|1[0-9]|II|III|IV|V|VI|VII|VIII|IX|X|2nd|3rd|4th|5th)\s*$',
          caseSensitive: false,
        ),
        ' ',
      );
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 片名归一后的比较键：只用于「是不是同一部片」的判断。
  ///
  /// 去掉标点 / 符号 / 空白 / 配音版本标记，保留文字与数字。
  /// 「鬼灭之刃 柱训练篇」和「鬼灭之刃」会得到不同的键，避免跨季串片。
  static String titleMatchKey(String raw) {
    var text = _toHalfWidth(dramaTitle(raw));
    if (text.isEmpty) text = _toHalfWidth(raw.trim());
    text = text.replaceAll(RegExp('<[^>]*>'), ' ');
    final book = RegExp(r'《([^》]{1,80})》').firstMatch(text);
    if (book != null) text = book.group(1)!;
    text = text.toLowerCase();
    // 配音版本不是片名身份的一部分；同一部番的中配/粤配封面相同。
    text = text.replaceAll(RegExp(r'(中配版|粤配版|国语版|日语版|台配版|中配|粤配|国语|日语|台配)'), '');
    // 「：」「·」「×」「（）」等标点在两边都折叠掉，避免同片不同键。
    return text.replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
  }

  static _TitleInfo _titleInfo(String raw, {bool trailingSequel = false}) {
    var text = dramaTitle(raw);
    if (text.isEmpty) text = raw.trim();
    final hint = seasonHintOf(text, trailingSequel: trailingSequel);
    final base = hint == null
        ? text
        : stripSeasonSuffix(text, trailingSequel: trailingSequel);
    return _TitleInfo(
      key: titleMatchKey(base.isEmpty ? text : base),
      season: hint ?? 1,
      explicitSeason: hint != null,
      dub: RegExp(r'中配|粤配|国语|日语|台配').hasMatch(raw),
    );
  }

  static String _toHalfWidth(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// 元数据搜索候选：原名 → 去版本标签 → 去季号。
  static List<String> titleCandidates(String raw) {
    final original = raw.trim();
    if (original.isEmpty) return const [];
    final cleaned = cleanMetadataTitle(original);
    final base = stripSeasonSuffix(cleaned);
    final list = <String>[];
    void add(String value) {
      final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || list.contains(text)) return;
      list.add(text);
    }

    add(original);
    add(cleaned);
    add(base);
    return list;
  }

  /// 分集刮削候选：常规候选之外，把结尾的 ` 2` 当季号剥掉再搜一次。
  ///
  /// 例如「赛博朋克：边缘行者 2」→「赛博朋克：边缘行者」，配合
  /// `seasonHint = 2` 定位到第二季；第一季不会被误选。
  static List<String> episodeTitleCandidates(String raw) {
    final list = <String>[...titleCandidates(raw)];
    final stripped = stripSeasonSuffix(
      dramaTitle(raw),
      trailingSequel: true,
    ).trim();
    if (stripped.isNotEmpty && !list.contains(stripped)) list.add(stripped);
    return list;
  }

  /// 从片名里取年份（用于补全调用方没传 year 的场景）。
  static String metadataYear(String raw) {
    final matches = RegExp(r'(19|20)\d{2}').allMatches(raw);
    if (matches.isEmpty) return '';
    return matches.last.group(0)!;
  }

  static bool _looksLikeTmdbToken(String key) =>
      key.startsWith('eyJ') || key.length > 60;

  static String _tmdbImage(String path) {
    final clean = path.trim();
    if (clean.startsWith('http')) return clean;
    return 'https://image.tmdb.org/t/p/original${clean.startsWith('/') ? '' : '/'}$clean';
  }

  static String _tmdbStill(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('http')) return clean;
    return 'https://image.tmdb.org/t/p/w300${clean.startsWith('/') ? '' : '/'}$clean';
  }

  // ------------------------------------------------------------------ IMDb

  /// IMDb 公开建议接口找条目 → GraphQL 取剧照（无需账号或 Key）。
  Future<String?> _imdbBackdrop(String name, String year) async {
    for (final candidate in titleCandidates(name)) {
      final id = await _imdbFind(candidate, year);
      if (id == null) continue;
      // 只接受横图；IMDb 没有合格横图时换下一个候选片名。
      final image = await _imdbImages(id);
      if (image != null && image.trim().isNotEmpty) return image;
    }
    return null;
  }

  Future<String?> _imdbFind(String name, String year) async {
    final res = await http.getText(
      'https://v3.sg.media-imdb.com/suggestion/x/'
      '${Uri.encodeComponent(name)}.json',
      headers: {'User-Agent': _desktopUa},
      timeout: const Duration(seconds: 12),
    );
    final decoded = jsonDecode(res.body);
    final list = decoded is Map ? decoded['d'] : null;
    if (list is! List) return null;
    Map? best;
    var bestScore = -1;
    for (final item in list) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString();
      final title = (item['l'] ?? '').toString();
      final kind = (item['qid'] ?? '').toString();
      final itemYear = (item['y'] as num?)?.toInt();
      if (id.isEmpty || !id.startsWith('tt')) continue;
      if (kind != 'movie' &&
          kind != 'tvSeries' &&
          kind != 'tvMiniSeries' &&
          kind != 'tvMovie') {
        continue;
      }
      var score = 0;
      if (title == name) {
        score += 5;
      } else if (title.contains(name) || name.contains(title)) {
        score += 2;
      }
      if (year.isNotEmpty && '$itemYear' == year) score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best?['id']?.toString();
  }

  Future<String?> _imdbImages(String imdbId) async {
    final query =
        'query { title(id: "$imdbId") { id images(first: 24) '
        '{ edges { node { url width height } } } } }';
    final res = await http.postJson(
      'https://api.graphql.imdb.com/',
      body: {'query': query},
      headers: {
        'User-Agent': _desktopUa,
        'Origin': 'https://www.imdb.com',
        'Referer': 'https://www.imdb.com/',
      },
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(res.body);
    final data = decoded is Map ? decoded['data'] : null;
    final title = data is Map ? data['title'] : null;
    final images = title is Map ? title['images'] : null;
    final edges = images is Map ? images['edges'] : null;
    if (edges is! List) return null;
    String? best;
    var bestWidth = 0;
    // IMDb 图库混有竖版海报和低分辨率剧照：优先挑最宽的横幅，太小的直接丢弃。
    for (final pass in const [(1.5, 1200), (1.2, 1000)]) {
      for (final edge in edges) {
        if (edge is! Map) continue;
        final node = edge['node'];
        if (node is! Map) continue;
        final url = (node['url'] ?? '').toString().trim();
        final width = (node['width'] as num?)?.toInt() ?? 0;
        final height = (node['height'] as num?)?.toInt() ?? 0;
        if (url.isEmpty || width < pass.$2 || height <= 0) continue;
        if (width / height < pass.$1) continue;
        if (width > bestWidth) {
          bestWidth = width;
          best = url;
        }
      }
      if (best != null) return best;
    }
    return best;
  }
}

/// 片名归一后的季号信息：`key` 判断是否同一部片，`season` 区分第几季。
class _TitleInfo {
  const _TitleInfo({
    required this.key,
    required this.season,
    required this.explicitSeason,
    required this.dub,
  });

  final String key;
  final int season;

  /// 标题里是否明确写了季号；没有写的按第一季处理。
  final bool explicitSeason;

  /// 中配 / 粤配 / 国语版等配音版本。
  final bool dub;
}

class ArtworkProbeResult {
  const ArtworkProbeResult({
    required this.source,
    required this.url,
    required this.error,
  });

  final String source;
  final String url;
  final String error;

  bool get ok => url.isNotEmpty;
}
