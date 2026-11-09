/// 多字幕源聚合入口。
///
/// 移植自旧版 `src/main/subtitle/index.ts`：
///   · 逐源并行检索（每源独立 + 超时预算），单源失败不影响其它源；
///   · 中文优先、标题精确命中优先排序；
///   · 下载按候选自带的 providerId 路由回对应源。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'assrt_provider.dart';
import 'custom_provider.dart';
import 'normalize_query.dart';
import 'subtitle_http.dart';
import 'subtitle_models.dart';
import 'subtitlecat_provider.dart';

/// 候选排序（稳定排序）：
///   ① 中文（简/繁/中英）优先；
///   ② 标题精确命中检索标题的优先；
///   ③ 其余保持各源返回顺序。
List<SubtitleCandidate> sortSubtitleCandidates(
  List<SubtitleCandidate> list,
  String title,
) {
  final want = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  int zhOf(SubtitleCandidate c) {
    final s = '${c.language} ${c.detail} ${c.subname}';
    return RegExp(r'简|繁|中文|中英|双语|zh', caseSensitive: false).hasMatch(s)
        ? 0
        : 1;
  }

  int exactOf(SubtitleCandidate c) {
    if (want.isEmpty) return 1;
    final t = c.title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return t.isNotEmpty && t == want ? 0 : 1;
  }

  final rows = <({SubtitleCandidate c, int i, int zh, int exact})>[
    for (var i = 0; i < list.length; i++)
      (c: list[i], i: i, zh: zhOf(list[i]), exact: exactOf(list[i])),
  ]..sort((a, b) {
      final byZh = a.zh.compareTo(b.zh);
      if (byZh != 0) return byZh;
      final byExact = a.exact.compareTo(b.exact);
      if (byExact != 0) return byExact;
      return a.i.compareTo(b.i);
    });
  return rows.map((x) => x.c).toList();
}

class SubtitleService {
  SubtitleService({
    Map<String, String> Function()? tokens,
    String Function()? customApis,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) : _tokens = tokens ?? (() => const <String, String>{}),
       _customApis = customApis ?? (() => ''),
       _timeout = timeout,
       _http = SubtitleHttp(client: client, timeout: timeout);

  final Map<String, String> Function() _tokens;
  final String Function() _customApis;
  final Duration _timeout;
  final SubtitleHttp _http;

  /// 并行检索；单源失败/超时只丢该源，不抛整体失败。
  ///
  /// 无 assrt token 时该源直接跳过（返回空列表）。
  Future<List<SubtitleCandidate>> search(
    SubtitleQuery query, {
    Set<String> providers = const <String>{'subtitlecat', 'assrt'},
  }) async {
    final ctx = _buildContext(query);
    final tokens = _readTokens();
    final pending = <Future<List<SubtitleCandidate>>>[];

    for (final raw in providers) {
      final type = subtitleProviderFromId(raw);
      if (type == null) continue;
      if (type == SubtitleProviderType.assrt) {
        final token = (tokens[assrtProviderId] ?? '').trim();
        if (token.isEmpty) continue;
        pending.add(_isolate(
          () => searchAssrt(
            http: _http,
            token: token,
            query: query,
            keywords: ctx.keywords,
          ).timeout(_timeout),
        ));
      } else {
        pending.add(_isolate(
          () => searchSubtitleCat(
            http: _http,
            query: query,
            keywords: ctx.keywords,
          ).timeout(_timeout),
        ));
      }
    }
    for (final api in _readCustomApis()) {
      pending.add(_isolate(
        () => searchCustomSubtitleApi(_http, api, query).timeout(_timeout),
      ));
    }

    final settled = await Future.wait(pending);
    final all = <SubtitleCandidate>[
      for (final list in settled) ...list,
    ];
    return sortSubtitleCandidates(all, ctx.title);
  }

  /// 下载并解出真正的字幕文本；失败抛 [SubtitleException]（中文原因）。
  Future<SubtitleFile> download(SubtitleCandidate candidate) async {
    if (candidate.providerId.startsWith('custom:')) {
      CustomSubtitleApi? api;
      for (final e in _readCustomApis()) {
        if (e.id == candidate.providerId) {
          api = e;
          break;
        }
      }
      if (api == null) {
        throw SubtitleException('自定义字幕接口已不存在：${candidate.providerName}');
      }
      return downloadCustomSubtitleApi(_http, api, candidate);
    }
    final type = subtitleProviderFromId(candidate.providerId);
    if (type == null) {
      throw SubtitleException('未知的字幕源：${candidate.providerId}');
    }
    if (type == SubtitleProviderType.assrt) {
      final token = (_readTokens()[assrtProviderId] ?? '').trim();
      if (token.isEmpty) {
        throw const SubtitleException(
          '尚未配置 assrt token，请先在「配置 → 外挂字幕」中填写',
        );
      }
      return assrtDownload(_http, token, candidate);
    }
    return fetchSubtitleCat(_http, candidate);
  }

  Map<String, String> _readTokens() {
    try {
      return _tokens();
    } catch (_) {
      return const <String, String>{};
    }
  }

  List<CustomSubtitleApi> _readCustomApis() {
    try {
      return parseCustomSubtitleApis(_customApis());
    } catch (_) {
      return const [];
    }
  }

  Future<List<SubtitleCandidate>> _isolate(
    Future<List<SubtitleCandidate>> Function() run,
  ) async {
    try {
      return await run();
    } catch (_) {
      return const <SubtitleCandidate>[];
    }
  }
}

/// 由公开查询构造内部检索上下文（标题 / 集号 / 关键词候选）。
({String title, String ep, List<String> keywords}) _buildContext(
  SubtitleQuery query,
) {
  final source = query.title.trim().isNotEmpty ? query.title : query.rawName;
  var title = normalizeTitle(source);
  if (title.isEmpty) title = source.trim();
  final ep = query.episode == null
      ? extractEp(query.rawName.isNotEmpty ? query.rawName : source)
      : query.episode.toString();

  final keywords = <String>[];
  void add(String value) {
    final t = value.trim();
    if (t.isNotEmpty && !keywords.contains(t)) keywords.add(t);
  }

  final variants = titleVariants(title);
  for (final v in variants) {
    add(v);
  }
  if (query.title.trim().isNotEmpty && query.rawName.trim().isNotEmpty) {
    final fromRaw = normalizeTitle(query.rawName);
    if (fromRaw.isNotEmpty && fromRaw != title) {
      for (final v in titleVariants(fromRaw)) {
        add(v);
      }
    }
  }
  if (ep.isNotEmpty) {
    add('$title $ep');
    for (final v in variants) {
      add('$v $ep');
    }
  }
  return (title: title, ep: ep, keywords: keywords.take(6).toList());
}
