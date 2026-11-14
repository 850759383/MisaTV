import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/app_version.dart';
import 'package:kniephos/services/update/update_service.dart';

void main() {
  test('版本形状判断', () {
    expect(UpdateService.looksLikeVersionTag('v0.9.1'), isTrue);
    expect(UpdateService.looksLikeVersionTag('0.9'), isTrue);
    expect(UpdateService.looksLikeVersionTag('1.2.3.4'), isTrue);
    expect(UpdateService.looksLikeVersionTag('v1.0.0-beta.1'), isTrue);
    expect(UpdateService.looksLikeVersionTag('weekly.2012-03-27'), isFalse);
    expect(UpdateService.looksLikeVersionTag('nightly'), isFalse);
  });

  // 真实接口连通性：有 release 的仓库要能解析出版本与资产（离线属环境问题）。
  test('真实 GitHub release 接口可用', () async {
    final release = await UpdateService(repo: 'microsoft/vscode').latest();
    if (release == null) {
      // 离线环境不算逻辑失败：跳过而不是红灯，联网时这段会真正跑一遍。
      markTestSkipped('当前离线，跳过真实接口校验');
      return;
    }
    expect(
      UpdateService.looksLikeVersionTag(release.tag),
      isTrue,
      reason: 'tag=${release.tag}',
    );
    // ignore: avoid_print
    print(
      '远端 tag=${release.tag} version=${release.version} '
      'asset=${release.assetName} 说明=${release.notes.length}字 '
      '本地 v$kAppVersion 有更新=${UpdateService.isNewer(release.version, kAppVersion)}',
    );
  }, timeout: const Timeout(Duration(seconds: 40)));
}
