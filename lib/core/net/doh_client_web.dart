import 'package:http/http.dart' as http;

/// 浏览器端无法改写 DNS，DoH 档直接退化成普通请求。
http.Client createDohClient() => http.Client();
