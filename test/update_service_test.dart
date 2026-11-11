import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/app_version.dart';
import 'package:kniephos/services/update/update_service.dart';

Map<String, Object?> asset(
  String name, {
  String url = 'https://x/a.zip',
  int size = 1,
}) => {'name': name, 'browser_download_url': url, 'size': size};

void main() {
  test('版本号归一：去掉 v 前缀与构建号', () {
    expect(UpdateService.normalizeVersion('v0.9.1'), '0.9.1');
    expect(UpdateService.normalizeVersion('  V1.2.3 '), '1.2.3');
    expect(UpdateService.normalizeVersion('1.2.3+45'), '1.2.3');
  });

  test('版本比较：按数字比，预测后缀更低', () {
    expect(UpdateService.compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(UpdateService.compareVersions('0.9.0', '0.9.0'), 0);
    expect(UpdateService.compareVersions('v0.9.0+10', '0.9.0'), 0);
    expect(UpdateService.compareVersions('0.9.1', '0.9.0'), greaterThan(0));
    expect(UpdateService.compareVersions('1.0.0-beta', '1.0.0'), lessThan(0));
    expect(UpdateService.compareVersions('1.2', '1.2.0'), 0);
  });

  test('是否比本地新', () {
    expect(UpdateService.isNewer('0.9.1', '0.9.0'), isTrue);
    expect(UpdateService.isNewer('0.9.0', '0.9.0'), isFalse);
    expect(UpdateService.isNewer('0.8.9', '0.9.0'), isFalse);
  });

  test('解析 release JSON：tag / 说明 / 资产', () {
    final release = UpdateService.parseGithubRelease({
      'tag_name': 'v0.9.1',
      'body': '### 更新内容\n- 修好封面',
      'html_url': 'https://github.com/yagami-hue/MisaTV/releases/tag/v0.9.1',
      'published_at': '2026-11-11T10:00:00Z',
      'assets': [
        asset('MisaTV-0.9.1-linux.zip'),
        asset('MisaTV-0.9.1-windows-x64.zip'),
      ],
    });
    expect(release.version, '0.9.1');
    expect(release.notes, contains('修好封面'));
    expect(release.assetName, 'MisaTV-0.9.1-windows-x64.zip');
    expect(release.openUrl, 'https://x/a.zip');
  });

  test('没有资产时用 release 页面兜底', () {
    final release = UpdateService.parseGithubRelease({
      'tag_name': '0.9.2',
      'html_url': 'https://github.com/yagami-hue/MisaTV/releases/tag/0.9.2',
      'assets': const [],
    });
    expect(release.assetName, isEmpty);
    expect(release.openUrl, contains('/releases/tag/0.9.2'));
  });

  test('挑资产：Windows zip 优先，其次任意 zip / exe', () {
    expect(
      UpdateService.pickAsset([
        asset('MisaTV.apk'),
        asset('MisaTV-0.9.1-linux.zip'),
        asset('MisaTV-0.9.1-windows-x64.zip'),
      ])?.name,
      'MisaTV-0.9.1-windows-x64.zip',
    );
    expect(
      UpdateService.pickAsset([asset('a.dmg'), asset('b.zip')])?.name,
      'b.zip',
    );
    expect(UpdateService.pickAsset([asset('setup.exe')])?.name, 'setup.exe');
    expect(UpdateService.pickAsset(const []), isNull);
  });

  test('应用版本号与 pubspec 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(kAppVersion, match!.group(1));
  });
}
