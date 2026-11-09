import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/py_spider/py_runtime.dart';

void main() {
  test('PY 宿主网络保留 options.body 原始请求体', () {
    final source = File('assets/python_runner/base/spider.py')
        .readAsStringSync();
    expect(source.contains("options.get('body')"), isTrue);
    expect(source.contains('data = raw_body'), isTrue);
    expect(PyRuntime.assetsVersion, greaterThanOrEqualTo(6));
  });
}
