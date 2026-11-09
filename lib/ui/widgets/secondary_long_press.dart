import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 桌面端「鼠标右键按住一段时间」检测器。
///
/// 右键按下后启动计时，达到 [duration] 仍未松开才触发 [onLongPress]；
/// 提前松开则视为一次普通右键点击，触发 [onTap]（可空）。
/// 左键 / 触摸事件完全透传，不影响子组件原有的点击与长按。
class SecondaryLongPressDetector extends StatefulWidget {
  const SecondaryLongPressDetector({
    super.key,
    required this.child,
    this.onLongPress,
    this.onTap,
    this.duration = const Duration(milliseconds: 600),
  });

  final Widget child;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final Duration duration;

  @override
  State<SecondaryLongPressDetector> createState() =>
      _SecondaryLongPressDetectorState();
}

class _SecondaryLongPressDetectorState
    extends State<SecondaryLongPressDetector> {
  Timer? _timer;
  bool _pressed = false;
  bool _fired = false;

  void _handleDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if ((event.buttons & kSecondaryMouseButton) == 0) return;
    _pressed = true;
    _fired = false;
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      if (!mounted || !_pressed || _fired) return;
      _fired = true;
      widget.onLongPress?.call();
    });
  }

  void _handleUp(PointerEvent event) {
    if (!_pressed) return;
    _timer?.cancel();
    final fired = _fired;
    _pressed = false;
    _fired = false;
    if (!fired) widget.onTap?.call();
  }

  void _handleCancel(PointerCancelEvent event) {
    _timer?.cancel();
    _pressed = false;
    _fired = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.child,
    );
  }
}
