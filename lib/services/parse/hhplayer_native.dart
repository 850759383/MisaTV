import 'dart:convert';

import '../../core/logging/app_log.dart';
import '../../core/logging/log_redact.dart';
import '../../core/net/app_http.dart';
import 'parse_service.dart';

/// 巴士动漫（Dm84）返回的 `hhjx.hhplayer.com/?url=…` 解析页。
///
/// 旧 Dm84 jar 的 `/api/parse` 请求已失效，页面本身仍在 `__HHJX_BOOTSTRAP__`
/// 里给出 `url/t/key`，按页面的 JSON POST 方式重新请求即可拿到真实 m3u8。
///
/// `client_fallback` 必须为 `true`：普通线路返回的 CDN 地址会 302 到下载广告，
/// 只有备用线路才是真实视频（页面自己的播放器也是失败后才切这条线路）。
class HhplayerNative {
  const HhplayerNative(this._http);

  final AppHttp _http;

  static const String _api = 'https://hhjx.hhplayer.com/api/parse';
  static const String _origin = 'https://hhjx.hhplayer.com';
  static const String _defaultUa =
      'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final RegExp _bootstrapAssign = RegExp(
    r'window\.__HHJX_BOOTSTRAP__\s*=\s*',
  );

  Future<String?> resolve(
    String pageUrl, {
    Map<String, String> headers = const {},
  }) async {
    final page = pageUrl.trim();
    if (page.isEmpty) return null;
    try {
      final ua = _header(headers, 'user-agent') ?? _defaultUa;
      final pageRes = await _http.getText(
        page,
        headers: {...headers, 'User-Agent': ua},
        timeout: const Duration(seconds: 15),
      );
      final boot = extractBootstrap(pageRes.body);
      if (boot == null) {
        AppLog.w('parse', 'hhplayer 页面没有 __HHJX_BOOTSTRAP__');
        return null;
      }
      final opaque = '${boot['url'] ?? ''}'.trim();
      final key = '${boot['key'] ?? ''}'.trim();
      final t = boot['t'];
      if (opaque.isEmpty || key.isEmpty || t == null) {
        AppLog.w('parse', 'hhplayer bootstrap 缺少 url/key/t');
        return null;
      }

      final cookie = _http.cookiesFor(page);
      final api = await _http.postJson(
        _api,
        body: {'url': opaque, 't': t, 'key': key, 'client_fallback': true},
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Origin': _origin,
          'Referer': page,
          'User-Agent': ua,
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
        timeout: const Duration(seconds: 20),
      );
      final data = jsonDecode(api.body);
      if (data is Map && data['code'] == 200) {
        final url = '${data['url'] ?? ''}'.trim();
        if (ParseService.isMediaUrl(url)) {
          AppLog.i('parse', 'hhplayer 原生解析成功 ${redactUrl(url)}');
          return url;
        }
        final hit = ParseService.extractParseResult(api.body);
        if (hit != null && ParseService.isMediaUrl(hit.url)) {
          AppLog.i('parse', 'hhplayer 原生解析成功 ${redactUrl(hit.url)}');
          return hit.url;
        }
        AppLog.w('parse', 'hhplayer 返回非直链 ${shorten(url, 120)}');
        return null;
      }
      AppLog.w(
        'parse',
        'hhplayer 解析返回异常 code=${data is Map ? data['code'] : '?'} '
            'msg=${data is Map ? data['msg'] : ''}',
      );
      return null;
    } catch (e) {
      AppLog.w('parse', 'hhplayer 解析失败: ${shorten(e.toString(), 160)}');
      return null;
    }
  }

  /// 从页面里截出 `window.__HHJX_BOOTSTRAP__ = {...};`。
  ///
  /// `failure_html` 之类的字符串字段可能带 `}`，不能按第一个 `;` 截断，
  /// 这里做一次简单的花括号配对（跳过字符串与转义）。
  static Map<String, dynamic>? extractBootstrap(String html) {
    final match = _bootstrapAssign.firstMatch(html);
    final marker = match?.end ?? html.indexOf('__HHJX_BOOTSTRAP__');
    if (marker < 0) return null;
    final start = html.indexOf('{', marker);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < html.length; i++) {
      final ch = html.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == 0x5C) {
          escaped = true;
        } else if (ch == 0x22) {
          inString = false;
        }
        continue;
      }
      if (ch == 0x22) {
        inString = true;
      } else if (ch == 0x7B) {
        depth++;
      } else if (ch == 0x7D) {
        depth--;
        if (depth == 0) {
          final raw = html.substring(start, i + 1);
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } catch (_) {
            return null;
          }
          return null;
        }
      }
    }
    return null;
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }
}
