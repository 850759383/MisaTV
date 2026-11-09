// 内容过滤：一键屏蔽 R18 / 成人内容。
//
// 思路参考 QuantumTV 的 adult source 过滤（crates/core/src/adult.rs）：
// 用一组关键词判断「是否为成人内容」，命中就从浏览列表里隐藏。
// 这里只做纯文本匹配与 JSON 读写，界面在首页 / 分类 / 搜索结果上应用。
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/site_config.dart';
import '../models/vod.dart';

/// 关闭密码最短长度（防止设置成空密码）。
const int contentFilterPasswordMinLength = 4;

/// 生成带随机盐的密码摘要：`<saltHex>:<sha256Hex>`，不保存明文。
String hashContentFilterPassword(String password, {String? salt}) {
  final actualSalt = salt ?? _randomSalt();
  final digest = sha256
      .convert(utf8.encode('$actualSalt:$password'))
      .toString();
  return '$actualSalt:$digest';
}

/// 校验密码；摘要格式非法或密码错误都返回 false。
bool verifyContentFilterPassword(String password, String stored) {
  final separator = stored.indexOf(':');
  if (separator <= 0 || separator >= stored.length - 1) return false;
  final salt = stored.substring(0, separator);
  final expected = stored.substring(separator + 1).toLowerCase();
  final actual = sha256.convert(utf8.encode('$salt:$password')).toString();
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

String _randomSalt() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// 默认屏蔽词：覆盖常见的成人内容标记（大小写不敏感）。
const List<String> defaultContentFilterKeywords = <String>[
  'R18',
  '18+',
  '18禁',
  'NSFW',
  'adult',
  '成人',
  '情色',
  '色情',
  // 「伦理片」是很多采集源单独列出的成人分类名，默认就拦截；
  // 关键词去后缀后也会命中类型字段只写「伦理」的条目。
  '伦理片',
  '🔞',
];

/// 旧版默认词（没有「伦理片」）。用于把从未自定义过关键词的老配置升级到新默认词。
const List<String> _legacyDefaultContentFilterKeywords = <String>[
  'R18',
  '18+',
  '18禁',
  'NSFW',
  'adult',
  '成人',
  '情色',
  '色情',
  '🔞',
];

/// 关键词归一：按行 / 逗号 / 顿号 / 分号切分，去空白、忽略大小写去重，保持顺序。
List<String> normalizeContentFilterKeywords(Iterable<String> raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final chunk in raw) {
    for (final part in chunk.split(RegExp(r'[\r\n,，、;；]+'))) {
      final word = part.trim();
      if (word.isEmpty) continue;
      if (!seen.add(word.toLowerCase())) continue;
      out.add(word);
    }
  }
  return out;
}

class ContentFilterSettings {
  const ContentFilterSettings({
    required this.enabled,
    required this.keywords,
    this.passwordHash = '',
  });

  /// 默认值：关闭、内置常见屏蔽词、未设置关闭密码。
  factory ContentFilterSettings.defaults() => const ContentFilterSettings(
    enabled: false,
    keywords: defaultContentFilterKeywords,
  );

  /// 宽容解析 JSON（非法返回默认值）。
  factory ContentFilterSettings.fromJsonString(String? json) {
    if (json == null || json.trim().isEmpty) {
      return ContentFilterSettings.defaults();
    }
    dynamic raw;
    try {
      raw = jsonDecode(json);
    } catch (_) {
      return ContentFilterSettings.defaults();
    }
    if (raw is! Map) return ContentFilterSettings.defaults();
    return ContentFilterSettings.fromJson(raw.cast<String, dynamic>());
  }

  factory ContentFilterSettings.fromJson(Map<String, dynamic> raw) {
    final fallback = ContentFilterSettings.defaults();
    final enabled = _asBool(raw['enabled']) ?? fallback.enabled;
    final passwordHash = _asString(raw['passwordHash']).trim();
    final stored = raw['keywords'];
    // 没写过 keywords 字段的旧配置沿用默认词；显式清空则保持空（不过滤任何内容）。
    if (stored == null) {
      return ContentFilterSettings(
        enabled: enabled,
        keywords: fallback.keywords,
        passwordHash: passwordHash,
      );
    }
    final Iterable<String> words = stored is List
        ? stored.map((e) => e?.toString() ?? '')
        : [stored.toString()];
    final keywords = normalizeContentFilterKeywords(words);
    // 老版本保存的「默认词」没有「伦理片」，原样读回会让升级后的默认规则失效；
    // 只有整份列表正好是旧默认词时才补新词，用户自定义过的列表保持原样。
    final legacy = normalizeContentFilterKeywords(
      _legacyDefaultContentFilterKeywords,
    );
    final isLegacyDefault =
        keywords.length == legacy.length &&
        keywords.every(
          (word) =>
              legacy.any((old) => old.toLowerCase() == word.toLowerCase()),
        );
    return ContentFilterSettings(
      enabled: enabled,
      keywords: isLegacyDefault ? fallback.keywords : keywords,
      passwordHash: passwordHash,
    );
  }

  final bool enabled;
  final List<String> keywords;

  /// 关闭过滤所需的密码摘要（`salt:sha256`）；空串表示未设置。
  final String passwordHash;

  /// 是否设置过关闭密码。
  bool get hasPassword => passwordHash.isNotEmpty;

  /// 校验关闭密码。
  bool verifyPassword(String password) =>
      hasPassword && verifyContentFilterPassword(password, passwordHash);

  /// 开关打开且至少有一个关键词时才真正参与过滤。
  bool get active => enabled && keywords.isNotEmpty;

  /// 单个文本是否命中屏蔽词（大小写不敏感的子串匹配）。
  bool matches(String text) {
    if (!active || text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final keyword in keywords) {
      if (lower.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  bool matchesAny(Iterable<String> fields) {
    if (!active) return false;
    for (final field in fields) {
      if (matches(field)) return true;
    }
    return false;
  }

  /// 点播条目：名称 / 备注 / 类型 / 地区 / 标签 / 来源。
  bool blocksVod(VodItem item) =>
      matchesAny([
        item.name,
        item.remarks,
        item.type,
        item.area,
        item.tag,
        item.sourceName,
      ]) ||
      // 分类名「伦理片」而条目类型只写「伦理」时也要命中。
      _matchesGenreStem(item.type);

  /// 分类是否命中屏蔽词：分类名 / 分类 id。
  bool blocksClass(SortClass cls) =>
      matchesAny([cls.name, cls.id]) || _matchesGenreStem(cls.name);

  /// 筛选选项是否命中屏蔽词：选项显示名 / 提交值 / 所属标签。
  ///
  /// 很多源把「伦理片」放在分类页的「类型」筛选里，而不是分类栏；
  /// 只过滤分类名会让它继续出现在筛选弹层里。
  bool blocksFilterOption(FilterOption option) =>
      matchesAny([option.n, option.v, option.tab]) ||
      _matchesGenreStem(option.n) ||
      _matchesGenreStem(option.v);

  /// 筛选组本身是否命中屏蔽词（组名 / key）。
  bool blocksFilterGroup(FilterGroup group) =>
      matchesAny([group.name, group.key]) || _matchesGenreStem(group.name);

  /// 过滤后的筛选组；命中屏蔽词或过滤后没有可选项时返回 null。
  FilterGroup? visibleFilterGroup(FilterGroup group) {
    if (!active) return group;
    if (blocksFilterGroup(group)) return null;
    final values = group.values
        .where((option) => !blocksFilterOption(option))
        .toList();
    if (values.isEmpty) return null;
    if (values.length == group.values.length) return group;
    return FilterGroup(key: group.key, name: group.name, values: values);
  }

  /// 过滤后的分类：分类名命中时整个分类隐藏；否则只剔除命中屏蔽词的
  /// 筛选组 / 筛选选项，保证「筛选」弹层里也不会出现成人分类。
  SortClass? visibleClass(SortClass cls) {
    if (!active) return cls;
    if (blocksClass(cls)) return null;
    var changed = false;
    final groups = <FilterGroup>[];
    for (final group in cls.filters) {
      final visible = visibleFilterGroup(group);
      if (visible == null) {
        changed = true;
        continue;
      }
      if (!identical(visible, group)) changed = true;
      groups.add(visible);
    }
    if (!changed) return cls;
    return SortClass(
      id: cls.id,
      name: cls.name,
      flag: cls.flag,
      filters: groups,
    );
  }

  /// 关键词末尾常带分类后缀（伦理片 / 三级片），而条目的类型字段可能只写
  /// 「伦理」「三级」；去掉后缀后再按子串匹配一次，避免分类屏蔽漏掉搜索结果。
  bool _matchesGenreStem(String text) {
    if (!active || text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final keyword in keywords) {
      final k = keyword.toLowerCase().trim();
      for (final suffix in const ['片', '剧', '区', '类']) {
        if (k.length < suffix.length + 2 || !k.endsWith(suffix)) continue;
        final stem = k.substring(0, k.length - suffix.length);
        if (lower.contains(stem)) return true;
      }
    }
    return false;
  }

  /// 详情：名称 / 类型 / 地区 / 演员 / 简介 / 备注。
  bool blocksDetail(VodDetail detail) => matchesAny([
    detail.name,
    detail.type,
    detail.area,
    detail.actor,
    detail.des,
    detail.remarks,
  ]);

  /// 站点：名称 / 地址 / key（对齐 QuantumTV 的成人源判定）。
  bool blocksSource(SourceBean site) =>
      matchesAny([site.name, site.api, site.key]);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'keywords': keywords,
    'passwordHash': passwordHash,
  };

  String toJsonString() => jsonEncode(toJson());

  ContentFilterSettings copyWith({
    bool? enabled,
    List<String>? keywords,
    String? passwordHash,
  }) {
    return ContentFilterSettings(
      enabled: enabled ?? this.enabled,
      keywords: keywords ?? this.keywords,
      passwordHash: passwordHash ?? this.passwordHash,
    );
  }
}

String _asString(dynamic v) => v == null ? '' : v.toString();

bool? _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}
