/// 首页展示的影视台词模型与离线兜底台词库。
///
/// 在线台词由 `QuoteService` 从一言（Hitokoto）公开语句包拉取并缓存；
/// 这里的内置列表只在「无缓存 + 网络不可用」时兜底。
class MovieQuote {
  const MovieQuote({required this.line, required this.title});

  final String line;
  final String title;

  /// 展示格式：台词——《片名》。
  String get display => '$line——《$title》';

  /// 点击后跳转搜索使用的关键词：优先取片名里的中文部分（去掉《》与英文副标题）。
  String get searchKeyword {
    final cleaned = title.replaceAll(RegExp('[《》]'), '').trim();
    for (final part in cleaned.split(RegExp(r'\s+'))) {
      if (containsChinese(part)) return part;
    }
    return cleaned;
  }
}

/// 是否包含中文（用于过滤纯外文台词）。
bool containsChinese(String text) =>
    text.runes.any((rune) => rune >= 0x4E00 && rune <= 0x9FFF);

const List<MovieQuote> movieQuotes = <MovieQuote>[
  MovieQuote(line: '你的心脏不会呐喊吗', title: '海贼王'),
  MovieQuote(line: '人的梦想是不会结束的', title: '海贼王'),
  MovieQuote(line: '生活就像一盒巧克力，你永远不知道下一颗是什么味道', title: '阿甘正传'),
  MovieQuote(line: '希望是美好的，也许是人间至善，而美好的事物永不消逝', title: '肖申克的救赎'),
  MovieQuote(line: '有些鸟儿是关不住的，它们的每一片羽毛都闪耀着自由的光辉', title: '肖申克的救赎'),
  MovieQuote(line: '要么忙着活，要么忙着死', title: '肖申克的救赎'),
  MovieQuote(line: '曾经有一份真诚的爱情放在我面前，我没有珍惜', title: '大话西游'),
  MovieQuote(line: '做人如果没有梦想，跟咸鱼有什么分别', title: '少林足球'),
  MovieQuote(line: '我命由我不由天', title: '哪吒之魔童降世'),
  MovieQuote(line: '这世上只有一种病，穷病', title: '我不是药神'),
  MovieQuote(line: '我们一路奋战，不是为了改变世界，而是为了不让世界改变我们', title: '熔炉'),
  MovieQuote(line: '人生就是不断地放下，但最痛心的是，没来得及好好道别', title: '少年派的奇幻漂流'),
  MovieQuote(line: '世界这么大，人生这么长，总会有这么一个人，让你想要温柔地对待', title: '哈尔的移动城堡'),
  MovieQuote(line: '我不知道将去何方，但我已在路上', title: '千与千寻'),
  MovieQuote(line: '人生就是一列开往坟墓的列车，路途上会有很多站，很难有人可以自始至终陪着走完', title: '千与千寻'),
  MovieQuote(line: '只有一个人在旅行时，才听得到自己的声音', title: '魔女宅急便'),
  MovieQuote(line: '越是试着忘记，越是记得深刻', title: '天空之城'),
  MovieQuote(line: '我们的孤独就像天空中漂浮的城市，仿佛是一个秘密，却无从述说', title: '天空之城'),
  MovieQuote(line: '如果你不出去走走，你就会以为这就是世界', title: '天堂电影院'),
  MovieQuote(line: '人生和电影不同，人生辛苦多了', title: '天堂电影院'),
  MovieQuote(line: '真正的死亡是世界上再没有一个人记得你', title: '寻梦环游记'),
  MovieQuote(line: '家人是比梦想更重要的事情', title: '寻梦环游记'),
  MovieQuote(line: '生活总会有点不顺意，我们都会犯错，重要的是你开始改变', title: '疯狂动物城'),
  MovieQuote(line: '不要让别人告诉你，你不能做什么', title: '当幸福来敲门'),
  MovieQuote(line: '如果你有梦想，就要守护它', title: '当幸福来敲门'),
  MovieQuote(line: '所有的大人都曾经是小孩，虽然只有少数人记得', title: '小王子'),
  MovieQuote(line: '如果我没有刀，我就不能保护你；如果我有刀，我就不能拥抱你', title: '剪刀手爱德华'),
  MovieQuote(line: '我们笑着说再见，却深知再见遥遥无期', title: '海上钢琴师'),
  MovieQuote(line: '有些人浅薄，有些人金玉其外败絮其中，但总有一天，你会遇到一个彩虹般绚丽的人', title: '怦然心动'),
  MovieQuote(line: '愿你在被打击时，记起你的珍贵，抵抗恶意', title: '无问西东'),
  MovieQuote(line: '爱你所爱，行你所行，听从你心，无问西东', title: '无问西东'),
  MovieQuote(line: '不抛弃，不放弃', title: '士兵突击'),
  MovieQuote(line: '我等了三年，就是要等一个机会，我要争一口气', title: '英雄本色'),
  MovieQuote(line: '出来混，迟早要还的', title: '无间道'),
  MovieQuote(line: '对不起，我是警察', title: '无间道'),
  MovieQuote(line: '活下去，像牲口一样活下去', title: '芙蓉镇'),
  MovieQuote(line: '不要温和地走进那个良夜', title: '星际穿越'),
  MovieQuote(line: '我要你知道，在这个世界上总有一个人是等着你的', title: '半生缘'),
];
