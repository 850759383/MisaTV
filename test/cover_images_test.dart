import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/discover/cover_images.dart';

void main() {
  test('同片名并发只查一次，结果缓存复用', () async {
    var calls = 0;
    final resolver = CoverResolver(
      spacing: Duration.zero,
      lookup: (name, year) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'https://img.test/$name.jpg';
      },
    );
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) resolver.resolve('流浪地球', year: '2019'),
    ]);
    expect(calls, 1);
    expect(results.toSet(), {'https://img.test/流浪地球.jpg'});
    // 完成后再次请求命中缓存。
    await resolver.resolve('流浪地球', year: '2019');
    expect(calls, 1);
  });

  test('查不到也缓存，不会反复打豆瓣', () async {
    var calls = 0;
    final resolver = CoverResolver(
      spacing: Duration.zero,
      lookup: (name, year) async {
        calls++;
        return null;
      },
    );
    expect(await resolver.resolve('不存在的片'), isNull);
    expect(await resolver.resolve('不存在的片'), isNull);
    expect(calls, 1);
  });

  test('并发上限生效', () async {
    var active = 0;
    var peak = 0;
    final resolver = CoverResolver(
      maxConcurrent: 2,
      spacing: Duration.zero,
      lookup: (name, year) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        active--;
        return 'https://img.test/$name.jpg';
      },
    );
    final results = await Future.wait([
      for (var i = 0; i < 8; i++) resolver.resolve('片$i'),
    ]);
    expect(peak, lessThanOrEqualTo(2));
    expect(results.where((e) => e != null).length, 8);
  });

  test('空片名不发起查询', () async {
    var calls = 0;
    final resolver = CoverResolver(
      spacing: Duration.zero,
      lookup: (name, year) async {
        calls++;
        return 'https://img.test/x.jpg';
      },
    );
    expect(await resolver.resolve('   '), isNull);
    expect(calls, 0);
  });

  test('doubanCoverUrl 只接受 http(s) 地址；中继未启动时原样返回', () {
    expect(doubanCoverUrl(''), isNull);
    expect(doubanCoverUrl('   '), isNull);
    expect(doubanCoverUrl('不是地址'), isNull);
    expect(doubanCoverUrl('ftp://img.test/x.jpg'), isNull);
    expect(doubanCoverUrl('https://img.test/x.jpg'), 'https://img.test/x.jpg');
  });
}
