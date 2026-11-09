import 'package:flutter/foundation.dart';

class PyRuntimeProgress {
  const PyRuntimeProgress(this.message, {this.value});
  final String message;
  final double? value;
}

/// Web 版没有嵌入式 Python；设置页仍可渲染同一套控件。
class PyRuntime {
  PyRuntime._();
  static final instance = PyRuntime._();

  final ValueNotifier<PyRuntimeProgress?> progress = ValueNotifier(null);
  String? get installPath => null;

  Future<bool> installed() async => false;

  Future<void> ensureInstalled({bool force = false}) async {
    throw StateError('Web 版不支持 Python 运行时');
  }

  Future<void> remove() async {}
}
