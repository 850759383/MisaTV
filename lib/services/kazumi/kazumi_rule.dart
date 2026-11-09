import 'dart:convert';

import '../../models/site_config.dart';

/// Kazumi 规则（`Predidit/KazumiRules` 的 `*.json`）。
///
/// 兼容 API Level 1~9：
///   · 老规则只有 `searchURL/searchList/searchName/searchResult/chapterRoads/chapterResult`；
///   · 新规则（api 9）额外有 `searchMode/chapterMode`、`searchApiConfig`、`chapterApiConfig`、
///     `antiCrawlerConfig` 等字段，搜索与选集可以一个走 XPath、一个走 JSON 接口。
///
/// 解析保持宽松：缺字段不报错，由调用方按 `valid` 与模式判断能否使用。
class KazumiRule {
  const KazumiRule({
    required this.raw,
    required this.api,
    required this.name,
    required this.version,
    required this.baseUrl,
    required this.searchMode,
    required this.chapterMode,
    required this.userAgent,
    required this.referer,
    required this.searchUrl,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.usePost,
    required this.searchApi,
    required this.chapterApi,
  });

  /// 原始 JSON（用于持久化与后续再解析，避免手写字段丢失）。
  final Map<String, dynamic> raw;
  final int api;
  final String name;
  final String version;
  final String baseUrl;

  /// `xpath` / `api`；老规则没有该字段时按已填的字段推断。
  final String searchMode;
  final String chapterMode;

  final String userAgent;
  final String referer;

  // XPath 模式字段。
  final String searchUrl;
  final String searchList;
  final String searchName;
  final String searchResult;
  final String chapterRoads;
  final String chapterResult;

  /// 老规则的 POST 搜索开关（`usePost`）。
  final bool usePost;

  final KazumiSearchApi? searchApi;
  final KazumiChapterApi? chapterApi;

  factory KazumiRule.fromJson(Map<String, dynamic> json) {
    final searchMode = _str(json['searchMode']).toLowerCase();
    final chapterMode = _str(json['chapterMode']).toLowerCase();
    final searchUrl = _str(json['searchURL']);
    final searchList = _str(json['searchList']);
    final chapterRoads = _str(json['chapterRoads']);
    final rule = KazumiRule(
      raw: json,
      api: _int(json['api']),
      name: _str(json['name']),
      version: _str(json['version']),
      baseUrl: _str(json['baseURL']),
      searchMode: searchMode.isNotEmpty
          ? searchMode
          : (searchUrl.isNotEmpty && searchList.isNotEmpty ? 'xpath' : 'api'),
      chapterMode: chapterMode.isNotEmpty
          ? chapterMode
          : (chapterRoads.isNotEmpty ? 'xpath' : 'api'),
      userAgent: _str(json['userAgent']),
      referer: _str(json['referer']),
      searchUrl: searchUrl,
      searchList: searchList,
      searchName: _str(json['searchName']),
      searchResult: _str(json['searchResult']),
      chapterRoads: chapterRoads,
      chapterResult: _str(json['chapterResult']),
      usePost: json['usePost'] == true,
      searchApi: KazumiSearchApi.fromJson(json['searchApiConfig']),
      chapterApi: KazumiChapterApi.fromJson(json['chapterApiConfig']),
    );
    return rule;
  }

  bool get valid {
    if (name.isEmpty) return false;
    if (searchMode == 'api') return searchApi != null;
    return searchUrl.isNotEmpty && searchList.isNotEmpty;
  }

  /// 稳定主键：跨版本升级同名规则只保留一条。
  String get key {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'kazumi_${_stableHash(name)}' : 'kazumi_$slug';
  }

  SourceBean toSourceBean() => SourceBean(
    key: key,
    name: name,
    type: kKazumiSourceType,
    api: 'kazumi://$key',
    searchable: 1,
    quickSearch: 1,
    changeable: 0,
    filterable: 0,
    playerType: -1,
    timeout: 20,
    ext: jsonEncode(raw),
  );

  static String _stableHash(String text) {
    var hash = 0;
    for (final code in text.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _str(Object? value) =>
      value == null ? '' : value.toString().trim();
}

/// Kazumi 规则在 TVBox 配置里的自定义类型（TVBox 自身未占用 5）。
const int kKazumiSourceType = 5;

/// Kazumi API 请求配置（搜索接口 / 选集接口）。
class KazumiApiRequest {
  const KazumiApiRequest({
    required this.method,
    required this.url,
    this.query = const {},
  });

  final String method;
  final String url;
  final Map<String, String> query;

  static KazumiApiRequest? fromJson(Object? value) {
    if (value is! Map) return null;
    final request = value['request'];
    if (request is! Map) return null;
    final url = (request['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final query = <String, String>{};
    final rawQuery = request['query'];
    if (rawQuery is Map) {
      rawQuery.forEach((key, item) {
        if (item != null) query[key.toString()] = item.toString();
      });
    }
    final method = (request['method'] ?? 'GET').toString().trim();
    return KazumiApiRequest(
      method: method.isEmpty ? 'GET' : method.toUpperCase(),
      url: url,
      query: query,
    );
  }
}

/// Kazumi 搜索接口配置：请求 + JSONPath + 详情地址模板。
class KazumiSearchApi {
  const KazumiSearchApi({
    required this.request,
    required this.listPath,
    required this.namePath,
    required this.sourcePath,
    required this.sourceTemplate,
  });

  final KazumiApiRequest request;
  final String listPath;
  final String namePath;
  final String sourcePath;

  /// 含 `@source`；为空时搜索得到的 source 直接作为选集接口的 `@source`。
  final String sourceTemplate;

  static KazumiSearchApi? fromJson(Object? value) {
    final request = KazumiApiRequest.fromJson(value);
    if (request == null) return null;
    final map = value is Map ? value : const <String, dynamic>{};
    return KazumiSearchApi(
      request: request,
      listPath: (map['listPath'] ?? '').toString().trim(),
      namePath: (map['namePath'] ?? '').toString().trim(),
      sourcePath: (map['sourcePath'] ?? '').toString().trim(),
      sourceTemplate: (map['sourceTemplate'] ?? '').toString().trim(),
    );
  }
}

/// Kazumi 选集接口配置：`json` 或 `delimited`（Cms 风格的 `$$$` / `#` / `$` 分隔）。
class KazumiChapterApi {
  const KazumiChapterApi({
    required this.request,
    required this.format,
    required this.roadNamesPath,
    required this.roadEpisodesPath,
    required this.roadSeparator,
    required this.episodeSeparator,
    required this.fieldSeparator,
  });

  /// 没有请求配置时为 null（调用方给出「规则缺少选集接口」）。
  final KazumiApiRequest? request;
  final String format;
  final String roadNamesPath;
  final String roadEpisodesPath;
  final String roadSeparator;
  final String episodeSeparator;
  final String fieldSeparator;

  static KazumiChapterApi? fromJson(Object? value) {
    if (value is! Map) return null;
    return KazumiChapterApi(
      request: KazumiApiRequest.fromJson(value),
      format: (value['format'] ?? '').toString().trim().toLowerCase(),
      roadNamesPath: (value['roadNamesPath'] ?? '').toString().trim(),
      roadEpisodesPath: (value['roadEpisodesPath'] ?? '').toString().trim(),
      roadSeparator: (value['roadSeparator'] ?? r'$$$').toString(),
      episodeSeparator: (value['episodeSeparator'] ?? '#').toString(),
      fieldSeparator: (value['fieldSeparator'] ?? r'$').toString(),
    );
  }
}
