import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/net/app_http.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/models/vod.dart';
import 'package:kniephos/services/cms_source.dart';
import 'package:kniephos/services/jar_spider_service.dart';
import 'package:kniephos/services/js_spider_service.dart';
import 'package:kniephos/services/parse/parse_service.dart';
import 'package:kniephos/services/player/external_playlist_io.dart';
import 'package:kniephos/services/py_spider_service.dart';
import 'package:kniephos/services/source_service.dart';

void main() {
  late Directory dir;
  late ExternalPlaylistService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kniephos-ext-list-');
    final http = AppHttp();
    service = ExternalPlaylistService(
      sourceService: SourceService(
        CmsSource(http),
        JsSpiderService(),
        PySpiderService(),
        JarSpiderService(),
      ),
      parseService: ParseService(http),
      config: () => const SiteConfig(),
      jarReady: () => false,
      preparePlay: (play, {forceRelay = false}) => play,
      unwrapPlayPage: (play) async => play,
      warmUp: (url) async => true,
      holdExternal: () {},
      supportDir: dir.path,
      relayBaseUrl: () => 'http://127.0.0.1:9978',
    );
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('选集 M3U：当前集排第一，且复用已取好的播放地址', () async {
    const episodes = [
      Episode(name: '第1集', url: 'http://a.cn/1.m3u8'),
      Episode(name: '第2集', url: 'http://a.cn/2.m3u8'),
      Episode(name: '第3集', url: 'http://a.cn/3.m3u8'),
    ];
    final path = await service.createPlaylist(
      site: const SourceBean(key: 's', name: 'S', type: 1, api: 'http://a.cn'),
      flag: '线路一',
      episodes: episodes,
      currentIndex: 1,
      currentUrl: 'http://127.0.0.1:9978/play?url=current',
    );
    expect(path, isNotNull);

    final lines = (await File(path!).readAsString()).trim().split('\n');
    expect(lines.first, '#EXTM3U');
    expect(lines[1], '#EXTINF:-1,第2集');
    expect(lines[2], 'http://127.0.0.1:9978/play?url=current');
    expect(lines[3], '#EXTINF:-1,第3集');
    expect(lines[4], matches(RegExp(r'/ext/[^/]+/2$')));
    expect(lines[5], '#EXTINF:-1,第1集');
    expect(lines[6], matches(RegExp(r'/ext/[^/]+/0$')));

    // 当前集已经取好链：中继直接返回它，不再跑一次蜘蛛。
    final token = Uri.parse(lines[4]).pathSegments[1];
    expect(
      await service.resolveEpisode(token, 1),
      'http://127.0.0.1:9978/play?url=current',
    );
  });
}
