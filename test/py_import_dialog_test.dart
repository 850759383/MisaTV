import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/state/app_state.dart';
import 'package:kniephos/ui/widgets/name_input_dialog.dart';

ConfigProfile _profile(String id, String name, int sites) => ConfigProfile(
  id: id,
  name: name,
  url: '',
  rawJson: '{"sites":[]}',
  importedAt: DateTime(2026),
  siteCount: sites,
);

void main() {
  testWidgets('PY 导入弹窗单选也会出现，可导入到已有订阅', (tester) async {
    final profiles = [_profile('p1', '订阅A', 2)];
    PyImportTarget? target;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              target = await showPyImportTargetDialog(
                context,
                profiles: profiles,
                initialProfileId: 'p1',
                suggestedName: '韩寒',
                fileCount: 1,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('导入 PY 源'), findsOneWidget);
    expect(find.text('订阅A（2 个站点）'), findsOneWidget);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(target?.profileId, 'p1');
    expect(target?.name, '订阅A');
  });

  testWidgets('PY 导入弹窗可切换为新建订阅并校验名称', (tester) async {
    final profiles = [_profile('p1', '订阅A', 2)];
    PyImportTarget? target;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              target = await showPyImportTargetDialog(
                context,
                profiles: profiles,
                initialProfileId: 'p1',
                suggestedName: '韩寒',
                fileCount: 2,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('订阅A（2 个站点）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建新订阅').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我的 PY 订阅');
    await tester.tap(find.text('创建并导入'));
    await tester.pumpAndSettle();
    expect(target?.profileId, isNull);
    expect(target?.name, '我的 PY 订阅');
  });

  testWidgets('移动站点弹窗返回目标订阅 id', (tester) async {
    final profiles = [_profile('p1', '订阅A', 2), _profile('p2', '订阅B', 1)];
    String? moved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              moved = await showMoveSitesTargetDialog(
                context,
                profiles: profiles,
                count: 3,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('移动站点'), findsOneWidget);
    expect(find.text('将选中的 3 个站点移动到：'), findsOneWidget);

    await tester.tap(find.text('订阅A（2 个站点）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('订阅B（1 个站点）').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动'));
    await tester.pumpAndSettle();
    expect(moved, 'p2');
  });

  test('订阅刷新保留本地新增 / 移动进来的站点', () {
    final existing = ConfigProfile(
      id: 'p1',
      name: '订阅A',
      url: 'https://example.com/config.json',
      rawJson: jsonEncode({
        'sites': [
          {'key': 'a', 'name': '远端 A'},
          {'key': 'b', 'name': '本地 B', 'api': 'file:///b.py'},
        ],
      }),
      importedAt: DateTime(2026),
      addedSiteKeys: const ['b'],
    );
    final incoming = jsonEncode({
      'sites': [
        {'key': 'a', 'name': '远端 A2'},
        {'key': 'c', 'name': '远端 C'},
      ],
    });
    final merged = jsonDecode(
      AppState.mergeAddedSites(incoming, existing, existing.addedSiteKeys),
    ) as Map<String, dynamic>;
    final sites = merged['sites'] as List;
    expect(sites.length, 3);
    expect(
      (sites.where((e) => (e as Map)['key'] == 'b').single as Map)['name'],
      '本地 B',
    );

    // 远端也有同 key 时，本地修改 / 移动过来的版本优先，避免刷新把修复冲掉。
    final remoteHasIt = jsonEncode({
      'sites': [
        {'key': 'b', 'name': '远端 B'},
      ],
    });
    final merged2 = jsonDecode(
      AppState.mergeAddedSites(remoteHasIt, existing, existing.addedSiteKeys),
    ) as Map<String, dynamic>;
    final sites2 = merged2['sites'] as List;
    expect(sites2.length, 1);
    expect((sites2.single as Map)['name'], '本地 B');
  });

  test('ConfigProfile JSON 往返保留本地新增 key', () {
    final profile = ConfigProfile(
      id: 'p1',
      name: '订阅A',
      url: '',
      rawJson: '{"sites":[]}',
      importedAt: DateTime(2026),
      addedSiteKeys: const ['one'],
    );
    final decoded = ConfigProfile.fromJson(profile.toJson());
    expect(decoded.addedSiteKeys, const ['one']);
  });
}
