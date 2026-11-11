import 'dart:convert';
import 'dart:io';

import 'quark_session_io.dart'
    show QuarkSessionResult, mergeSetCookies, sanitizeCookie;

const _pan115Ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36  115Browser/26.0.7.2';
const _pan115Referer = 'https://115.com/';
const _pan115NavUrl = 'https://my.115.com/?ct=ajax&ac=nav';

/// 探测 115 网盘登录态并吸收响应里刷新的 Cookie（不写盘，调用方决定是否保存）。
///
/// 115 的网盘接口用 `UID` / `CID` / `SEID` 三件套鉴权：只贴 UID 时服务端仍回
/// 「登录失败」，蜘蛛侧表现为播放地址为空，所以这里以 `state == true` 判定，
/// 而不是只看 Cookie 里有没有字段。
Future<QuarkSessionResult> refreshPan115Session(String cookie) async {
  final original = cookie.trim();
  if (original.isEmpty) {
    return const QuarkSessionResult(cookie: '', changed: false, valid: null);
  }
  final base = sanitizeCookie(original);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(Uri.parse(_pan115NavUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _pan115Ua)
      ..set(HttpHeaders.refererHeader, _pan115Referer)
      ..set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*')
      ..set(HttpHeaders.cookieHeader, base);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    final setCookies = <String>[];
    response.headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') setCookies.addAll(values);
    });
    final merged = mergeSetCookies(base, setCookies);

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // 非 JSON（风控页 / 网关错误）→ 状态未知
    }
    final state = json?['state'];
    final valid = response.statusCode == 200 && state == true;
    // state == false 是明确的「未登录」；其它形态（验证码页等）留给下一次探测。
    final guest = response.statusCode == 200 && state == false;
    return QuarkSessionResult(
      cookie: merged,
      changed: merged != original,
      valid: valid ? true : (guest ? false : null),
    );
  } catch (_) {
    return QuarkSessionResult(cookie: original, changed: false, valid: null);
  } finally {
    client.close(force: true);
  }
}
