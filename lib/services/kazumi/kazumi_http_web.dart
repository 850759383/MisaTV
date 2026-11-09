import 'package:http/http.dart' as http;

/// Web 端没有自定义 TLS 校验，直接返回普通客户端。
http.Client createKazumiHttpClient() => http.Client();
