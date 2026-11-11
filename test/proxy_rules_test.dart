import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/relay/proxy_rules.dart';

void main() {
  tearDown(() {
    ProxyRules.current = ProxyRules.none;
    ProxyRules.relayBase = () => '';
  });

  test('普通域名按包含匹配，带正则元字符的按正则匹配', () {
    final rules = ProxyRules.fromRules([
      {
        'name': 'proxy',
        'hosts': ['javdb.com', '.*workers.dev', '127.0.0.1:8080'],
      },
    ]);
    expect(rules.matches('https://javdb.com/v/abc'), isTrue);
    expect(rules.matches('https://sub.javdb.com/x'), isTrue);
    expect(rules.matches('https://foo.workers.dev/api'), isTrue);
    expect(rules.matches('http://127.0.0.1:8080/x'), isTrue);
    expect(rules.matches('https://example.com/'), isFalse);
    expect(rules.matches(''), isFalse);
  });

  test('非法正则退回普通域名匹配，不会抛错', () {
    final rules = ProxyRules.fromRules([
      {
        'hosts': ['[bad', 'ok.com'],
      },
    ]);
    expect(rules.matches('https://ok.com/a'), isTrue);
    expect(rules.matches('https://example.com/[bad'), isTrue);
    expect(rules.matches('https://example.com/a'), isFalse);
  });

  test('rewrite 带上中继地址与请求头；已指向中继时不再套一层', () {
    ProxyRules.relayBase = () => 'http://127.0.0.1:9978';
    final rules = ProxyRules.fromRules([
      {
        'hosts': ['javdb.com'],
      },
    ]);
    final out = rules.rewrite(
      'https://javdb.com/v/?a=1',
      headers: {'Referer': 'https://javdb.com/'},
    );
    expect(out, startsWith('http://127.0.0.1:9978/proxy?do=proxy&url='));
    final query = Uri.parse(out).queryParameters;
    expect(query['url'], 'https://javdb.com/v/?a=1');
    expect(jsonDecode(query['h']!)['Referer'], 'https://javdb.com/');
    const loop = 'http://127.0.0.1:9978/proxy?do=proxy&url=x';
    expect(rules.rewrite(loop), loop);
  });

  test('中继没起来时原样返回；空规则集什么都不做', () {
    final rules = ProxyRules.fromRules([
      {
        'hosts': ['javdb.com'],
      },
    ]);
    expect(rules.rewrite('https://javdb.com/'), 'https://javdb.com/');
    expect(ProxyRules.none.matches('https://javdb.com/'), isFalse);
    expect(ProxyRules.fromRules(const []).isEmpty, isTrue);
    expect(rules.isEmpty, isFalse);
  });
}
