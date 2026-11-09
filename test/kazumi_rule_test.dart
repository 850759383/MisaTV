import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/kazumi/kazumi_rule.dart';
import 'package:kniephos/services/kazumi/kazumi_source.dart';

void main() {
  group('Kazumi 规则解析', () {
    test('纯 XPath 规则（api 5）', () {
      final rule = KazumiRule.fromJson({
        'api': '5',
        'type': 'anime',
        'name': 'MXdm',
        'version': '2.4',
        'baseURL': 'https://www.dcc3.com',
        'searchURL': 'https://www.dcc3.com/search/?wd=@keyword',
        'searchList': "//div[contains(@class, 'search')]/ul/li",
        'searchName': '//h3/a',
        'searchResult': '//h3/a',
        'chapterRoads': "//div[@class='playlist']/div[@class='row']/ul",
        'chapterResult': '//li/a',
      });
      expect(rule.valid, isTrue);
      expect(rule.searchMode, 'xpath');
      expect(rule.chapterMode, 'xpath');
      expect(rule.key, 'kazumi_mxdm');
      final bean = rule.toSourceBean();
      expect(bean.type, 5);
      expect(bean.isKazumi, isTrue);
      expect(bean.ext, contains('"chapterRoads"'));
    });

    test('API + XPath 混合规则（api 9）', () {
      final rule = KazumiRule.fromJson({
        'api': '9',
        'name': 'TvTFun',
        'version': '1.3',
        'baseURL': 'https://www.tvtfun.net',
        'searchMode': 'api',
        'chapterMode': 'xpath',
        'chapterRoads': "//ol[@class*='tvt-watch-episodes']",
        'chapterResult': '//li/a',
        'searchApiConfig': {
          'request': {
            'method': 'GET',
            'url': 'https://www.tvtfun.net/api/client/anime',
            'query': {'keyword': '@keyword', 'page': 1},
          },
          'listPath': r'$.data.items[*]',
          'namePath': r'$.name',
          'sourcePath': r'$.slug',
          'sourceTemplate': 'https://www.tvtfun.net/watch/@source/1',
        },
      });
      expect(rule.valid, isTrue);
      expect(rule.searchMode, 'api');
      expect(rule.chapterMode, 'xpath');
      expect(rule.searchApi!.sourceTemplate, contains('@source'));
      expect(rule.searchApi!.request.query['keyword'], '@keyword');
    });

    test('分离字符串选集规则（giriGiriLove）', () {
      final rule = KazumiRule.fromJson({
        'api': '9',
        'name': 'giriGiriLove',
        'chapterMode': 'api',
        'searchMode': 'api',
        'searchApiConfig': {
          'request': {
            'method': 'GET',
            'url': 'https://m3u8.girigirilove.com/api.php/Vod/get_list',
          },
          'listPath': r'$.info.rows[*]',
          'namePath': r'$.vod_name',
          'sourcePath': r'$.vod_id',
        },
        'chapterApiConfig': {
          'request': {
            'method': 'GET',
            'url': 'https://m3u8.girigirilove.com/api.php/Vod/get_detail',
            'query': {'vod_id': '@source'},
          },
          'format': 'delimited',
          'roadNamesPath': r'$.info.vod_play_from',
          'roadEpisodesPath': r'$.info.vod_play_url',
          'roadSeparator': r'$$$',
          'episodeSeparator': '#',
          'fieldSeparator': r'$',
        },
      });
      expect(rule.chapterMode, 'api');
      expect(rule.chapterApi!.roadSeparator, r'$$$');
      expect(rule.chapterApi!.episodeSeparator, '#');
    });
  });

  group('Kazumi XPath 解析', () {
    final rule = KazumiRule.fromJson({
      'name': 'TestXPath',
      'baseURL': 'https://example.com/',
      'searchURL': 'https://example.com/search?wd=@keyword',
      'searchList': "//ul[@class='list']/li",
      'searchName': '//h3/a',
      'searchResult': '//h3/a',
      'chapterRoads': "//div[@class='playlist']",
      'chapterResult': '//li/a',
    });

    test('搜索结果与相对地址归一', () {
      const html = '''
<html><body>
<ul class="list">
  <li><h3><a href="/detail/1.htm">紫罗兰永恒花园</a></h3></li>
  <li><h3><a href="/detail/2.htm">进击的巨人</a></h3></li>
</ul>
</body></html>''';
      final items = KazumiSource.parseSearchHtml(
        rule,
        'https://example.com/search?wd=x',
        html,
        sourceKey: 'kazumi_test',
        sourceName: 'TestXPath',
      );
      expect(items, hasLength(2));
      expect(items[0].name, '紫罗兰永恒花园');
      expect(items[0].id, 'https://example.com/detail/1.htm');
      expect(items[0].sourceKey, 'kazumi_test');
    });

    test('多线路选集与相对地址归一', () {
      const html = '''
<html><body>
<div class="playlist"><ul>
  <li><a href="/play/1-1.html">第1集</a></li>
  <li><a href="/play/1-2.html">第2集</a></li>
</ul></div>
<div class="playlist"><ul>
  <li><a href="/play/2-1.html">第1集</a></li>
</ul></div>
</body></html>''';
      final roads = KazumiSource.parseChapterHtml(
        rule,
        'https://example.com/detail/1.htm',
        html,
      );
      expect(roads.keys, ['线路1', '线路2']);
      expect(roads['线路1'], hasLength(2));
      expect(roads['线路1']![0].url, 'https://example.com/play/1-1.html');
      expect(roads['线路2'], hasLength(1));
    });
  });

  group('Kazumi API 解析', () {
    test('搜索接口 JSONPath + sourceTemplate', () {
      final rule = KazumiRule.fromJson({
        'name': 'TestApi',
        'searchMode': 'api',
        'searchApiConfig': {
          'request': {'method': 'GET', 'url': 'https://a.com/api'},
          'listPath': r'$.list[*]',
          'namePath': r'$.name',
          'sourcePath': r'$.id',
          'sourceTemplate': 'https://a.com/detail/@source.html',
        },
      });
      final items = KazumiSource.parseSearchJson(
        rule,
        {
          'list': [
            {'id': 11, 'name': 'A'},
            {'id': 12, 'name': 'B'},
          ],
        },
        sourceKey: 'kazumi_test',
        sourceName: 'TestApi',
      );
      expect(items, hasLength(2));
      expect(items[0].id, 'https://a.com/detail/11.html');
      expect(items[1].name, 'B');
    });

    test('分隔字符串选集', () {
      final rule = KazumiRule.fromJson({
        'name': 'TestDelimited',
        'chapterMode': 'api',
        'chapterApiConfig': {
          'request': {'method': 'GET', 'url': 'https://a.com/detail'},
          'format': 'delimited',
          'roadNamesPath': r'$.info.vod_play_from',
          'roadEpisodesPath': r'$.info.vod_play_url',
          'roadSeparator': r'$$$',
          'episodeSeparator': '#',
          'fieldSeparator': r'$',
        },
      });
      final roads = KazumiSource.parseChapterJson(rule, {
        'info': {
          'vod_play_from': 'uk\$\$\$qq',
          'vod_play_url':
              '第1集\$https://a.com/1.m3u8#第2集\$https://a.com/2.m3u8'
              '\$\$\$第1集\$https://b.com/1.m3u8',
        },
      });
      expect(roads.keys, ['uk', 'qq']);
      expect(roads['uk'], hasLength(2));
      expect(roads['uk']![0].url, 'https://a.com/1.m3u8');
      expect(roads['qq'], hasLength(1));
      expect(roads['qq']![0].url, 'https://b.com/1.m3u8');
    });
  });

  group('Kazumi 首页新番', () {
    final calendar = {
      'code': 0,
      'result': [
        {
          'date': '11-02',
          'day_of_week': 1,
          'episodes': [
            {
              'title': '测试动画',
              'cover': 'https://i0.hdslb.com/a.jpg',
              'pub_index': '第1话',
            },
          ],
        },
        {
          'date': '11-04',
          'day_of_week': 3,
          'episodes': [
            {'title': 'Another', 'cover': 'https://i0.hdslb.com/y.jpg'},
            {'title': '测试动画', 'cover': 'https://i0.hdslb.com/z.jpg'},
            {'title': '测试动画', 'cover': 'https://i0.hdslb.com/z.jpg'},
          ],
        },
      ],
    };

    test('按星期过滤、去重并保留集数标记', () {
      final items = KazumiSource.parseBiliTimeline(
        calendar,
        sourceKey: 'kazumi_test',
        sourceName: 'Test',
        dayId: 'day3',
      );
      expect(items, hasLength(2));
      expect(items[0].name, 'Another');
      expect(items[0].id, 'Another');
      expect(items[0].pic, 'https://i0.hdslb.com/y.jpg');
      // 同一天重名条目只保留一条。
      expect(items[1].name, '测试动画');
      expect(items[1].remarks, isEmpty);
    });

    test('名称作为 id，集数进入角标', () {
      final items = KazumiSource.parseBiliTimeline(
        calendar,
        sourceKey: 'kazumi_test',
        sourceName: 'Test',
        dayId: 'day1',
      );
      expect(items.single.name, '测试动画');
      expect(items.single.id, '测试动画');
      expect(items.single.pic, 'https://i0.hdslb.com/a.jpg');
      expect(items.single.remarks, '第1话');
    });
  });

  group('Kazumi Bangumi 榜单', () {
    final season = [
      {
        'day_of_week': 1,
        'subjects': [
          {
            'subject': {
              'id': 1,
              'name': 'Japanese Name',
              'nameCN': '中文名',
              'date': '2026-10-05',
              'rating': {'score': 7.4},
              'images': {
                'common': 'https://api.bgm.tv/v0/subjects/1/image?type=large',
              },
            },
          },
        ],
      },
      {
        'day_of_week': 3,
        'subjects': [
          {
            'subject': {
              'id': 2,
              'name': 'Only Japanese',
              'images': {'common': 'https://lain.bgm.tv/pic/cover/l/x.jpg'},
            },
          },
        ],
      },
    ];

    test('季度表按星期过滤，中文名优先，封面走 wsrv 代理', () {
      final items = KazumiSource.parseBangumiSeason(
        season,
        sourceKey: 'kazumi_test',
        sourceName: 'Test',
        dayId: 'day1',
      );
      expect(items.single.name, '中文名');
      expect(items.single.id, '中文名');
      expect(items.single.year, '2026');
      expect(items.single.remarks, '7.4分');
      expect(items.single.pic, startsWith('https://wsrv.nl/?url='));
      expect(items.single.pic, contains('api.bgm.tv'));
    });

    test('没有中文名时回退原名', () {
      final items = KazumiSource.parseBangumiSeason(
        season,
        sourceKey: 'kazumi_test',
        sourceName: 'Test',
        dayId: 'day3',
      );
      expect(items.single.name, 'Only Japanese');
      expect(items.single.pic, startsWith('https://wsrv.nl/?url='));
    });

    test('热门榜 data 数组解析', () {
      final items = KazumiSource.parseBangumiSubjects(
        {
          'data': [
            {
              'id': 3,
              'name': 'Hot',
              'nameCN': '热门番',
              'info': '12话 / 2026年10月3日',
              'rating': {'score': 8.2},
              'images': {'large': 'https://lain.bgm.tv/pic/cover/l/h.jpg'},
            },
          ],
        },
        sourceKey: 'kazumi_test',
        sourceName: 'Test',
      );
      expect(items.single.name, '热门番');
      expect(items.single.year, '2026');
      expect(items.single.remarks, '8.2分');
    });
  });
}
