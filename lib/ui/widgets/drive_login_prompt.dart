import 'package:flutter/material.dart';

import '../../app.dart';
import '../../services/drive/drive_line_hint.dart';
import 'drive_web_login_dialog.dart';
import 'uc_tv_login_dialog.dart';

/// 线路要用的网盘没登录时，直接把扫码窗口摆出来
/// （winbox 的经验：缺凭据不要只丢一句「请去配置中心」，用户找不到入口）。
///
/// 返回 true 表示此刻已具备该线路需要的凭据，可以继续播放。
Future<bool> promptDriveLogin(
  BuildContext context,
  DriveLineHint hint, {
  String message = '',
}) async {
  if (!hint.supported) {
    if (context.mounted) {
      await _showUnsupported(context, hint, message);
    }
    return false;
  }

  final app = AppScope.of(context);
  if (!app.hasDriveAccount(hint.provider)) {
    final ok = await showDriveLoginDialog(context, hint.provider);
    if (ok != true || !context.mounted) return false;
  }

  if (hint.needsToken) {
    final token = (app.driveAccounts[hint.provider]?.extra['uctvToken'] ?? '').trim();
    if (token.isEmpty) {
      final ok = await showUcTvLoginDialog(context);
      return ok == true;
    }
  }
  return true;
}

Future<void> _showUnsupported(
  BuildContext context,
  DriveLineHint hint,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${hint.name}线路暂不支持扫码'),
      content: Text(
        [
          if (message.isNotEmpty) message,
          '本机只内置了夸克 / UC / 百度的扫码登录；这条线路请换其他可用线路再试。',
        ].join('\n\n'),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
