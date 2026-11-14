import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../core/logging/app_log.dart';
import '../../services/update/update_service.dart';

/// 弹出「发现新版本」对话框：看更新内容，然后下载 / 走网盘 / 稍后提醒。
Future<void> showUpdateDialog(BuildContext context, AppRelease release) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => UpdateDialog(release: release),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.release});

  final AppRelease release;

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw '系统没有可用的浏览器';
    } catch (e) {
      AppLog.w('update', '打开下载地址失败：$e');
      messenger?.showSnackBar(SnackBar(content: Text('打不开链接：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = release.notes.isEmpty ? '本次发布没有填写更新说明。' : release.notes;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Flexible(child: Text('发现新版本 v${release.version}')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当前版本 v$kAppVersion  ·  最新 v${release.version}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: SelectableText(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后提醒'),
        ),
        TextButton.icon(
          onPressed: () => _open(context, kUpdateNetdiskUrl),
          icon: const Icon(Icons.cloud_outlined, size: 18),
          label: const Text('网盘下载'),
        ),
        FilledButton.icon(
          onPressed: () => _open(context, release.openUrl),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('下载'),
        ),
      ],
    );
  }
}
