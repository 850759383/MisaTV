import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_log.dart';
import '../../core/logging/log_redact.dart';
import '../../models/site_config.dart';
import '../../models/vod.dart';
import '../parse/parse_service.dart';
import '../source_service.dart';
import 'external_playlist_types.dart';

/// 第三方播放器的选集播放列表。
///
/// 外部播放器只认一个 URL，原来只能播当前这一集。这里写一份 M3U，把每一集
/// 指向本机中继的 `/ext/<token>/<index>`；外部播放器切集时由中继按需调用
/// 蜘蛛解析，再 302 到真正的播放地址，避免启动前把整季直链全部跑一遍。
class ExternalPlaylistService {
  ExternalPlaylistService({
    required this.sourceService,
    required this.parseService,
    required this.config,
    required this.jarReady,
    required this.preparePlay,
    required this.unwrapPlayPage,
    required this.warmUp,
    required this.holdExternal,
    required this.supportDir,
    required this.relayBaseUrl,
    this.maxSessions = 12,
  });

  final SourceService sourceService;
  final ParseService parseService;

  /// 创建播放列表时快照当前配置，外部播放器切集期间不受订阅刷新影响。
  final SiteConfig? Function() config;
  final bool Function() jarReady;
  final ExternalPreparePlayFn preparePlay;
  final ExternalUnwrapPlayFn unwrapPlayPage;
  final ExternalWarmUpFn warmUp;
  final void Function()? holdExternal;
  final String supportDir;
  final String Function() relayBaseUrl;
  final int maxSessions;

  final Map<String, _PlaylistSession> _sessions = {};
  final List<String> _sessionOrder = [];
  final Map<String, Future<String?>> _inflight = {};
  int _seq = 0;
  bool _cleaned = false;

  /// 写一份选集 M3U，返回文件路径；不足两集或中继未启动时返回 null。
  Future<String?> createPlaylist({
    required SourceBean site,
    required String flag,
    required List<Episode> episodes,
    required int currentIndex,
    String? currentUrl,
  }) async {
    if (episodes.length < 2) return null;
    final base = relayBaseUrl();
    if (base.isEmpty) return null;
    final snapshot = config();
    if (snapshot == null) return null;
    final index = currentIndex.clamp(0, episodes.length - 1);

    final token =
        'ep${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';
    try {
      final dir = Directory(p.join(supportDir, 'ext-playlists'));
      await dir.create(recursive: true);
      await _cleanupStale(dir);

      final file = File(p.join(dir.path, '$token.m3u'));
      // 当前集放在第一位（外部播放器默认从第一项起播），其余按原顺序轮转；
      // 这样「下一集」仍然是原剧集的下一集。
      final order = [
        for (var i = index; i < episodes.length; i++) i,
        for (var i = 0; i < index; i++) i,
      ];
      final buffer = StringBuffer('#EXTM3U\n');
      for (final episodeIndex in order) {
        final rawName = episodes[episodeIndex].name.replaceAll(
          RegExp(r'[\r\n]'),
          ' ',
        );
        final name = rawName.trim().isEmpty
            ? '第${episodeIndex + 1}集'
            : rawName.trim();
        // 当前集已经由 UI 取好链并预热：直接写真实地址，避免外部播放器
        // 起播时再跑一次蜘蛛、把刚预热好的取流会话顶掉。
        final direct =
            episodeIndex == index &&
                currentUrl != null &&
                currentUrl.trim().isNotEmpty
            ? currentUrl.trim()
            : null;
        buffer
          ..writeln('#EXTINF:-1,$name')
          ..writeln(direct ?? '$base/ext/$token/$episodeIndex');
      }
      await file.writeAsString(buffer.toString(), flush: true);

      _sessions[token] = _PlaylistSession(
        site: site,
        flag: flag,
        episodes: episodes,
        config: snapshot,
        currentIndex: index,
        currentUrl: currentUrl?.trim() ?? '',
      );
      _sessionOrder.add(token);
      await _prune();
      AppLog.i(
        'external',
        '生成选集列表 ${episodes.length} 集 current=$index file=${file.path}',
      );
      return file.path;
    } catch (e, s) {
      AppLog.w('external', '生成选集列表失败', e, s);
      return null;
    }
  }

  /// 中继 `/ext/<token>/<index>` 调到这里：按需解析出可交给外部播放器的地址。
  Future<String?> resolveEpisode(String token, int index) {
    final session = _sessions[token];
    if (session == null || index < 0 || index >= session.episodes.length) {
      return Future.value(null);
    }
    if (session.currentIndex == index && session.currentUrl.isNotEmpty) {
      return Future.value(session.currentUrl);
    }
    final key = '$token/$index';
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _resolveEpisode(session, index);
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  Future<String?> _resolveEpisode(_PlaylistSession session, int index) async {
    final episode = session.episodes[index];
    try {
      var play = await sourceService.resolvePlay(
        site: session.site,
        config: session.config,
        flag: session.flag,
        rawUrl: episode.url,
        jarReady: jarReady(),
      );
      play = await unwrapPlayPage(play);
      if (play.parse != 0 && play.externalLink.isEmpty) {
        final target = play.url.trim().isNotEmpty
            ? play.url.trim()
            : episode.url.trim();
        // 网页嗅探依赖 UI，外部播放器的请求里只能走 JSON 型解析接口。
        final hit = await parseService.resolve(session.config.parses, target);
        if (hit == null) {
          AppLog.w(
            'external',
            '选集 $index 需要解析但没有可用直链 url=${redactUrl(target)}',
          );
          return null;
        }
        play = PlayResult(
          url: hit.url,
          flag: session.flag,
          headers: hit.headers,
          message: play.message,
        );
      }
      if (!play.playable) {
        AppLog.w(
          'external',
          '选集 $index 没有可播放地址 msg=${play.message} '
              'url=${redactUrl(play.url)}',
        );
        return null;
      }
      final prepared = preparePlay(play, forceRelay: true);
      if (prepared.url.trim().isEmpty) return null;
      if (!await warmUp(prepared.url)) {
        AppLog.w('external', '选集 $index 取流预热失败');
        return null;
      }
      holdExternal?.call();
      return prepared.url;
    } catch (e, s) {
      AppLog.e('external', '选集 $index 解析失败', e, s);
      return null;
    }
  }

  /// 只保留最近 [maxSessions] 份列表，避免长时间运行后磁盘积压。
  Future<void> _prune() async {
    while (_sessionOrder.length > maxSessions) {
      final token = _sessionOrder.removeAt(0);
      _sessions.remove(token);
      try {
        final file = File(p.join(supportDir, 'ext-playlists', '$token.m3u'));
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 删除失败不影响播放
      }
    }
  }

  /// 清理上次运行残留的列表文件（超过一天）。
  Future<void> _cleanupStale(Directory dir) async {
    if (_cleaned) return;
    _cleaned = true;
    try {
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.m3u')) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > const Duration(days: 1)) {
            await entity.delete();
          }
        } catch (_) {
          // 单个文件失败跳过
        }
      }
    } catch (_) {
      // 目录不存在 / 不可读时忽略
    }
  }
}

class _PlaylistSession {
  _PlaylistSession({
    required this.site,
    required this.flag,
    required this.episodes,
    required this.config,
    required this.currentIndex,
    required this.currentUrl,
  });

  final SourceBean site;
  final String flag;
  final List<Episode> episodes;
  final SiteConfig config;

  /// 当前集已经取好的外部可播地址（UI 预热过的），其余集走按需解析。
  final int currentIndex;
  final String currentUrl;
}
