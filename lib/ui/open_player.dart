import 'package:flutter/material.dart';

import '../core/platform/player_window.dart';
import '../models/live.dart';
import '../models/site_config.dart';
import '../services/live/epg.dart';
import '../services/player/player_window_session.dart';
import '../state/app_state.dart';
import 'pages/live_player_page.dart';
import 'pages/player_page.dart';

/// 内置播放器是否应该开在独立窗口里。
///
/// 沉浸观影模式始终用主窗口内嵌播放器；Web / 移动端没有多窗口能力。
bool shouldUseStandalonePlayer(AppState app) =>
    supportsStandalonePlayerWindow && app.playerSettings.effectivePopOutPlayer;

Future<void> openVodPlayer(
  BuildContext context,
  AppState app,
  PlayerSession session, {
  bool rootNavigator = false,
}) async {
  if (shouldUseStandalonePlayer(app)) {
    // 首播地址可能已经指向主窗口 JVM 的本机 /chunk：子窗口播放期间不能回收。
    app.sourceService.jar.holdPlaybackForExternal();
    final opened = await openStandalonePlayerWindow(
      payload: PlayerWindowPayload.vod(
        VodWindowSession(
          detail: session.detail,
          site: session.site,
          flag: session.flag,
          episodeIndex: session.episodeIndex,
          episodes: session.episodes,
          initialPlay: session.initialPlay,
          startPositionMs: session.startPositionMs,
          ephemeral: session.ephemeral,
        ),
      ),
    );
    if (opened) return;
    // 窗口创建失败时退回原来的内嵌播放器，不能让点击没有反应。
  }
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: rootNavigator).push(
    MaterialPageRoute(builder: (_) => PlayerPage(session: session)),
  );
}

Future<void> openLivePlayer(
  BuildContext context,
  AppState app, {
  required LiveBean bean,
  required LiveChannel channel,
  required LiveLine initialLine,
  EpgEntry? epg,
  List<LiveGroup> groups = const [],
  Map<String, EpgEntry> epgEntries = const {},
  String initialGroup = '',
}) async {
  if (shouldUseStandalonePlayer(app)) {
    final opened = await openStandalonePlayerWindow(
      payload: PlayerWindowPayload.live(
        LiveWindowSession(
          bean: bean,
          channel: channel,
          initialLine: initialLine,
          epg: epg,
          groups: groups,
          epgEntries: epgEntries,
          initialGroup: initialGroup,
        ),
      ),
    );
    if (opened) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LivePlayerPage(
        bean: bean,
        channel: channel,
        initialLine: initialLine,
        epg: epg,
        groups: groups,
        epgEntries: epgEntries,
        initialGroup: initialGroup,
      ),
    ),
  );
}
