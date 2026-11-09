import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/net/app_http.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/models/vod.dart';
import 'package:kniephos/services/cms_source.dart';
import 'package:kniephos/services/jar_spider_service.dart';
import 'package:kniephos/services/js_spider_service.dart';
import 'package:kniephos/services/py_spider_service.dart';
import 'package:kniephos/services/search_service.dart';
import 'package:kniephos/services/source_service.dart';

class _FakeCms extends CmsSource {
  _FakeCms(this.itemsBySite) : super(AppHttp());

  final Map<String, List<VodItem>> itemsBySite;
  int calls = 0;

  @override
  Future<List<VodItem>> search(SourceBean site, String keyword) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return itemsBySite[site.key] ?? const [];
  }
}

class _FakeJs extends JsSpiderService {
  _FakeJs(this.itemsBySite);

  final Map<String, List<VodItem>> itemsBySite;

  @override
  Future<List<VodItem>> search(SourceBean site, String keyword) async =>
      itemsBySite[site.key] ?? const [];
}

SourceService _service(CmsSource cms) => SourceService(
  cms,
  JsSpiderService(),
  PySpiderService(),
  JarSpiderService(),
);

VodItem _item(String name, {String id = '1'}) => VodItem(
  id: id,
  name: name,
  year: '2026',
  sourceKey: 'a',
);

void main() {
  test('同源同关键词命中短 TTL 缓存，clearCache 后重新请求', () async {
    final cms = _FakeCms({'a': [_item('测试片名')]});
    final service = SearchService(_service(cms));
    final site = SourceBean(
      key: 'a',
      name: 'A',
      type: 0,
      api: 'https://example.com/api.php/provide/vod',
    );

    final first = await service.search('测试片名', [site]).toList();
    expect(first.last.finished, isTrue);
    expect(first.last.items.length, 1);
    expect(cms.calls, 1);

    final second = await service.search('测试片名', [site]).toList();
    expect(second.last.finished, isTrue);
    expect(second.last.items.length, 1);
    expect(cms.calls, 1);

    service.clearCache();
    await service.search('测试片名', [site]).toList();
    expect(cms.calls, 2);
  });

  test('CMS 结果排在慢的蜘蛛源前面', () async {
    final cms = _FakeCms({
      'cms': [
        const VodItem(
          id: 'c1',
          name: '电影 A',
          year: '2026',
          sourceKey: 'cms',
          sourceName: 'CMS',
        ),
      ],
    });
    final js = _FakeJs({
      'js': [
        const VodItem(
          id: 'j1',
          name: '电影 B',
          year: '2026',
          sourceKey: 'js',
          sourceName: 'JS',
        ),
      ],
    });
    final service = SearchService(
      SourceService(cms, js, PySpiderService(), JarSpiderService()),
    );
    final sites = [
      SourceBean(
        key: 'cms',
        name: 'CMS',
        type: 0,
        api: 'https://example.com/api.php/provide/vod',
      ),
      SourceBean(
        key: 'js',
        name: 'JS',
        type: 3,
        api: 'https://example.com/spider.js',
      ),
    ];

    final events = await service.search('电影', sites).toList();
    final last = events.last;
    expect(last.finished, isTrue);
    expect(last.items.length, 2);
    expect(last.items.first.sourceKey, 'cms');
    expect(last.items.last.sourceKey, 'js');
  });

  test('结果按名称相关度排序：精确 > 前缀 > 包含 > 无关', () async {
    final cms = _FakeCms({
      'cms': [
        const VodItem(
          id: 'c1',
          name: '201秒带你回看虞君的故事',
          sourceKey: 'cms',
          sourceName: 'CMS',
        ),
        const VodItem(
          id: 'c2',
          name: '20261026【玉置秋】直播 丞磊徐若晗',
          sourceKey: 'cms',
          sourceName: 'CMS',
        ),
        const VodItem(
          id: 'c3',
          name: '玉置秋 第1集',
          sourceKey: 'cms',
          sourceName: 'CMS',
        ),
      ],
    });
    final js = _FakeJs({
      'js': [
        const VodItem(
          id: 'j1',
          name: '玉置秋',
          sourceKey: 'js',
          sourceName: 'JS',
        ),
      ],
    });
    final service = SearchService(
      SourceService(cms, js, PySpiderService(), JarSpiderService()),
    );
    final sites = [
      SourceBean(
        key: 'cms',
        name: 'CMS',
        type: 0,
        api: 'https://example.com/api.php/provide/vod',
      ),
      SourceBean(
        key: 'js',
        name: 'JS',
        type: 3,
        api: 'https://example.com/spider.js',
      ),
    ];

    final events = await service.search('玉置秋', sites).toList();
    final last = events.last;
    expect(last.finished, isTrue);
    expect(
      [for (final item in last.items) item.id],
      ['j1', 'c3', 'c2', 'c1'],
    );
  });

  test('跨源合并按名称 + 年份去重并保留每源结果', () async {
    final cms = _FakeCms({
      'a': [_item('同名电影', id: 'a1')],
      'b': [_item('同名电影', id: 'b1')],
    });
    final service = SearchService(_service(cms));
    final sites = [
      SourceBean(
        key: 'a',
        name: 'A',
        type: 0,
        api: 'https://example.com/a',
      ),
      SourceBean(
        key: 'b',
        name: 'B',
        type: 0,
        api: 'https://example.com/b',
      ),
    ];

    final events = await service.search('同名电影', sites).toList();
    final last = events.last;
    expect(last.finished, isTrue);
    expect(last.items.length, 1);
    expect(last.items.first.sameFromOtherSources, 1);
    expect(last.sourceItems['a']?.length, 1);
    expect(last.sourceItems['b']?.length, 1);
    expect(cms.calls, 2);
  });
}
