import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/logging/app_log.dart';
import 'package:kniephos/core/logging/log_redact.dart';

void main() {
  test('AppLog 写入 logs 目录、按行落盘并可 flush', () async {
    final tmp = Directory.systemTemp.createTempSync('misa_log_');
    try {
      await AppLog.init(supportDir: tmp.path);
      AppLog.i('test', 'hello');
      AppLog.e('test', 'boom', StateError('bad state'));
      await AppLog.flush();

      expect(AppLog.directory, endsWith('logs'));
      final file = File(AppLog.currentFile);
      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(text, contains('[I][test] hello'));
      expect(text, contains('[E][test] boom'));
      expect(text, contains('bad state'));
      expect(text, contains('===== MisaTV 启动 ====='));
    } finally {
      await AppLog.dispose();
      tmp.deleteSync(recursive: true);
    }
  });

  test('日志 URL 只保留键名，不带 token 值', () {
    expect(
      redactUrl('https://pan.quark.cn/api/file?auth_key=secret&token=abc'),
      'https://pan.quark.cn/api/file?<auth_key,token>',
    );
    expect(redactUrl('magnet:?xt=urn:btih:abc'), 'magnet:?xt=urn:btih:abc');
  });
}
