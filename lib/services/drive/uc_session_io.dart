import 'dart:convert';
import 'dart:io';

import 'quark_session_io.dart'
    show QuarkSessionResult, mergeSetCookies, sanitizeCookie;

const _ucUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const _ucReferer = 'https://drive.uc.cn/';
const _ucMemberUrl =
    'https://pc-api.uc.cn/1/clouddrive/member'
    '?entry=ft&fr=pc&pr=UCBrowser&fetch_subscribe=true&_ch=home';
const _ucInfoUrl = 'https://fast.uc.cn/api/info?fr=pc&pr=UCBrowser';

/// 探测 UC 登录态并吸收响应里的新 `__puus`（不写盘，调用方决定是否保存）。
///
/// UC 登录页一打开就会下发 `__pus` / `PUVID` 等访客 Cookie；只看「有 Cookie」
/// 会把访客态当成登录成功，蜘蛛随后所有网盘接口都返回「没有返回数据」。
/// `/member` 返回 401 / code 31001 即访客态。
Future<QuarkSessionResult> refreshUcSession(String cookie) async {
  final original = cookie.trim();
  if (original.isEmpty) {
    return const QuarkSessionResult(cookie: '', changed: false, valid: null);
  }
  final base = sanitizeCookie(original);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  var merged = base;
  try {
    final request = await client.getUrl(Uri.parse(_ucMemberUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _ucUa)
      ..set(HttpHeaders.refererHeader, _ucReferer)
      ..set('Origin', 'https://drive.uc.cn')
      ..set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*')
      ..set(HttpHeaders.cookieHeader, base);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    final setCookies = <String>[];
    response.headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') setCookies.addAll(values);
    });
    merged = mergeSetCookies(merged, setCookies);

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // 非 JSON（网关错误页）→ 状态未知
    }
    final httpStatus = response.statusCode;
    final code = json?['code'];
    if (httpStatus == 200 && code == 0) {
      return QuarkSessionResult(
        cookie: merged,
        changed: merged != original,
        valid: true,
      );
    }
    final guest = httpStatus == 401 || code == 31001;
    // 明确的访客响应直接按未登录处理；只有「响应形态异常」时才用账号信息
    // 接口复核，避免每次轮询都多打一个请求。
    if (!guest) {
      final nickname = await _ucNickname(client, base);
      if (nickname.isNotEmpty) {
        return QuarkSessionResult(
          cookie: merged,
          changed: merged != original,
          valid: true,
        );
      }
    }
    return QuarkSessionResult(
      cookie: merged,
      changed: merged != original,
      valid: guest ? false : null,
    );
  } catch (_) {
    return QuarkSessionResult(cookie: original, changed: false, valid: null);
  } finally {
    client.close(force: true);
  }
}

/// UC 官方账号信息接口：返回昵称即说明 Cookie 是登录态。
Future<String> _ucNickname(HttpClient client, String cookie) async {
  try {
    final request = await client.postUrl(Uri.parse(_ucInfoUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _ucUa)
      ..set(HttpHeaders.refererHeader, _ucReferer)
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set('x-biz-retry', '0')
      ..set(HttpHeaders.cookieHeader, cookie);
    request.write(jsonEncode({'st': ''}));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return '';
    if (decoded['success'] != true) return '';
    final data = decoded['data'];
    if (data is! Map) return '';
    return (data['nickname'] ?? '').toString().trim();
  } catch (_) {
    return '';
  }
}
