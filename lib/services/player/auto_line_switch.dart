import '../../models/vod.dart';

/// 集名归一：`第16集` / `【16】` / `S01E16` 都归成 `n16`。
///
/// 日期型综艺集名（`2024-01-01期`）保留完整文本，不能把年份当成集号。
String episodeSignature(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return '';
  if (RegExp(r'\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}').hasMatch(text)) {
    return text.replaceAll(RegExp(r'[\s\-_:：·,，。!！?？【】\[\]()（）/\.年月日号]'), '');
  }
  final se = RegExp(r's\d+e(\d+)').firstMatch(text);
  if (se != null) {
    final n = int.tryParse(se.group(1)!);
    if (n != null) return 'n$n';
  }
  final cn = RegExp(r'第\s*(\d{1,4})\s*[集期话]').firstMatch(text);
  if (cn != null) {
    final n = int.tryParse(cn.group(1)!);
    if (n != null) return 'n$n';
  }
  final suffix = RegExp(r'(\d{1,4})\s*[集期话]').firstMatch(text);
  if (suffix != null) {
    final n = int.tryParse(suffix.group(1)!);
    if (n != null) return 'n$n';
  }
  final bare = RegExp(r'^[\s【\[(（]*(\d{1,4})[\s】\])）]*$').firstMatch(text);
  if (bare != null) {
    final n = int.tryParse(bare.group(1)!) ?? 0;
    if (n < 1900 || n > 2099) return 'n$n';
  }
  return text.replaceAll(RegExp(r'[\s\-_:：·,，。!！?？【】\[\]()（）第集话期]'), '');
}

/// 目标集在下一条线路里的下标：先按集名 / 集号匹配，再退回同下标。
///
/// 目标是明确的第 N 集但对方没有这一集时返回 -1，避免把 16 集误播成第 1 集。
int matchEpisodeIndex(List<Episode> episodes, String targetName, int fallback) {
  if (episodes.isEmpty) return -1;
  final target = episodeSignature(targetName);
  if (target.isNotEmpty) {
    for (var i = 0; i < episodes.length; i++) {
      if (episodeSignature(episodes[i].name) == target) return i;
    }
    if (target.startsWith('n')) return -1;
  }
  if (fallback >= 0 && fallback < episodes.length) return fallback;
  return 0;
}

/// 当前线路之后的其它线路（循环一圈，不回头）。
List<String> nextLineCandidates(List<String> flags, String current) {
  if (flags.length <= 1) return const [];
  final start = flags.indexOf(current);
  if (start < 0) return List<String>.of(flags);
  final out = <String>[];
  for (var offset = 1; offset < flags.length; offset++) {
    out.add(flags[(start + offset) % flags.length]);
  }
  return out;
}

/// 片名归一：去掉空白、常见标点，以及尾部的 `(2024)` / `【2024】` 年份。
///
/// 跨源同名匹配用；不去季节 / 集数后缀，避免把第二季误配到第一季。
String titleSignature(String raw) {
  final text = raw.toLowerCase().replaceAll(
    RegExp(r'[（(\[【]\s*(19|20)\d{2}\s*[）)\]】]'),
    '',
  );
  return text.replaceAll(RegExp(r'[\s\-_:：·,，。!！?？]'), '');
}
