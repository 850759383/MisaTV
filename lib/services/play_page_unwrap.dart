import '../core/logging/app_log.dart';
import '../core/logging/log_redact.dart';
import '../core/net/app_http.dart';
import '../models/vod.dart';

/// 播放地址是否明显是图片（封面 / 截图 / 图床变换模板）而不是视频。
///
/// 少数源把海报地址当播放地址返回（如 `~tplv-xxx-image.image`）；交给
/// fvp/libmdk 会黑屏，个别机器还会在原生图像解码路径上直接闪退。
/// 这类地址在打开播放器前拦下并提示换线路，比让原生内核去试更可控。
bool looksLikeImageMediaUrl(String raw) {
  final path = Uri.tryParse(raw.trim())?.path.toLowerCase() ?? '';
  if (path.isEmpty) return false;
  const suffixes = <String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
    '.svg',
    '.ico',
    '.image',
  ];
  return suffixes.any(path.endsWith);
}

/// 云播线路（`hnyun` / `mtyun` / `dbyun` 等）返回的通常是 HTML 播放/分享页，
/// 例如 `/play/<id>`、`/share/<hash>`；播放器拿到网页只会报 invalid media。
/// 这里把页面里内嵌的 m3u8 直链提取出来，再交给播放器。
class PlayPageUnwrap {
  PlayPageUnwrap(this._http);

  final AppHttp _http;
  final Map<String, String> _cache = {};
  final Set<String> _failed = {};

  /// 只有疑似播放页/分享页才需要抓取；带媒体扩展名的直链直接放行。
  static bool needsUnwrap(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return false;
    }
    final path = uri.path.toLowerCase();
    const media = [
      '.m3u8',
      '.mp4',
      '.flv',
      '.mkv',
      '.ts',
      '.mpd',
      '.mov',
      '.avi',
      '.webm',
      '.m4a',
      '.mp3',
    ];
    if (media.any(path.endsWith)) return false;
    if (path.contains('/play/') ||
        path.contains('/share/') ||
        path.contains('/player/') ||
        path.contains('/vodplay/')) {
      return true;
    }
    // 无扩展名的路径（不含 .php 这类接口）也当作可能的播放页。
    return !path.contains('.');
  }

  /// 从页面源码里提取 m3u8 / mp4 直链，优先 `main` / `vid` 这类主清单变量。
  static String? extractMediaUrl(String html, String pageUrl) {
    final text = html.replaceAll(r'\/', '/');
    final assigned = RegExp(
      r'(?:var|let|const)\s+(?:main|vid|url|videoUrl)\s*=\s*["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    ).firstMatch(text);
    if (assigned != null) {
      final abs = _absolute(assigned.group(1)!, pageUrl);
      if (abs != null) return abs;
    }
    final absolute = RegExp(
      r'https?://[^"\x27<>\s\\]+?\.(?:m3u8|mp4)(?:\?[^"\x27<>\s\\]*)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (absolute != null) return absolute.group(0);
    final relative = RegExp(
      r'["\x27](/[^"\x27<>\s\\]*?\.(?:m3u8|mp4)(?:\?[^"\x27<>\s\\]*)?)["\x27]',
      caseSensitive: false,
    ).firstMatch(text);
    if (relative != null) return _absolute(relative.group(1)!, pageUrl);
    return null;
  }

  static String? _absolute(String value, String pageUrl) {
    final v = value.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (!v.startsWith('/')) return null;
    try {
      return Uri.parse(pageUrl).resolve(v).toString();
    } catch (_) {
      return null;
    }
  }

  Future<PlayResult> unwrap(PlayResult play) async {
    if (play.parse != 0 || !play.playable) return play;
    final url = play.url.trim();
    if (!needsUnwrap(url)) return play;
    final cached = _cache[url];
    if (cached != null) return _withUrl(play, cached);
    // 解析过一次没结果的页面不再重复抓，避免每集都卡十秒。
    if (_failed.contains(url)) return play;
    try {
      final res = await _http.getText(
        url,
        headers: play.headers,
        timeout: const Duration(seconds: 10),
      );
      final type = res.contentType.toLowerCase();
      // 本身已经是清单或媒体流：原地址可以直接播。
      if (type.contains('mpegurl') ||
          type.startsWith('video/') ||
          type.contains('octet-stream') ||
          res.body.trimLeft().startsWith('#EXTM3U')) {
        return play;
      }
      final extracted = extractMediaUrl(res.body, url);
      if (extracted != null && extracted != url) {
        _remember(url, extracted);
        AppLog.i('play', '云播页面解出直链 ${redactUrl(extracted)}');
        return _withUrl(play, extracted);
      }
    } catch (e) {
      AppLog.w('play', '云播页面解析失败 ${redactUrl(url)}', e);
    }
    // `/play/<id>` 这类页面有时源码里没有直链，但补 `/index.m3u8` 就是清单。
    final fallback = _indexUrl(url);
    if (fallback != null) {
      try {
        final res = await _http.getText(
          fallback,
          headers: play.headers,
          timeout: const Duration(seconds: 8),
        );
        final type = res.contentType.toLowerCase();
        if (type.contains('mpegurl') ||
            res.body.trimLeft().startsWith('#EXTM3U')) {
          _remember(url, fallback);
          AppLog.i('play', '云播页面补 /index.m3u8 成功 ${redactUrl(fallback)}');
          return _withUrl(play, fallback);
        }
      } catch (_) {
        // 补路径也失败：保持原地址，让播放器给出明确错误
      }
    }
    _rememberFailed(url);
    return play;
  }

  static String? _indexUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) return null;
    final path = uri.path.endsWith('/')
        ? '${uri.path}index.m3u8'
        : '${uri.path}/index.m3u8';
    return uri.replace(path: path).toString();
  }

  void _remember(String pageUrl, String mediaUrl) {
    if (_cache.length >= 200) _cache.clear();
    _cache[pageUrl] = mediaUrl;
  }

  void _rememberFailed(String pageUrl) {
    if (_failed.length >= 200) _failed.clear();
    _failed.add(pageUrl);
  }

  PlayResult _withUrl(PlayResult play, String url) {
    return PlayResult(
      url: url,
      flag: play.flag,
      headers: play.headers,
      message: play.message,
    );
  }
}
