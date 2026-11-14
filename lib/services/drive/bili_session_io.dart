import 'dart:convert';
import 'dart:io';

import 'quark_session_io.dart'
    show QuarkSessionResult, mergeSetCookies, sanitizeCookie;

const _biliUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const _biliReferer = 'https://www.bilibili.com/';
const _biliNavUrl = 'https://api.bilibili.com/x/web-interface/nav';

/// 探测哔哩哔哩登录态并吸收响应里刷新的 Cookie（不写盘，调用方决定是否保存）。
///
/// 只看「有没有 SESSDATA」不够：过期 / 被风控的 SESSDATA 仍然存在，`nav`
/// 会回 `code=-101`（未登录）。这里用 `code == 0 && isLogin == true` 判定。
///
/// 注意：哔哩的 Cookie 是**可选增强**。没有登录态时蜘蛛照样能取到 360P / 480P
/// 的 `durl`，所以调用方不能把 `valid == false` 当成「不能播放」。
Future<QuarkSessionResult> refreshBiliSession(String cookie) async {
  final original = cookie.trim();
  if (original.isEmpty) {
    return const QuarkSessionResult(cookie: '', changed: false, valid: null);
  }
  final base = sanitizeCookie(original);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(Uri.parse(_biliNavUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _biliUa)
      ..set(HttpHeaders.refererHeader, _biliReferer)
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
    final code = (json?['code'] as num?)?.toInt();
    final data = json?['data'];
    final isLogin = data is Map && data['isLogin'] == true;
    final valid = response.statusCode == 200 && code == 0 && isLogin;
    // -101 = 账号未登录；-400 / -403 多为参数或风控问题，不能据此判定过期。
    final guest = code == -101;
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
