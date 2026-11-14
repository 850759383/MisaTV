import 'dart:convert';

/// TVBox 订阅里的「代理规则」：`rules[].hosts` 命中的地址不走直连，改走本机中继
/// 的通用代理口 `/proxy?do=proxy&url=…`，由中继带着应用自己的代理设置去取。
///
/// 与上游（FongMi `Proxy`）一致：hosts 里普通域名按「地址包含」匹配，带正则元字符
/// 的条目（`.*workers.dev` 这类）按正则匹配；非法的正则直接忽略，不能因为一条
/// 写错的规则把整份订阅的请求都打到代理上。
class ProxyRules {
  ProxyRules(Iterable<String> patterns) {
    for (final raw in patterns) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      if (_regexMeta.hasMatch(text)) {
        try {
          _regex.add(RegExp(text, caseSensitive: false));
        } catch (_) {
          // 正则不合法：按普通域名处理，至少别把这条规则丢掉
          _plain.add(text.toLowerCase());
        }
      } else {
        _plain.add(text.toLowerCase());
      }
    }
  }

  static final RegExp _regexMeta = RegExp(r'[*()\[\]\\|^$+?]');

  /// 空规则集：不做任何改写。
  static final ProxyRules none = ProxyRules(const []);

  /// 当前生效的规则；订阅加载 / 切换档案时由 AppState 登记。
  static ProxyRules current = none;

  /// 本机中继地址（`http://127.0.0.1:9978`）；中继没起来时返回空串，规则自动失效。
  static String Function() relayBase = () => '';

  final List<String> _plain = [];
  final List<RegExp> _regex = [];

  /// 从订阅的 `rules` 数组里抽出所有 `hosts`（不止 `name == proxy` 的那条）。
  factory ProxyRules.fromRules(Iterable<dynamic> rules) {
    final patterns = <String>[];
    for (final rule in rules) {
      if (rule is! Map) continue;
      final hosts = rule['hosts'];
      if (hosts is! List) continue;
      for (final host in hosts) {
        final text = host.toString().trim();
        if (text.isNotEmpty) patterns.add(text);
      }
    }
    return ProxyRules(patterns);
  }

  bool get isEmpty => _plain.isEmpty && _regex.isEmpty;

  /// 这个地址是否需要走代理。
  bool matches(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    for (final plain in _plain) {
      if (lower.contains(plain)) return true;
    }
    for (final re in _regex) {
      if (re.hasMatch(url)) return true;
    }
    return false;
  }

  /// 改写成中继的通用代理地址；[headers] 会一起带过去（Referer / Cookie 不能丢）。
  String rewrite(String url, {Map<String, String>? headers}) {
    final base = relayBase().trim();
    if (base.isEmpty) return url;
    // 地址已经指向中继本身时不要再套一层，否则自己代理自己。
    if (url.toLowerCase().startsWith(base.toLowerCase())) return url;
    final buffer = StringBuffer('$base/proxy?do=proxy&url=')
      ..write(Uri.encodeComponent(url));
    if (headers != null && headers.isNotEmpty) {
      buffer
        ..write('&h=')
        ..write(Uri.encodeComponent(jsonEncode(headers)));
    }
    return buffer.toString();
  }
}
