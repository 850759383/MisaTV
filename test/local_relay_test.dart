import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/dav.dart';
import 'package:kniephos/services/discover/cover_images.dart';
import 'package:kniephos/services/relay/local_relay.dart';
import 'package:kniephos/services/torrent/bt_stream.dart';

/// `/bt` 测试用的假会话源（不依赖 aria2）。
class _FakeBtSource implements BtStreamSource {
  _FakeBtSource({required this.path, required this.length});

  final String path;
  final int length;
  bool ready = true;
  final List<(int, int)> gates = [];

  @override
  BtStreamInfo? resolveStream(String infoHash, int fileIndex) {
    if (fileIndex != 1) return null;
    if (infoHash.length != 40) return null;
    return BtStreamInfo(
      absPath: path,
      length: length,
      fileOffset: 0,
      pieceLength: 1024,
    );
  }

  @override
  Future<bool> waitCovered(
    String infoHash,
    int fileIndex,
    int start,
    int end, {
    Duration? timeout,
    Duration? stall,
    bool Function()? isCancelled,
  }) async {
    gates.add((start, end));
    return ready;
  }
}

void main() {
  late HttpServer upstream;
  late HttpServer jvmProxy;
  late Directory root;
  late LocalRelay relay;
  late _FakeBtSource bt;
  final hash = List<String>.filled(40, 'b').join();

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('kniephos-relay-');
    File('${root.path}/hello.txt').writeAsStringSync('local-file-ok');
    final btFile = File('${root.path}/bt-source.bin');
    btFile.writeAsBytesSync(List<int>.generate(4096, (i) => i % 256));
    bt = _FakeBtSource(path: btFile.path, length: 4096);

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/dav-only') {
        res.write('auth:${req.headers.value(HttpHeaders.authorizationHeader)}');
        await res.close();
        return;
      }
      if (req.uri.path == '/index.m3u8') {
        res.headers.set('content-type', 'application/vnd.apple.mpegurl');
        res.write(
          '#EXTM3U\n'
          '#EXTINF:6.0,\n'
          'seg1.ts\n'
          '#EXT-X-CUE-OUT:30\n'
          '#EXTINF:6.0,\n'
          'ad.ts\n'
          '#EXT-X-CUE-IN\n'
          '#EXTINF:6.0,\n'
          'seg2.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await res.close();
        return;
      }
      if (req.uri.path == '/protected.mp4') {
        res.write('seen:${req.headers.value('x-test')}');
        await res.close();
        return;
      }
      if (req.uri.path == '/dup-cache.mp4') {
        // 上游 CDN 常见写法：同名 cache-control 下发多次。
        res.headers.add('cache-control', 'no-cache');
        res.headers.add('cache-control', 'no-store');
        res.write('dup-cache-ok');
        await res.close();
        return;
      }
      if (req.uri.path == '/live.txt') {
        res.headers.set('content-type', 'text/plain; charset=utf-8');
        res.write('央视,#genre#\nCCTV1,http://a.test/1.m3u8\n');
        await res.close();
        return;
      }
      if (req.uri.path == '/hotlink.jpg') {
        res.headers.set('content-type', 'image/jpeg');
        res.write('ref:${req.headers.value(HttpHeaders.refererHeader) ?? ''}');
        await res.close();
        return;
      }
      if (req.uri.path == '/ua-only') {
        res.write('ua:${req.headers.value(HttpHeaders.userAgentHeader) ?? ''}');
        await res.close();
        return;
      }
      if (req.uri.path == '/headers') {
        res.write(
          'cookie:${req.headers.value(HttpHeaders.cookieHeader) ?? ''}\n',
        );
        res.write('ua:${req.headers.value(HttpHeaders.userAgentHeader) ?? ''}');
        await res.close();
        return;
      }
      res.statusCode = 404;
      await res.close();
    });

    // 假「常驻 JVM 宿主代理」：壳自己的 do=… 路由交给它，中继只负责原样转发。
    jvmProxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    jvmProxy.listen((req) async {
      req.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
      req.response.write(
        'jvm:${req.uri.query}|range=${req.headers.value(HttpHeaders.rangeHeader) ?? ''}',
      );
      await req.response.close();
    });

    relay = LocalRelay.instance;
    await relay.start(
      fileRoot: root.path,
      driveTokens: () => const {},
      rules: () => const [],
      purifyEnabled: () => true,
      davAuth: (id) => id == 'srv-1' ? 'Basic dGVzdDp0ZXN0' : '',
      btSource: () => bt,
      jvmProxyPort: () => jvmProxy.port,
    );
  });

  tearDownAll(() async {
    await relay.stop();
    await upstream.close(force: true);
    await jvmProxy.close(force: true);
    await root.delete(recursive: true);
  });

  Future<({int status, List<int> bytes, HttpHeaders headers})> fetch(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      final res = await req.close();
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      return (status: res.statusCode, bytes: bytes, headers: res.headers);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> get(String url) async {
    final result = await fetch(url);
    expect(result.status, 200);
    return utf8.decode(result.bytes);
  }

  test('/img 注入 Referer（豆瓣图床反盗链）', () async {
    final target = 'http://127.0.0.1:${upstream.port}/hotlink.jpg';
    final wrapped = doubanCoverUrl(target);
    expect(wrapped, isNotNull);
    expect(wrapped, contains('/img?'));
    expect(await get(wrapped!), 'ref:https://m.douban.com/');
  });

  test('/play 未提供 UA 时补浏览器 UA（网盘直链 403 防护）', () async {
    final target = 'http://127.0.0.1:${upstream.port}/ua-only';
    final body = await get(relay.playUrl(target));
    expect(body, startsWith('ua:Mozilla/5.0'));
  });

  test('m3u8：去广告 + 分片/密钥递归改写回中继', () async {
    final target = 'http://127.0.0.1:${upstream.port}/index.m3u8';
    final body = await get(relay.playUrl(target));
    expect(body.contains('ad.ts'), isFalse);
    expect(body.contains('seg1.ts'), isTrue);
    expect(body.contains('seg2.ts'), isTrue);
    expect(body.contains('${relay.baseUrl}/play?'), isTrue);
    expect(body.contains('#EXT-X-ENDLIST'), isTrue);
  });

  test('/play 透传自定义 header', () async {
    final target = 'http://127.0.0.1:${upstream.port}/protected.mp4';
    final wrapped = relay.playUrl(target, headers: const {'X-Test': 'ok'});
    final body = await get(wrapped);
    expect(body, 'seen:ok');
  });

  test('/play 请求头换成短 token，URL 不带 Cookie 明文', () async {
    final target = 'http://127.0.0.1:${upstream.port}/headers';
    final cookie =
        'session=abc; ${List.generate(120, (i) => 'k$i=v$i').join('; ')}';
    final headers = {'Cookie': cookie, 'User-Agent': 'TestUA'};
    final wrapped = relay.playUrl(target, headers: headers);
    expect(wrapped, isNot(contains('cookie=')));
    expect(wrapped.length, lessThan(500));
    // 相同 URL + 相同请求头复用同一个 token，不会给每个 HLS 分片建新表项。
    expect(relay.playUrl(target, headers: headers), wrapped);
    final body = await get(wrapped);
    expect(body, contains('cookie:$cookie'));
    expect(body, contains('ua:TestUA'));
  });

  test('/play 超长目标地址换短 token，URL 不超过 FFmpeg 上限', () async {
    final longTarget =
        'http://127.0.0.1:${upstream.port}/headers?x=${'a' * 4000}';
    final wrapped = relay.playUrl(longTarget);
    expect(wrapped.length, lessThan(500));
    expect(wrapped, contains('p='));
    final body = await get(wrapped);
    expect(body, contains('ua:'));
  });

  test('/play 上游重复 cache-control 不把分片变成 502', () async {
    final target = 'http://127.0.0.1:${upstream.port}/dup-cache.mp4';
    final body = await get(relay.playUrl(target));
    expect(body, 'dup-cache-ok');
  });

  test('/file 按应用数据目录提供本地文件', () async {
    final body = await get('${relay.baseUrl}/file/hello.txt');
    expect(body, 'local-file-ok');
  });

  test('/proxy?do=ck 应答 ok（加固壳据此识别 9978 宿主代理）', () async {
    expect(await get('${relay.baseUrl}/proxy?do=ck'), 'ok');
  });

  test('壳路由 do=hmys 原样转发到常驻 JVM 并透传 Range', () async {
    final query = Uri(
      queryParameters: {
        'do': 'hmys',
        'type': 'm3u8',
        'url': 'aHR0cHM6Ly9leGFtcGxlLmNvbS9hLm0zdTg=',
        'ck': 'abc',
        'sign': 'def',
      },
    ).query;
    final result = await fetch(
      '${relay.baseUrl}/proxy?$query',
      headers: const {'Range': 'bytes=0-10'},
    );
    expect(result.status, 200);
    expect(utf8.decode(result.bytes), 'jvm:$query|range=bytes=0-10');
  });

  test('/proxy?do=live 解 base64url 并原样回传', () async {
    final liveUrl = 'http://127.0.0.1:${upstream.port}/live.txt';
    final ext = base64Url.encode(utf8.encode(liveUrl)).replaceAll('=', '');
    final body = await get('${relay.baseUrl}/proxy?do=live&type=txt&ext=$ext');
    expect(body, contains('CCTV1'));
  });

  test('/play?dav= 注入 Basic Authorization', () async {
    final target = 'http://127.0.0.1:${upstream.port}/dav-only';
    final wrapped = wrapDavPlayUrl(relay.baseUrl, target, 'srv-1');
    expect(await get(wrapped), 'auth:Basic dGVzdDp0ZXN0');
    // 未知服务器不注入（保持无认证）。
    final anonymous = wrapDavPlayUrl(relay.baseUrl, target, 'srv-x');
    expect(await get(anonymous), 'auth:null');
  });

  test('/bt 按 Range 取流并做首片门控', () async {
    final result = await fetch(
      '${relay.baseUrl}/bt/$hash/1',
      headers: {'range': 'bytes=0-1023'},
    );
    expect(result.status, 206);
    expect(result.headers.value('content-range'), 'bytes 0-1023/4096');
    expect(result.bytes.length, 1024);
    expect(result.bytes[0], 0);
    expect(result.bytes[1], 1);
    expect(bt.gates.first, (0, 1023));
  });

  test('/bt 无 Range 时回整段', () async {
    final result = await fetch('${relay.baseUrl}/bt/$hash/1');
    expect(result.status, 200);
    expect(result.bytes.length, 4096);
  });

  test('/bt 会话不存在 → 404；门控失败 → 503', () async {
    final missing = await fetch('${relay.baseUrl}/bt/$hash/2');
    expect(missing.status, 404);
    bt.ready = false;
    final blocked = await fetch(
      '${relay.baseUrl}/bt/$hash/1',
      headers: {'range': 'bytes=0-99'},
    );
    expect(blocked.status, 503);
    bt.ready = true;
  });
}
