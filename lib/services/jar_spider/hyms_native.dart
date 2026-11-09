import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../core/logging/app_log.dart';
import '../../core/logging/log_redact.dart';
import '../../core/net/app_http.dart';

/// 饭太硬「海绵」（csp_HmysGuard）的播放兜底。
///
/// 旧版 HymsGuard 的 `playerContent` 只带详情页里的旧 `vod_token/cur_time`
/// 直接调 `/api/video/collection`。该接口现在会先返回空 `vod_url`，必须：
///   1. `/api/video/result` 用旧 token 换到每条剧集的新 `vod_token/cur_time`；
///   2. `/api/video/collection` 用新 token 才返回真实 m3u8。
/// 壳里没有实现这两段，所以桌面端永远拿到 `url=&ck=`，再被 `/proxy?do=hmys`
/// 报 `cdn path empty`。这里按同一套 Hyms 客户端请求补上两步，绕开旧壳。
class HymsNative {
  HymsNative(this._http);

  final AppHttp _http;

  static const String _base = 'https://u.gslock.com';
  static const String _deviceId = 'a8ebc3ed43119349';
  static const String _initSign = 'DDB6E4D2927F807ED778F887390ABFD7';
  static const String _apiSign = '72BE38FB5F59D0194FC892F28133A5AA';
  static const String _apiKey = 'aZ9\$kU5%qI7=yC2=zH2#gM0@pX7^wF3a';
  static const String _initTime = '1793597323760';
  static const String _apiTime = '1793597325806';
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 12; TVBox Build/SKQ1.211113.001; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/97.0.4692.98 Mobile Safari/537.36';

  String? _token;

  /// 滑块验证成功后的 `session_id / sig / nc_token`（及 WebView Cookie）。
  Map<String, String>? _verifySession;

  /// 由播放页注入：打开 check_page_url，等用户完成滑块验证。
  static Future<Map<String, String>?> Function(String checkUrl)? captchaHandler;

  /// [id] 形如 `collection_id@@@vod_token@@@cur_time@@@vod_id`。
  /// 成功返回直链 m3u8；失败返回 null，由旧壳继续走原来的错误路径。
  Future<String?> resolve(String id) async {
    final parts = id.split('@@@');
    if (parts.length < 4) return null;
    final collectionId = parts[0].trim();
    final vodToken = parts[1].trim();
    final curTime = parts[2].trim();
    final vodId = parts[3].trim();
    if (collectionId.isEmpty || vodId.isEmpty) return null;
    try {
      return await _resolve(collectionId, vodToken, curTime, vodId);
    } catch (e) {
      AppLog.w('jar', 'Hyms 原生两段取链失败: ${shorten(e.toString(), 200)}');
      return null;
    }
  }

  Future<String?> _resolve(
    String collectionId,
    String vodToken,
    String curTime,
    String vodId,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _ensureToken(refresh: attempt > 0);
      if (token == null) return null;

      // 第一段：旧 token -> 新 token/时间。
      final result = await _post(
        '/api/video/result',
        _body(collectionId, vodToken, curTime, vodId),
        token,
      );
      final resultJson = _decode(result);
      final episodes = resultJson?['result']?['vod_collection'];
      if (episodes is! List || episodes.isEmpty) {
        AppLog.w('jar', 'Hyms result 无剧集返回 collection=$collectionId');
        _token = null;
        continue;
      }
      Map? episode;
      for (final item in episodes) {
        if (item is Map && '${item['id'] ?? ''}'.trim() == collectionId) {
          episode = item;
          break;
        }
      }
      episode ??= episodes.first is Map ? episodes.first as Map : null;
      final freshToken = '${episode?['vod_token'] ?? ''}'.trim();
      final freshTime = '${episode?['cur_time'] ?? ''}'.trim();
      if (freshToken.isEmpty || freshTime.isEmpty) {
        AppLog.w('jar', 'Hyms result 新 token 为空 collection=$collectionId');
        _token = null;
        continue;
      }

      // 第二段：新 token -> vod_url。未验证时这里通常只给 19 秒广告，
      // 同时返回 check_page_url；先带上已有 session 试一次，再决定是否弹滑块。
      final playJson = await _collection(
        collectionId,
        freshToken,
        freshTime,
        vodId,
        token,
      );
      var playResult = playJson?['result'];
      var url = _pickUrl(playResult);
      if (url != null && !_isAd(playResult)) return url;

      final checkUrl = '${playResult?['check_page_url'] ?? ''}'.trim();
      if (checkUrl.isEmpty) {
        if (url != null && !_isAd(playResult)) return url;
        AppLog.w(
          'jar',
          'Hyms collection 无直链 collection=$collectionId '
              'msg=${shorten('${playJson?['message'] ?? ''}', 80)}',
        );
        _token = null;
        continue;
      }
      final solver = captchaHandler;
      if (solver == null) {
        AppLog.w('jar', 'Hyms 需要滑块验证，但当前没有可用的验证页');
        return null;
      }
      AppLog.i('jar', 'Hyms 需要滑块验证 ${redactUrl(checkUrl)}');
      _verifySession = null;
      final session = await solver(checkUrl);
      if (session == null) {
        AppLog.w('jar', 'Hyms 滑块验证未完成');
        return null;
      }
      _verifySession = session;
      final verifiedJson = await _collection(
        collectionId,
        freshToken,
        freshTime,
        vodId,
        token,
      );
      playResult = verifiedJson?['result'];
      url = _pickUrl(playResult);
      if (url != null && !_isAd(playResult)) return url;
      _verifySession = null;
      AppLog.w(
        'jar',
        'Hyms 已验证但仍未拿到真实地址 collection=$collectionId '
            'duration=${playResult?['duration'] ?? ''} '
            'ad=${_isAd(playResult)}',
      );
      return null;
    }
    return null;
  }

  Future<Map?> _collection(
    String collectionId,
    String vodToken,
    String curTime,
    String vodId,
    String token,
  ) async {
    final body = _body(collectionId, vodToken, curTime, vodId, _verifySession);
    final raw = await _post(
      '/api/video/collection',
      body,
      token,
      cookie: _verifySession?['cookie'] ?? '',
    );
    return _decode(raw);
  }

  /// 免费态返回的是 19 秒下载 App 广告；真实剧集时长通常几十分钟。
  static bool _isAd(Map? result) {
    final duration = '${result?['duration'] ?? ''}'.trim();
    final parts = duration.split(':');
    if (parts.length == 3) {
      final seconds =
          (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
      if (seconds > 0 && seconds < 90) return true;
    }
    return '${result?['check_page_url'] ?? ''}'.trim().isNotEmpty &&
        duration.isEmpty;
  }

  Future<String?> _ensureToken({bool refresh = false}) async {
    if (!refresh && _token != null) return _token;
    final res = await _http.postForm(
      '$_base/api/public/init',
      body: {'invited_by': '', 'ua': _ua, 'is_install': '1'},
      headers: _headers('', _initSign, _initTime),
      timeout: const Duration(seconds: 15),
    );
    final json = _decode(res.body);
    final user = json?['result']?['user_info'];
    final token = user is Map ? '${user['token'] ?? ''}'.trim() : '';
    if (token.isEmpty) {
      AppLog.w('jar', 'Hyms init 未返回 token');
      return null;
    }
    _token = token;
    return token;
  }

  Future<String> _post(
    String path,
    Map<String, String> body,
    String token, {
    String cookie = '',
  }) async {
    final res = await _http.postForm(
      '$_base$path',
      body: body,
      headers: _headers(token, _apiSign, _apiTime, cookie: cookie),
      timeout: const Duration(seconds: 15),
    );
    return res.body;
  }

  Map<String, String> _headers(
    String token,
    String sign,
    String curTime, {
    String cookie = '',
  }) => {
    'sys_platform': '2',
    'device_id': _deviceId,
    'sysrelease': '10',
    'User-Agent': 'okhttp/4.9.0',
    'sign': sign,
    'cur_time': curTime,
    'channel_code': 'xk_sp01',
    'mobmodel': 'TVBox',
    'version': '50100',
    'token': token,
    'log-header': 'I am the log request header.',
    'mob_mfr': 'Android',
    'package_name': 'com.lineone.connecter',
    'app_id': 'xingkongshipin',
    if (cookie.isNotEmpty) 'Cookie': cookie,
  };

  Map<String, String> _body(
    String collectionId,
    String vodToken,
    String curTime,
    String vodId, [
    Map<String, String>? session,
  ]) => {
    'sig': session?['sig'] ?? '',
    'collection_id': collectionId,
    'nc_token': session?['nc_token'] ?? '',
    'code': '',
    'phone': '',
    'vod_id': vodId,
    'session_id': session?['session_id'] ?? '',
    'cur_time': curTime,
    'vod_token': vodToken,
  };

  /// Hyms 的响应是 base64(AES-256-CBC) 且首块前少一个 `{`；补齐后再解析。
  static Map? _decode(String body) {
    final text = decryptApiBody(body);
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _pickUrl(dynamic result) {
    if (result is! Map) return null;
    for (final key in const ['vod_url', 'tc_vod_url', 'down_url']) {
      final value = '${result[key] ?? ''}'.trim();
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
    }
    final m3u8 = result['m3u8_json'];
    dynamic parsed = m3u8;
    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        parsed = null;
      }
    }
    if (parsed is List) {
      for (final item in parsed) {
        if (item is Map) {
          final value = '${item['url'] ?? ''}'.trim();
          if (value.startsWith('http://') || value.startsWith('https://')) {
            return value;
          }
        } else if (item is String && item.startsWith('http')) {
          return item;
        }
      }
    }
    return null;
  }

  /// 供单测直接验证 Hyms 响应解密。
  static String decryptApiBody(String body) {
    try {
      final bytes = base64Decode(body.trim());
      if (bytes.length < 32 || bytes.length % 16 != 0) return '';
      final iv = Uint8List.fromList(bytes.sublist(0, 16));
      final cipherText = Uint8List.fromList(bytes.sublist(16));
      final key = Uint8List.fromList(utf8.encode(_apiKey));
      final cipher = CBCBlockCipher(AESEngine())
        ..init(false, ParametersWithIV(KeyParameter(key), iv));
      final out = Uint8List(cipherText.length);
      for (var off = 0; off < cipherText.length; off += 16) {
        cipher.processBlock(cipherText, off, out, off);
      }
      final text = utf8.decode(out, allowMalformed: true);
      final end = text.lastIndexOf('}');
      if (end < 0) return '';
      if (text.trimLeft().startsWith('{')) {
        return text.substring(text.indexOf('{'), end + 1);
      }
      final start = text.indexOf('"');
      if (start < 0 || start > end) return '';
      return '{${text.substring(start, end + 1)}';
    } catch (_) {
      return '';
    }
  }
}
