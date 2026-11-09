// 弹幕搜索前的资源名清洗（对齐旧版 src/engine/danmaku/normalizeQuery.ts）：
// 生成搜索候选词 / 解析「集」输入框 / 候选显示压缩。
import 'danmaku_endpoints.dart';

final RegExp _fullWidthRe = RegExp(r'[\uFF01-\uFF5E]');
final RegExp _nonLetterNumber = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _fullToHalf(String s) {
  return s
      .replaceAllMapped(
        _fullWidthRe,
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
      )
      .replaceAll('\u3000', ' ');
}

String _segment(String s) {
  for (final part in s.split(RegExp(r'[-/~/·:：|_]'))) {
    final t = part.trim();
    if (t.isNotEmpty) return t;
  }
  return s;
}

/// 生成搜索候选词（去重、按原意优先，最长优先在前；最多 6 个）。
List<String> danmakuQueryCandidates(String raw) {
  if (raw.isEmpty) return const [];
  final base = _fullToHalf(raw).trim();
  final seen = <String>{};
  final out = <String>[];
  void push(String s) {
    final v = s.trim();
    if (v.isNotEmpty && v.length >= 2 && seen.add(v)) out.add(v);
  }

  // 1) 原文（半角化）
  push(base);
  // 2) 去尾部剧集标记：第N集/话/期/章、全N集、更新至N
  final noEp = base
      .replaceAll(RegExp(r'\s*(?:第)?\d+[集话期章]\s*$'), '')
      .replaceAll(RegExp(r'\s*全\d+[集话]\s*$'), '')
      .replaceAll(RegExp(r'\s*更新至\s*\d+\s*$'), '')
      .trim();
  push(noEp);
  // 3) 去掉所有符号/空格/emoji，只留文字数字
  final pureBase = base.replaceAll(_nonLetterNumber, '');
  final pureNoEp = noEp.replaceAll(_nonLetterNumber, '');
  push(pureNoEp);
  push(pureBase);
  // 4) 取第一段（拆掉 " - " 字幕组后缀 / 季数等）
  push(_segment(noEp));
  push(_segment(base));
  return out.length > 6 ? out.sublist(0, 6) : out;
}

/// 「集」输入框解析结果。
class EpisodeInput {
  const EpisodeInput({this.season, this.ep});

  /// 季号（`S02E01` / `第2季` → 2）。
  final int? season;

  /// 集号（已去前导零：`01` → `1`）。
  final String? ep;
}

/// 集号去前导零（`01`→`1`）；全零保留 `0` 以免变成空串。
String _stripEp(String v) {
  final t = v.replaceFirst(RegExp(r'^0+'), '');
  return t.isEmpty ? '0' : t;
}

/// 解析「集」输入框内容：`S01E10` / `1x10` / `E10` / `第10集` / `10` / `更新至10` / `第2季`。
/// 认不出来返回空对象（调用方回退「从资源名提取」）。
EpisodeInput parseEpisodeInput(String raw) {
  final s = _fullToHalf(raw).trim();
  if (s.isEmpty) return const EpisodeInput();
  final se = RegExp(r'[Ss](\d{1,2})\s*[Ee][Pp]?\s*(\d{1,4})').firstMatch(s) ??
      RegExp(r'(\d{1,3})\s*[xX]\s*(\d{1,4})').firstMatch(s);
  if (se != null) {
    return EpisodeInput(
      season: int.tryParse(se.group(1)!),
      ep: _stripEp(se.group(2)!),
    );
  }
  int? season;
  final sn = RegExp(r'第\s*(\d{1,3})\s*[季部]').firstMatch(s) ??
      RegExp(r'(?:^|\b)s(?:eason)?\s*(\d{1,2})(?![0-9])', caseSensitive: false)
          .firstMatch(s);
  if (sn != null) season = int.tryParse(sn.group(1)!);
  String? ep;
  final epMatch = RegExp(r'[Ee][Pp]?\s*(\d{1,4})').firstMatch(s) ??
      RegExp(r'第\s*(\d{1,4})\s*[集话期]').firstMatch(s) ??
      RegExp(r'(?:更新至|至)\s*(\d{1,4})').firstMatch(s) ??
      RegExp(r'^\s*(\d{1,4})\s*$').firstMatch(s);
  if (epMatch != null) ep = _stripEp(epMatch.group(1)!);
  return EpisodeInput(season: season, ep: ep);
}

/// 「集」输入框初值（由资源名生成）：`S01E10` → `S1E10`；`第10集`/末尾数字 → `10`。
String episodeFieldFromName(String name) {
  final s = name.trim();
  if (s.isEmpty) return '';
  final se = RegExp(r'[Ss](\d{1,2})\s*[Ee](\d{1,4})').firstMatch(s);
  if (se != null) {
    final season = int.tryParse(se.group(1)!) ?? 0;
    return 'S${season}E${_stripEp(se.group(2)!).padLeft(2, '0')}';
  }
  final cn = RegExp(r'第\s*(\d{1,4})\s*[集话期]').firstMatch(s);
  if (cn != null) return _stripEp(cn.group(1)!);
  final e = RegExp(r'[Ee][Pp]?\s*(\d{1,4})(?![0-9])').firstMatch(s);
  if (e != null) return _stripEp(e.group(1)!);
  // 末尾/独立数字（避免向前吞掉字母：只认前后都不是 ASCII 字母数字的孤立数字）。
  for (final m in RegExp(r'\d+').allMatches(s)) {
    final before = m.start > 0 ? s.codeUnitAt(m.start - 1) : 0;
    final after = m.end < s.length ? s.codeUnitAt(m.end) : 0;
    if (_isAsciiAlnum(before) || _isAsciiAlnum(after)) continue;
    final run = m.group(0)!;
    if (run.length > 3) continue;
    return _stripEp(run);
  }
  return '';
}

bool _isAsciiAlnum(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// 从文本里提集号：`第N话/集/期` → N；`SxxExx` → xx；`更新至N` → N；纯数字（非年份）→ N。
String _epNumberOf(String s) {
  final t = _fullToHalf(s).trim();
  if (t.isEmpty) return '';
  final se = RegExp(r'[Ss]\d{1,2}\s*[Ee]\s*(\d{1,4})').firstMatch(t);
  if (se != null) return _stripEp(se.group(1)!);
  final cn = RegExp(r'第\s*(\d{1,4})\s*[集话期]').firstMatch(t);
  if (cn != null) return _stripEp(cn.group(1)!);
  final up = RegExp(r'(?:更新至|至)\s*(\d{1,4})\s*[集话期]?').firstMatch(t);
  if (up != null) return _stripEp(up.group(1)!);
  final pure = RegExp(r'^\s*(\d{1,4})\s*$').firstMatch(t);
  if (pure != null && !RegExp(r'^(?:19|20)\d{2}$').hasMatch(pure.group(1)!)) {
    return _stripEp(pure.group(1)!);
  }
  return '';
}

/// 弹幕候选显示压缩：`斗破苍穹年番 第212话` → `斗破苍穹年番 · 第212集`。
String formatCandidateLabel({
  String title = '',
  String episodeTitle = '',
  String episodeNumber = '',
}) {
  final raw = _fullToHalf(title.trim());
  final ym = RegExp(r'[（(\[]?\s*((?:19|20)\d{2})\s*[）)\]]?').firstMatch(raw);
  final year = ym == null ? '' : ym.group(1)!;
  final num = episodeNumber.trim();
  final ep = _epNumberOf(episodeTitle).isNotEmpty
      ? _epNumberOf(episodeTitle)
      : (RegExp(r'^\d{1,4}$').hasMatch(num) ? _stripEp(num) : _epNumberOf(raw));
  final season = seasonOf(raw) ?? seasonOf(episodeTitle);
  var name = raw
      .replaceAll(RegExp(r'[（(\[]\s*(?:19|20)\d{2}\s*[）)\]]'), ' ')
      .replaceAll(RegExp(r'\bfrom\s*[^\s（()\u4e00-\u9fa5]+', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(
          r'[（(\[【]\s*(?:3D)?(?:动漫|动画|国漫|日漫|电视剧|电影|综艺|纪录片|TV|OVA)\s*[）)\]】]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'第\s*(?:\d{1,2}|[一二三四五六七八九十]{1,3})\s*[季部]'), ' ')
      .replaceAll(RegExp(r'[Ss](?:eason)?\s*\d{1,2}\s*[Ee]\s*\d{1,4}'), ' ')
      .replaceAll(RegExp(r'[Ss]\s*\d{1,2}(?![0-9A-Za-z])'), ' ')
      .replaceAll(RegExp(r'第\s*\d{1,4}\s*[集话期]'), ' ')
      .replaceAll(RegExp(r'(?:更新至|全)\s*\d{1,4}\s*[集话期]?'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'[\s\-–—·:：|]+$'), '')
      .trim();
  if (name.isEmpty) name = raw; // 净化后为空但原文有内容（如纯符号名）→ 保留原文
  final nameFromEp = name.isEmpty;
  if (nameFromEp) name = episodeTitle.trim();
  if (name.isEmpty) return '';
  final parts = <String>[year.isEmpty ? name : '$name（$year）'];
  if (season != null) parts.add('第$season季');
  if (ep.isNotEmpty && !nameFromEp) parts.add('第$ep集');
  return parts.join(' · ');
}
