import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/net/url_utils.dart';
import 'package:kniephos/services/config_parser.dart';

void main() {
  group('normalizeHostUrl', () {
    test('中文域名转 punycode（与 TVBox/okhttp 的 IDNA 一致）', () {
      expect(
        normalizeHostUrl('http://影视仓.com/'),
        'http://xn--5mqx81b535a.com/',
      );
      expect(
        normalizeHostUrl('http://宝盒接口.top'),
        'http://xn--6orr3pi6g9uu.top',
      );
      expect(
        normalizeHostUrl('http://影视仓.com:8080/a?b=1'),
        'http://xn--5mqx81b535a.com:8080/a?b=1',
      );
    });

    test('百分号编码的中文域名同样还原', () {
      expect(
        normalizeHostUrl('http://%E5%BD%B1%E8%A7%86%E4%BB%93.com/'),
        'http://xn--5mqx81b535a.com/',
      );
    });

    test('ASCII 域名与已编码域名保持不变', () {
      expect(
        normalizeHostUrl('https://9280.kstore.vip/newwex.json'),
        'https://9280.kstore.vip/newwex.json',
      );
      expect(
        normalizeHostUrl('http://xn--4kq62z5rby2qupq9ub.top/'),
        'http://xn--4kq62z5rby2qupq9ub.top/',
      );
    });

    test('站根与同路径换协议', () {
      expect(
        siteRootOf('https://影视仓.com/a/b.json?x=1'),
        'https://xn--5mqx81b535a.com/',
      );
      expect(
        protocolAltUrl('http://影视仓.com/a'),
        'https://xn--5mqx81b535a.com/a',
      );
      expect(
        protocolAltUrl('https://9280.kstore.vip/x'),
        'http://9280.kstore.vip/x',
      );
    });

    test('相对路径展开使用 punycode 基准地址', () {
      final fixed = ConfigParser.fixContentPath(
        'http://影视仓.com/sub/a.json',
        '{"spider":"./jar/x.jar"}',
      );
      expect(fixed, contains('http://xn--5mqx81b535a.com/sub/jar/x.jar'));
    });
  });

  group('githubMirrorUrls', () {
    test('raw 地址（含 refs/heads 与短分支两种写法）', () {
      expect(
        githubMirrorUrls(
          'https://raw.githubusercontent.com/qist/tvbox/refs/heads/master/fty.json',
        ),
        contains('https://cdn.jsdelivr.net/gh/qist/tvbox@master/fty.json'),
      );
      expect(
        githubMirrorUrls(
          'https://raw.githubusercontent.com/qist/tvbox/master/jar/fan.txt',
        ),
        contains('https://cdn.jsdelivr.net/gh/qist/tvbox@master/jar/fan.txt'),
      );
    });

    test('github.com raw/blob 地址也能转镜像', () {
      expect(
        githubMirrorUrls('https://github.com/qist/tvbox/raw/master/fty.json'),
        contains('https://cdn.jsdelivr.net/gh/qist/tvbox@master/fty.json'),
      );
      expect(
        githubMirrorUrls('https://github.com/qist/tvbox/blob/master/FTY/a.js'),
        contains('https://cdn.jsdelivr.net/gh/qist/tvbox@master/FTY/a.js'),
      );
    });

    test('非 GitHub 地址不产生镜像', () {
      expect(githubMirrorUrls('https://9280.kstore.vip/newwex.json'), isEmpty);
      expect(
        githubMirrorUrls('https://cdn.jsdelivr.net/gh/a/b@main/x.json'),
        isEmpty,
      );
    });
  });
}
