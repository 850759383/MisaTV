import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const bool hasCustomWindowChrome = false;

/// Web 端没有可记忆的独立窗口。
bool get supportsAppWindowSize => false;

Future<Size?> currentAppWindowSize() async => null;

final ValueNotifier<bool> _neverMaximized = ValueNotifier<bool>(false);
final ValueNotifier<bool> _neverFullScreen = ValueNotifier<bool>(false);

ValueListenable<bool> get windowMaximized => _neverMaximized;

ValueListenable<bool> get windowFullScreen => _neverFullScreen;

Future<void> setupDesktopWindow({Size? size}) async {}

/// Web 端没有独立的窗口进程，关窗清理是空实现。
void registerAppShutdown(Future<void> Function() hook) {}

Widget windowFrame(Widget child) => child;

/// Web 版没有独立播放器窗口，竖版适配是空操作。
Future<void> fitAppWindowToVideo(double videoWidth, double videoHeight) async {}

Future<void> minimizeAppWindow() async {}

Future<void> hideAppWindowToTray() async {}

Future<void> restoreAppWindowFromTray() async {}

Future<void> enterImmersiveFullscreen() async {}

Future<void> exitImmersiveFullscreen() async {}

Future<void> setAppWindowAlwaysOnTop(bool value) async {}

Future<void> toggleMaximizeAppWindow() async {}

Future<void> closeAppWindow() async {}

Future<void> startWindowDrag() async {}

Widget windowDragArea(Widget child, {bool enabled = true}) => child;

Future<void> enterMiniPlayerWindow() async {}

Future<void> exitMiniPlayerWindow() async {}

Future<void> setWindowFullscreen(bool fullscreen) async {
  await SystemChrome.setEnabledSystemUIMode(
    fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
}
