import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/vod.dart';
import 'package:kniephos/services/player/auto_line_switch.dart';

Episode _ep(String name) => Episode(name: name, url: '/$name');

void main() {
  group('episodeSignature', () {
    test('第 N 集 / 方括号 / SxxExx 归一成 nN', () {
      expect(episodeSignature('第16集'), 'n16');
      expect(episodeSignature('【16】'), 'n16');
      expect(episodeSignature('S01E16'), 'n16');
      expect(episodeSignature('16'), 'n16');
      expect(episodeSignature('第 3 期'), 'n3');
    });

    test('日期型综艺不把年份当集号', () {
      final a = episodeSignature('2024-01-01期');
      final b = episodeSignature('2024/01/01期');
      expect(a, isNot(startsWith('n')));
      expect(a, b);
    });

    test('普通片名保留归一文本', () {
      expect(episodeSignature('正片'), '正片');
      expect(episodeSignature('HD'), 'hd');
    });
  });

  group('matchEpisodeIndex', () {
    final episodes = [_ep('第1集'), _ep('第2集'), _ep('第16集')];

    test('按集号匹配', () {
      expect(matchEpisodeIndex(episodes, '【16】', 0), 2);
      expect(matchEpisodeIndex(episodes, '第 2 集', 0), 1);
    });

    test('目标集不存在时不退回第 0 集', () {
      final short = [_ep('第1集'), _ep('第2集')];
      expect(matchEpisodeIndex(short, '第16集', 0), -1);
    });

    test('电影类集名退回同下标', () {
      final movie = [_ep('正片')];
      expect(matchEpisodeIndex(movie, 'HD', 0), 0);
    });
  });

  group('nextLineCandidates', () {
    test('从当前线路之后循环一圈，不包含当前线路', () {
      expect(nextLineCandidates(['专享', '专用', '专线', '高清'], '专用'), [
        '专线',
        '高清',
        '专享',
      ]);
    });

    test('当前线路不在列表时全部尝试', () {
      expect(nextLineCandidates(['A', 'B'], 'X'), ['A', 'B']);
    });

    test('只有一条线路时没有候选', () {
      expect(nextLineCandidates(['A'], 'A'), isEmpty);
    });
  });

  test('titleSignature 去掉空白、标点与年份括号', () {
    expect(titleSignature(' 墨雨云间 '), '墨雨云间');
    expect(titleSignature('墨雨云间(2024)'), '墨雨云间');
    expect(titleSignature('墨雨云间【2024】'), '墨雨云间');
    expect(titleSignature('墨雨云间·2024'), '墨雨云间2024');
  });
}
