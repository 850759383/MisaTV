import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/app_log.dart';
import '../../services/update/update_service.dart';
import 'update_dialog.dart';

/// 启动后检查一次更新；有新版本就弹窗（点「稍后提醒」下次启动会再弹）。
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  /// 一次进程只提示一次，避免对话框被反复拉起。
  static bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (_prompted || !mounted) return;
    // 让首屏加载与字幕/封面请求先跑，别抢带宽，也别盖住启动动画。
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted || _prompted) return;
    final release = await UpdateService().check();
    if (!mounted || release == null) return;
    _prompted = true;
    AppLog.i('update', '提示更新到 v${release.version}');
    await showUpdateDialog(context, release);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
