import 'proxy_config.dart';

/// 把「系统代理」解析成内置代理桥的上联配置。
///
/// 用户一般只是在 Clash / v2rayN 里开了「系统代理」，本应用要能跟着走，
/// 否则 Dart 的 HttpClient 默认完全无视系统设置，`api.themoviedb.org` 这类
/// 被墙的域名只会一路超时。
///
/// 两种来源：
///   · 环境变量 `HTTPS_PROXY` / `ALL_PROXY` / `HTTP_PROXY`（大小写都认）；
///   · Windows「Internet 选项 → 局域网设置」里的 `ProxyEnable` + `ProxyServer`，
///     值可能是 `127.0.0.1:7897`，也可能是 `http=...;https=...;socks=...` 分协议写法。
class SystemProxy {
  const SystemProxy._();

  /// 环境变量里的代理（优先级高于注册表）。
  static ProxyConfig? fromEnvironment(Map<String, String> env) {
    for (final key in const [
      'https_proxy',
      'HTTPS_PROXY',
      'all_proxy',
      'ALL_PROXY',
      'http_proxy',
      'HTTP_PROXY',
    ]) {
      final parsed = parseProxyUrl(env[key] ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Windows 注册表里的代理设置。
  static ProxyConfig? fromWindowsSettings({
    required bool proxyEnable,
    required String proxyServer,
  }) {
    if (!proxyEnable) return null;
    final text = proxyServer.trim();
    if (text.isEmpty) return null;
    if (!text.contains('=')) return parseProxyUrl(text);
    // 分协议写法：http= 最通用，其次 https=、socks=（socks 按 socks5 处理）。
    final map = <String, String>{};
    for (final part in text.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      map[part.substring(0, index).trim().toLowerCase()] = part
          .substring(index + 1)
          .trim();
    }
    final http = parseProxyUrl(map['http'] ?? '');
    if (http != null) return http;
    final https = parseProxyUrl(map['https'] ?? '');
    if (https != null) return https;
    for (final key in const ['socks5', 'socks']) {
      final value = (map[key] ?? '').trim();
      if (value.isEmpty) continue;
      final parsed = parseProxyUrl('socks5://$value');
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// 解析单个代理地址，支持：
  /// `127.0.0.1:7897`、`http://host:port`、`https://host:port`、
  /// `socks5://host:port`、`socks4://…`、`PROXY host:port`。
  static ProxyConfig? parseProxyUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase().startsWith('proxy ')) {
      text = text.substring(6).trim();
    }
    var type = 'http';
    final scheme = RegExp(r'^([a-zA-Z0-9]+)://').firstMatch(text);
    if (scheme != null) {
      final name = scheme.group(1)!.toLowerCase();
      if (name.startsWith('socks')) {
        type = 'socks5';
      } else if (name == 'https') {
        // HTTPS 代理端口同样按 HTTP CONNECT 处理（Clash / v2rayN 都是这种混合口）。
        type = 'http';
      } else if (name != 'http') {
        return null;
      }
      text = text.substring(scheme.end);
    }
    text = text.split('/').first.split('?').first.trim();
    if (text.isEmpty) return null;
    final separator = text.lastIndexOf(':');
    if (separator <= 0 || separator == text.length - 1) return null;
    final host = text
        .substring(0, separator)
        .replaceAll(RegExp(r'^\[|\]$'), '');
    final port = int.tryParse(text.substring(separator + 1));
    if (host.trim().isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    return ProxyConfig(
      enabled: true,
      type: type,
      host: host.trim(),
      port: port,
    );
  }
}
