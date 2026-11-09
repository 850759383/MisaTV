import 'quark_session_io.dart' show QuarkSessionResult;

/// Web 预览版不做 UC 会话探测：视为「状态未知」，保留原 Cookie。
Future<QuarkSessionResult> refreshUcSession(String cookie) async {
  return QuarkSessionResult(cookie: cookie, changed: false, valid: null);
}
