import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/drive/quark_session.dart';

void main() {
  test('mergeSetCookies 覆盖同名键并追加新键', () {
    const base = '__pus=old; ctoken=abc';
    final merged = mergeSetCookies(base, [
      '__pus=new; Path=/; HttpOnly',
      '__puus=fresh; Path=/',
    ]);
    expect(merged, '__pus=new; ctoken=abc; __puus=fresh');
  });

  test('mergeSetCookies 键名大小写不敏感、忽略非法行', () {
    const base = '__PUS=old; __puus=old2';
    final merged = mergeSetCookies(base, [
      '__pus=New; Path=/',
      'no-equals',
      '=empty-key',
    ]);
    expect(merged, contains('__pus=New'));
    expect(merged, isNot(contains('__PUS=old')));
    expect(merged, contains('__puus=old2'));
  });

  test('sanitizeCookie 清掉历史坏键，mergeSetCookies 可再命中同名覆盖', () {
    const legacy = '__pus=abc; \$1__puus=stale';
    final clean = sanitizeCookie(legacy);
    expect(clean, '__pus=abc');
    final merged = mergeSetCookies(clean, ['__puus=fresh; Path=/']);
    expect(merged, '__pus=abc; __puus=fresh');
  });

  test('mergeSetCookies 支持删除型空值', () {
    const base = 'a=1; b=2';
    final merged = mergeSetCookies(base, ['b=; Path=/']);
    expect(merged, 'a=1; b=');
  });
}
