import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/parse/hhplayer_native.dart';

void main() {
  test('hhplayer bootstrap 按花括号配对截取', () {
    const html = '''
<script>
window.__HHJX_BOOTSTRAP__={"url":"abc","t":1793601793,"key":"k",
"ts_key":"tk","failure_html":"播放失败，请刷新或稍候再试！{}"};</script>
<script>(() => { const d = window.__HHJX_BOOTSTRAP__; })();</script>
''';
    final boot = HhplayerNative.extractBootstrap(html);
    expect(boot, isNotNull);
    expect(boot!['url'], 'abc');
    expect(boot['t'], 1793601793);
    expect(boot['key'], 'k');
    expect(boot['failure_html'], '播放失败，请刷新或稍候再试！{}');
  });

  test('没有 bootstrap 时返回 null', () {
    expect(HhplayerNative.extractBootstrap('<html></html>'), isNull);
  });
}
