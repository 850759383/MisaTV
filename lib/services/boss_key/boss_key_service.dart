import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../core/logging/app_log.dart';
import '../../core/platform/window_service.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';

/// 老板键：暂停正在播放的视频并把窗口收进托盘；再按一次老板键或点托盘图标
/// 恢复原来的形态（全屏回全屏、小窗回小窗、普通窗口回普通窗口）。
///
/// 沉浸观影模式下整个功能不生效（热键仍然注册，但按下不做任何事）。
class BossKeyService {
  BossKeyService._();

  static final BossKeyService instance = BossKeyService._();

  AppState? _app;
  TrayIcon? _tray;
  Menu? _menu;
  final List<MenuItem> _menuItems = [];
  HotKey? _hotKey;
  String _activeBossKey = '';
  bool _hidden = false;
  bool _busy = false;
  bool _pausedByBoss = false;
  int _lastPressMs = 0;
  String lastHotKeyError = '';

  /// 最近一次注册使用的老板键（用于设置页显示状态）。
  String get activeBossKey => _activeBossKey;

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// 启动时接好托盘与全局热键；失败只记日志，不影响正常使用。
  Future<void> init(AppState app) async {
    if (!_desktop) return;
    _app = app;
    _initTray();
    await applyBossKey(app.playerSettings.bossKey);
  }

  /// 更换老板键（设置页保存后调用）。返回是否注册成功。
  Future<bool> applyBossKey(String raw) async {
    if (!_desktop) return false;
    final value = normalizeBossKey(raw);
    _activeBossKey = value;
    lastHotKeyError = '';
    final previous = _hotKey;
    _hotKey = null;
    if (previous != null) {
      try {
        await hotKeyManager.unregister(previous);
      } catch (_) {
        // 旧键可能已经失效，继续注册新键。
      }
    }
    _tray?.setTooltip('MisaTV · 老板键 ${bossKeyLabel(value)}');
    if (value == 'off') {
      AppLog.i('boss', '老板键已关闭');
      return true;
    }
    final hotKey = _hotKeyFor(value);
    if (hotKey == null) return false;
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _onPressed(),
      );
      _hotKey = hotKey;
      AppLog.i('boss', '老板键已注册：${bossKeyLabel(value)}');
      return true;
    } catch (e) {
      lastHotKeyError = '$e';
      AppLog.w('boss', '老板键注册失败（${bossKeyLabel(value)}）：$e');
      return false;
    }
  }

  /// 热键回调：沉浸观影模式直接忽略，按住不放产生的重复事件只认第一次。
  void _onPressed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPressMs < 600) return;
    _lastPressMs = now;
    final app = _app;
    if (app == null) return;
    if (app.playerSettings.immersiveMode) return;
    unawaited(toggle());
  }

  Future<void> toggle() async {
    if (_busy) return;
    if (_hidden) {
      await restore();
    } else {
      await hide();
    }
  }

  /// 暂停视频并隐藏到托盘。
  Future<void> hide() async {
    if (_busy || _hidden) return;
    _busy = true;
    try {
      final paused = _pauseHook?.call() ?? false;
      _pausedByBoss = paused;
      await hideAppWindowToTray();
      _hidden = true;
      AppLog.i('boss', '老板键：已隐藏到托盘${paused ? '，播放已暂停' : ''}');
    } finally {
      _busy = false;
    }
  }

  /// 从托盘恢复窗口，并只在老板键按下前正在播放时才继续播放。
  Future<void> restore() async {
    if (_busy) return;
    _busy = true;
    try {
      await restoreAppWindowFromTray();
      _hidden = false;
      if (_pausedByBoss) {
        _pausedByBoss = false;
        _resumeHook?.call();
      }
      AppLog.i('boss', '老板键：已恢复窗口');
    } finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------- 播放器钩子

  Object? _playerOwner;
  bool Function()? _pauseHook;
  VoidCallback? _resumeHook;

  /// 播放器页注册：返回是否真的暂停了（原本暂停时不恢复）。
  void bindPlayer(
    Object owner, {
    required bool Function() pause,
    required VoidCallback resume,
  }) {
    _playerOwner = owner;
    _pauseHook = pause;
    _resumeHook = resume;
  }

  void unbindPlayer(Object owner) {
    if (_playerOwner != owner) return;
    _playerOwner = null;
    _pauseHook = null;
    _resumeHook = null;
  }

  // -------------------------------------------------------------------- 托盘

  void _initTray() {
    try {
      final icon = TrayIcon.create();
      if (icon == null) return;
      _tray = icon;
      icon.icon = ImageAsset.fromAsset('assets/images/app_icon.png');
      icon.setTooltip('MisaTV · 老板键 ${bossKeyLabel(_app?.playerSettings.bossKey ?? kDefaultBossKey)}');

      final menu = Menu.create();
      if (menu != null) {
        final showItem = MenuItem.createWithLabelAndType(
          '显示 MisaTV',
          MenuItemType.normal,
        );
        if (showItem != null) {
          showItem.addListener((event) {
            if (event is MenuItemClickedEvent) unawaited(restore());
          });
          menu.addItem(showItem);
          _menuItems.add(showItem);
        }
        menu.addSeparator();
        final exitItem = MenuItem.createWithLabelAndType(
          '退出 MisaTV',
          MenuItemType.normal,
        );
        if (exitItem != null) {
          exitItem.addListener((event) {
            if (event is MenuItemClickedEvent) {
              // 等菜单收起后再关窗，避免在菜单回调里直接销毁窗口。
              Timer.run(() => unawaited(closeAppWindow()));
            }
          });
          menu.addItem(exitItem);
          _menuItems.add(exitItem);
        }
        icon.setContextMenu(menu);
        icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
        _menu = menu;
      }
      if (_menu != null) {
        AppLog.i('boss', '托盘菜单已创建（${_menuItems.length} 项）');
      }

      icon.addListener((event) {
        if (event is TrayIconClickedEvent ||
            event is TrayIconDoubleClickedEvent) {
          unawaited(restore());
        }
      });
      icon.setVisible(true);
      AppLog.i('boss', '托盘图标已创建');
    } catch (e) {
      AppLog.w('boss', '托盘图标创建失败：$e');
    }
  }

  HotKey? _hotKeyFor(String value) {
    final key = switch (value) {
      'ctrl+shift+b' => LogicalKeyboardKey.keyB,
      'ctrl+alt+b' => LogicalKeyboardKey.keyB,
      'alt+q' => LogicalKeyboardKey.keyQ,
      'alt+x' => LogicalKeyboardKey.keyX,
      'f12' => LogicalKeyboardKey.f12,
      _ => null,
    };
    if (key == null) return null;
    final modifiers = switch (value) {
      'ctrl+shift+b' => [HotKeyModifier.control, HotKeyModifier.shift],
      'ctrl+alt+b' => [HotKeyModifier.control, HotKeyModifier.alt],
      'alt+q' || 'alt+x' => [HotKeyModifier.alt],
      _ => const <HotKeyModifier>[],
    };
    return HotKey(
      identifier: 'misa-boss-key',
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );
  }
}
