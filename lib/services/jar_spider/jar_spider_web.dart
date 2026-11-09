import '../../models/site_config.dart';
import '../../models/vod.dart';

/// Web 版没有 JVM，JAR 蜘蛛不可用；接口保持与 IO 版一致。
class JarSpiderService {
  JarSpiderService({
    Object? runtime,
    Map<String, String> Function()? driveTokens,
    Map<String, String> Function()? driveSeed,
    Object? http,
    this.refreshDriveSession,
  });

  Future<void> Function(String provider)? refreshDriveSession;

  Future<void> resetDriveState() async {}

  String globalJar = '';

  Future<CmsResult> home(SourceBean site) async => const CmsResult();

  Future<CmsResult> category(
    SourceBean site,
    String tid,
    String pg,
    Map<String, String> filters,
  ) async => const CmsResult();

  Future<VodDetail?> detail(SourceBean site, String id) async => null;

  Future<List<VodItem>> search(SourceBean site, String keyword) async =>
      const [];

  Future<PlayResult?> play(
    SourceBean site,
    String flag,
    String id, {
    List<String> vipFlags = const [],
  }) async => null;

  /// Web 版没有壳内取流进程，探针直接视为就绪。
  Future<bool> warmUpLocalPlayUrl(
    String url, {
    Duration timeout = const Duration(seconds: 20),
  }) async => true;
}
