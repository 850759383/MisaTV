import '../../models/site_config.dart';
import '../../models/vod.dart';
import '../parse/parse_service.dart';
import '../source_service.dart';
import 'external_playlist_types.dart';

/// Web 端没有外部播放器与本地中继，选集列表不可用。
class ExternalPlaylistService {
  ExternalPlaylistService({
    required SourceService sourceService,
    required ParseService parseService,
    required SiteConfig? Function() config,
    required bool Function() jarReady,
    required ExternalPreparePlayFn preparePlay,
    required ExternalUnwrapPlayFn unwrapPlayPage,
    required ExternalWarmUpFn warmUp,
    required void Function()? holdExternal,
    required String supportDir,
    required String Function() relayBaseUrl,
  });

  Future<String?> createPlaylist({
    required SourceBean site,
    required String flag,
    required List<Episode> episodes,
    required int currentIndex,
    String? currentUrl,
  }) async => null;

  Future<String?> resolveEpisode(String token, int index) async => null;
}
