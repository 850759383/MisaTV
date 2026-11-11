import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/jar_spider/jar_spider.dart';
import 'package:kniephos/services/jar_spider/spider_host.dart';

void main() {
  group('rewriteLocalProxy', () {
    const port = 19973;

    test('-1 占位端口改写到本 JVM 宿主代理', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:-1/proxy?do=play&url=x', port),
        'http://127.0.0.1:$port/proxy?do=play&url=x',
      );
    });

    test('9978（旧桌面宿主）改写到本 JVM', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:9978/proxy?do=ck', port),
        'http://127.0.0.1:$port/proxy?do=ck',
      );
    });

    test('0 占位端口改写到本 JVM', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:0/proxy?do=proxy', port),
        'http://127.0.0.1:$port/proxy?do=proxy',
      );
      expect(
        rewriteLocalProxy('http://localhost:-1/proxy?do=proxy', port),
        'http://127.0.0.1:$port/proxy?do=proxy',
      );
    });

    test('旧入口 /proxy/<port> 归一到当前代理', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:9978/proxy/18888?do=proxy', port),
        'http://127.0.0.1:$port/proxy?do=proxy',
      );
    });

    test('当前端口与远端地址保持原样', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:$port/proxy?do=proxy', port),
        'http://127.0.0.1:$port/proxy?do=proxy',
      );
      expect(
        rewriteLocalProxy('https://example.com/proxy?a=1', port),
        'https://example.com/proxy?a=1',
      );
      expect(
        rewriteLocalProxy('http://127.0.0.1:30000/proxy?do=proxy', port),
        'http://127.0.0.1:30000/proxy?do=proxy',
      );
    });

    test('非 /proxy 路由（/chunk）不接管', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:-1/chunk?id=1', port),
        'http://127.0.0.1:-1/chunk?id=1',
      );
    });

    test('代理端口未知时原样返回', () {
      expect(
        rewriteLocalProxy('http://127.0.0.1:-1/proxy?do=play', 0),
        'http://127.0.0.1:-1/proxy?do=play',
      );
    });
  });

  group('isSpiderJarBytes', () {
    test('含 classes.dex 的 zip 视为有效 JAR', () {
      final archive = Archive()
        ..addFile(ArchiveFile('classes.dex', 8, utf8.encode('dex\n035')));
      final zipped = ZipEncoder().encode(archive);
      expect(isSpiderJarBytes(zipped), isTrue);
    });

    test('HTML 错误页 / 非 zip 不是有效 JAR', () {
      expect(
        isSpiderJarBytes(utf8.encode('<html><body>404</body></html>')),
        isFalse,
      );
    });
  });

  group('looksLikeBiliFlag', () {
    test('B 站线路的各种写法都能认出', () {
      expect(looksLikeBiliFlag('B站'), isTrue);
      expect(looksLikeBiliFlag('B 站 1080P'), isTrue);
      expect(looksLikeBiliFlag('哔哩哔哩'), isTrue);
      expect(looksLikeBiliFlag('bilibili'), isTrue);
      expect(looksLikeBiliFlag('Bili 4K'), isTrue);
    });

    test('普通线路名不误判', () {
      expect(looksLikeBiliFlag('4K'), isFalse);
      expect(looksLikeBiliFlag('高清线路'), isFalse);
      expect(looksLikeBiliFlag('UC'), isFalse);
      expect(looksLikeBiliFlag(''), isFalse);
    });

    test('蜘蛛的「账号未登录」文案能定位到哔哩', () {
      // 这类文案不含网盘名，必须靠线路名兜底才会触发会话刷新重试。
      expect(looksLikeBiliFlag('获取失败：账号未登录或 Cookie 已失效'), isFalse);
      expect(looksLikeBiliFlag('B站'), isTrue);
    });
  });

  group('hostProxyPortOf', () {
    test('解析 SpiderHost 上报的实际端口', () {
      expect(hostProxyPortOf('[host-proxy] listening port=20123'), 20123);
      expect(
        hostProxyPortOf('2026-10-30 x [host-proxy] listening port=20123 ...'),
        20123,
      );
    });

    test('无关行 / 未启动状态返回 null', () {
      expect(hostProxyPortOf('[host-proxy] 未启动（端口无效）'), isNull);
      expect(hostProxyPortOf('[relay] GET /proxy'), isNull);
      expect(hostProxyPortOf(''), isNull);
    });
  });
}
