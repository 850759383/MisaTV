import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 允许鼠标左键按住拖动滚动。
///
/// Material 默认把 [PointerDeviceKind.mouse] 排除在 `dragDevices` 之外，
/// 桌面端横向列表只能靠滚轮或滚动条；分类栏、选集线路这类单行长列表
/// 一超出宽度就没法用鼠标左键拖。
class MouseDragScrollBehavior extends MaterialScrollBehavior {
  const MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
