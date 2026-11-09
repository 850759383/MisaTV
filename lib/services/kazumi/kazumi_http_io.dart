import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 动漫站常见证书链不完整 / 证书过期：给 Kazumi 规则单独准备一个
/// 只读客户端，TLS 校验失败时回退使用（不影响其它源的严格校验）。
http.Client createKazumiHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (_, _, _) => true;
  return IOClient(client);
}
