/// 从播放文件名 / 资源名提取「剧名 + 集号」作为字幕检索关键词。
///
/// 逐函数移植自旧版 `src/engine/subtitle/normalizeQuery.ts`。
/// 例：`繁花.2023.第11集.1080p.WEB-DL.x264-ABC` → `title: 繁花, ep: 11`
library;

/// 归一化后的检索词。
class NormalizedSubtitleQuery {
  const NormalizedSubtitleQuery({required this.title, required this.ep});

  final String title;
  final String ep;
}

final RegExp _noise = RegExp(
  r'(1080[pPiI]?|2160[pPiI]?|720[pPiI]?|4k|web[-_.]?dl|web[-_.]?rip|bd[-_.]?(rip|720|1080)?|blu[-_.]?ray|h\.?264|x264|h\.?265|x265|hevc|10[-_.]?bit|hdr(10\+?)?|dolby[-_.]?vision|dv|dts[-_.]?hd?|dd[+p]?|ac3|aac(2\.?0)?|atmos|mkv|mp4|mp4b|srt|ass|uniqp|yysubs|fnf|dmhy|简体|简体中文|国语|粤语|双语|中英|[/_#].*)',
  caseSensitive: false,
);

/// 集号模式（顺序有讲究：先 S01E10 再 E10）。
final List<RegExp> _epPatterns = <RegExp>[
  RegExp(r'\b[Ss](\d{1,3})[Ee](\d{1,3})\b'),
  RegExp(r'\b[Ee](\d{1,3})\b'),
  RegExp(r'第\s*(\d{1,3})\s*[集话季](?:\s*[-~]\s*第?\s*(\d{1,3})\s*[集话季])?'),
  RegExp(r'[（(\[]\s*第?\s*(\d{1,3})\s*[集话][）)\] ]'),
];

final RegExp _tailNumber = RegExp(r'(?<![0-9A-Za-z])(\d{1,3})(?![0-9])');

/// 提取集号（优先中文“第N集”；其次 E/如；再退化为末尾数字）。
String extractEp(String name) {
  for (final re in _epPatterns) {
    for (final m in re.allMatches(name)) {
      final raw = m.groupCount >= 2 ? (m.group(2) ?? m.group(1)) : m.group(1);
      if (raw != null && raw.isNotEmpty) {
        return raw.replaceFirst(RegExp(r'^0+'), '');
      }
    }
  }
  final tail = _tailNumber.firstMatch(name);
  return tail == null ? '' : tail.group(1)!.replaceFirst(RegExp(r'^0+'), '');
}

/// 从资源名（常形如“剧名 - 第N集”或“剧名 第N集”）提取查询词。
NormalizedSubtitleQuery normalizeSubtitleQuery(String name) =>
    NormalizedSubtitleQuery(title: normalizeTitle(name), ep: extractEp(name));

/// 提取剧名主标题（去掉“- 集名”、“第N集”、年份、清晰度、发布组等后缀）。
String normalizeTitle(String name) {
  var title = name;
  // 去掉「标题 - 集名」的后半段（- / — / 空格 + 第N集 或 集名）
  title = title.split(RegExp(r'[-—–]\s*第\s*\d+\s*[集话][^(-—–]*')).first;
  final dash = RegExp(r'^(.*?)[-\s]*(第\s*\d+\s*[集话]).*$').firstMatch(title);
  if (dash != null) {
    title = dash.group(1) ?? '';
  } else {
    final epIdx = title.indexOf(RegExp(r'第\s*\d+\s*[集话]'));
    if (epIdx > 0) title = title.substring(0, epIdx);
  }
  // 去集名（“标题 - 集名”而无数字时）
  final pure = RegExp(r'^(.*?)\s*[-—–]\s*([^-—–]{1,20})$').firstMatch(title.trim());
  if (pure != null && (pure.group(1) ?? '').length >= 2) {
    title = pure.group(1)!;
  }
  // 去嘈杂后缀（年份 / 清晰度 / 编码 / 发布组 / 标签）
  title = title
      .replaceAll(_noise, ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll('.', ' ')
      .trim();
  title = title
      .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
      .replaceAll(RegExp(r'[\[【].*?[\]】]'), ' ')
      .trim();
  return title;
}

/// 生成一组剧名关键词候选（主标题 + 常见变体）。
List<String> titleVariants(String title) {
  final t = title.trim();
  if (t.isEmpty) return const <String>[];
  final out = <String>[t];
  final noSpace = t.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[·/]'), '');
  if (noSpace.isNotEmpty && noSpace != t) out.add(noSpace);
  final parts = t.split(RegExp(r'\s+'));
  if (parts.length > 1 && parts.last.length > 1) {
    final joined = parts.sublist(0, parts.length - 1).join(' ');
    if (joined.isNotEmpty) out.add(joined);
  }
  return out.toSet().take(4).toList();
}

String buildSearchQuery(String name) {
  final q = normalizeSubtitleQuery(name);
  final kw = q.title + (q.ep.isEmpty ? '' : ' ${q.ep}');
  return kw.trim();
}

/// 统一取「剧名副名」供检索（优先 knownTitle，为空则从资源名截取第一段）。
String animeTitleForQuery(String resourceName, [String? knownTitle]) {
  final t = (knownTitle ?? '').trim();
  if (t.isNotEmpty) return t;
  final seg = resourceName.split(RegExp(r'[-—–~]')).first.trim();
  return seg.isNotEmpty ? seg : resourceName.trim();
}
