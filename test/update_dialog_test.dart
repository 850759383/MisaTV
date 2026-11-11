import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/app_version.dart';
import 'package:kniephos/services/update/update_service.dart';
import 'package:kniephos/ui/widgets/update_dialog.dart';

void main() {
  const release = AppRelease(
    version: '0.9.1',
    tag: 'v0.9.1',
    notes: '### 更新内容\n- 修好封面抓取\n- 设置页重新分类',
    htmlUrl: 'https://github.com/yagami-hue/MisaTV/releases/tag/v0.9.1',
    downloadUrl: 'https://example.com/MisaTV-0.9.1-windows-x64.zip',
    assetName: 'MisaTV-0.9.1-windows-x64.zip',
  );

  testWidgets('更新弹窗展示版本、更新内容与三个按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showUpdateDialog(context, release),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v0.9.1'), findsOneWidget);
    expect(find.textContaining('当前版本 v$kAppVersion'), findsOneWidget);
    expect(find.textContaining('修好封面抓取'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('网盘下载'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);

    // 稍后提醒只关掉弹窗，不改任何持久化状态（下次启动会再弹）。
    await tester.tap(find.text('稍后提醒'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v0.9.1'), findsNothing);
  });
}
