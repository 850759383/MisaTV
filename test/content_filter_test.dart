import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/models/vod.dart';
import 'package:kniephos/services/content_filter.dart';

void main() {
  group('ContentFilterSettings', () {
    test('默认：关闭 + 内置屏蔽词', () {
      final s = ContentFilterSettings.defaults();
      expect(s.enabled, isFalse);
      expect(s.active, isFalse);
      expect(s.keywords, contains('R18'));
      expect(s.keywords, contains('18禁'));
      expect(s.keywords, contains('成人'));
      expect(s.keywords, contains('伦理片'));
      expect(s.keywords, contains('🔞'));
      expect(normalizeContentFilterKeywords(s.keywords), s.keywords);
    });

    test('匹配：大小写不敏感，关闭 / 空关键词时不过滤', () {
      final on = ContentFilterSettings.defaults().copyWith(enabled: true);
      expect(on.active, isTrue);
      expect(on.matches('【R18】某某'), isTrue);
      expect(on.matches('r18 测试'), isTrue);
      expect(on.matches('NSFW 合集'), isTrue);
      expect(on.matches('nsfw'), isTrue);
      expect(on.matches('普通电影'), isFalse);
      expect(on.matches(''), isFalse);

      expect(
        ContentFilterSettings.defaults().matches('R18'),
        isFalse,
        reason: '默认关闭',
      );
      expect(
        ContentFilterSettings.defaults()
            .copyWith(enabled: true, keywords: const [])
            .matches('R18'),
        isFalse,
        reason: '显式清空关键词后不过滤',
      );
      expect(
        ContentFilterSettings.fromJson({'enabled': true, 'keywords': const []})
            .active,
        isFalse,
      );
    });

    test('关键词归一：行 / 逗号 / 顿号 / 分号切分，去空白与大小写重复', () {
      final words = normalizeContentFilterKeywords([
        ' R18 \n18禁,成人，情色、色情;NSFW ',
        'r18',
        '',
        '  ',
      ]);
      expect(words, ['R18', '18禁', '成人', '情色', '色情', 'NSFW']);
    });

    test('JSON 往返 / 旧配置沿用默认词 / 非法 JSON 回退', () {
      final s = ContentFilterSettings(
        enabled: true,
        keywords: normalizeContentFilterKeywords(['成人', 'R18']),
      );
      final back = ContentFilterSettings.fromJsonString(s.toJsonString());
      expect(back.enabled, isTrue);
      expect(back.keywords, ['成人', 'R18']);

      final legacy = ContentFilterSettings.fromJson({'enabled': '1'});
      expect(legacy.enabled, isTrue);
      expect(legacy.keywords, defaultContentFilterKeywords);

      expect(ContentFilterSettings.fromJsonString('{').enabled, isFalse);
      expect(
        ContentFilterSettings.fromJsonString(null).keywords,
        defaultContentFilterKeywords,
      );
      expect(
        ContentFilterSettings.fromJson({
          'enabled': true,
          'keywords': 'R18\n18+',
        }).keywords,
        ['R18', '18+'],
      );
    });

    test('blocksVod 命中名称 / 备注 / 类型 / 地区 / 标签 / 来源', () {
      final filter = ContentFilterSettings.defaults().copyWith(enabled: true);
      VodItem item({
        String name = '普通电影',
        String remarks = '',
        String type = '',
        String area = '',
        String tag = '',
        String sourceName = '',
      }) => VodItem(
        id: '1',
        name: name,
        remarks: remarks,
        type: type,
        area: area,
        tag: tag,
        sourceName: sourceName,
      );

      expect(filter.blocksVod(item(name: 'R18 某某')), isTrue);
      expect(filter.blocksVod(item(remarks: '更新至 18禁')), isTrue);
      expect(filter.blocksVod(item(type: '情色片')), isTrue);
      expect(filter.blocksVod(item(area: '成人频道')), isTrue);
      expect(filter.blocksVod(item(tag: 'NSFW')), isTrue);
      expect(filter.blocksVod(item(sourceName: 'adult 站')), isTrue);
      expect(filter.blocksVod(item(name: '流浪地球', remarks: 'HD')), isFalse);
      expect(
        ContentFilterSettings.defaults().blocksVod(item(name: 'R18')),
        isFalse,
        reason: '关闭时不过滤',
      );
    });

    test('旧版默认词升级补上「伦理片」，自定义列表保持原样', () {
      final legacy = ContentFilterSettings.fromJson({
        'enabled': true,
        'keywords': const [
          'R18',
          '18+',
          '18禁',
          'NSFW',
          'adult',
          '成人',
          '情色',
          '色情',
          '🔞',
        ],
      });
      expect(legacy.keywords, contains('伦理片'));

      final custom = ContentFilterSettings.fromJson({
        'enabled': true,
        'keywords': const ['R18', '成人'],
      });
      expect(custom.keywords, ['R18', '成人']);
      expect(custom.keywords, isNot(contains('伦理片')));
    });

    test('分类名命中：伦理片从分类栏隐藏，类型「伦理」也拦截', () {
      final filter = ContentFilterSettings(
        enabled: true,
        keywords: normalizeContentFilterKeywords(['伦理片']),
      );
      const blocked = SortClass(id: '20', name: '伦理片');
      const normal = SortClass(id: '1', name: '电影');
      expect(filter.blocksClass(blocked), isTrue);
      expect(filter.blocksClass(normal), isFalse);
      expect(filter.copyWith(enabled: false).blocksClass(blocked), isFalse);

      VodItem item(String type) => VodItem(id: '1', name: '某片', type: type);
      expect(filter.blocksVod(item('伦理')), isTrue);
      expect(filter.blocksVod(item('伦理片')), isTrue);
      expect(filter.blocksVod(item('科幻')), isFalse);
      expect(
        filter.blocksVod(const VodItem(id: '2', name: '流浪地球', type: '科幻')),
        isFalse,
      );
    });

    test('默认屏蔽词即可拦截「伦理片」分类', () {
      final filter = ContentFilterSettings.defaults().copyWith(enabled: true);
      expect(
        filter.blocksClass(const SortClass(id: '20', name: '伦理片')),
        isTrue,
      );
      expect(
        filter.blocksVod(const VodItem(id: '1', name: '某片', type: '伦理')),
        isTrue,
      );
    });

    test('分类筛选里的「伦理片」选项也要隐藏', () {
      final filter = ContentFilterSettings(
        enabled: true,
        keywords: normalizeContentFilterKeywords(['伦理片']),
      );
      const cls = SortClass(
        id: '1',
        name: '电影',
        filters: [
          FilterGroup(
            key: 'type',
            name: '类型',
            values: [
              FilterOption(tab: '', n: '全部', v: ''),
              FilterOption(tab: '', n: '伦理片', v: '20'),
              FilterOption(tab: '', n: '动作', v: '5'),
            ],
          ),
          FilterGroup(
            key: 'area',
            name: '伦理片',
            values: [FilterOption(tab: '', n: '华语', v: 'cn')],
          ),
          FilterGroup(
            key: 'year',
            name: '年份',
            values: [FilterOption(tab: '', n: '伦理', v: '19')],
          ),
        ],
      );
      final visible = filter.visibleClass(cls);
      expect(visible, isNotNull);
      expect(visible!.name, '电影');
      expect(visible.filters.length, 1);
      expect(visible.filters.single.key, 'type');
      expect(visible.filters.single.values.map((e) => e.n).toList(), [
        '全部',
        '动作',
      ]);

      expect(
        filter.blocksFilterOption(
          const FilterOption(tab: '', n: '伦理片', v: '20'),
        ),
        isTrue,
      );
      expect(
        filter.blocksFilterOption(const FilterOption(tab: '', n: '动作', v: '5')),
        isFalse,
      );

      // 只有一组筛选、且只是组内少了选项时，也必须返回删减后的组。
      const single = SortClass(
        id: '2',
        name: '电影',
        filters: [
          FilterGroup(
            key: 'type',
            name: '类型',
            values: [
              FilterOption(tab: '', n: '全部', v: ''),
              FilterOption(tab: '', n: '伦理片', v: '20'),
            ],
          ),
        ],
      );
      final singleVisible = filter.visibleClass(single);
      expect(singleVisible, isNotNull);
      expect(singleVisible!.filters.single.values.map((e) => e.n).toList(), [
        '全部',
      ]);
    });

    test('blocksDetail / blocksSource', () {
      final filter = ContentFilterSettings.defaults().copyWith(enabled: true);
      const detail = VodDetail(
        id: '1',
        name: '普通剧',
        type: '剧情',
        actor: '某某',
        des: '一段 R18 简介',
      );
      expect(filter.blocksDetail(detail), isTrue);
      expect(
        filter.blocksDetail(const VodDetail(id: '2', name: '普通剧', des: '正常简介')),
        isFalse,
      );

      const site = SourceBean(
        key: 'adult1',
        name: '成人资源',
        type: 1,
        api: 'https://a.test/api',
      );
      const normal = SourceBean(
        key: 'ok',
        name: '普通站点',
        type: 1,
        api: 'https://b.test/api',
      );
      expect(filter.blocksSource(site), isTrue);
      expect(filter.blocksSource(normal), isFalse);
    });

    test('copyWith 只替换指定字段', () {
      final base = ContentFilterSettings.defaults();
      final off = base.copyWith(enabled: true);
      expect(off.enabled, isTrue);
      expect(identical(off.keywords, base.keywords), isTrue);
      final custom = base.copyWith(keywords: const ['x']);
      expect(custom.keywords, ['x']);
      expect(custom.enabled, base.enabled);
    });

    test('关闭密码：加盐摘要可校验，不保存明文', () {
      final hash = hashContentFilterPassword('2468');
      expect(hash, contains(':'));
      expect(hash, isNot(contains('2468')));
      expect(verifyContentFilterPassword('2468', hash), isTrue);
      expect(verifyContentFilterPassword('1357', hash), isFalse);
      expect(verifyContentFilterPassword('2468', 'bad'), isFalse);

      final other = hashContentFilterPassword('2468');
      expect(other, isNot(hash), reason: '每次使用随机盐');

      final settings = ContentFilterSettings.defaults().copyWith(
        enabled: true,
        passwordHash: hash,
      );
      expect(settings.hasPassword, isTrue);
      expect(settings.verifyPassword('2468'), isTrue);
      expect(settings.verifyPassword('1357'), isFalse);
    });

    test('密码随 JSON 保存；旧配置没有密码', () {
      final hash = hashContentFilterPassword('abcd', salt: 'fixed');
      expect(hash, startsWith('fixed:'));
      final settings = ContentFilterSettings.defaults().copyWith(
        enabled: true,
        passwordHash: hash,
      );
      final back = ContentFilterSettings.fromJsonString(
        settings.toJsonString(),
      );
      expect(back.passwordHash, hash);
      expect(back.verifyPassword('abcd'), isTrue);

      final legacy = ContentFilterSettings.fromJson({'enabled': true});
      expect(legacy.hasPassword, isFalse);
      expect(legacy.passwordHash, '');
      expect(legacy.copyWith(enabled: false).passwordHash, '');
    });

    test('JSON 编码稳定', () {
      final s = ContentFilterSettings.defaults().copyWith(enabled: true);
      final decoded = jsonDecode(s.toJsonString()) as Map<String, dynamic>;
      expect(decoded['enabled'], isTrue);
      expect(decoded['keywords'], isA<List>());
    });
  });
}
