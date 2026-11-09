import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/core/platform/portable_app_data_io.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('misa_prefs_');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('PortablePrefsStore 写入后可跨实例读回', () async {
    final store = PortablePrefsStore(dir.path);
    await store.setValue('String', 'flutter.a', '1');
    await store.setValue('StringList', 'flutter.list', ['x', 'y']);

    final reopened = PortablePrefsStore(dir.path);
    final all = await reopened.getAll();
    expect(all['flutter.a'], '1');
    expect(all['flutter.list'], ['x', 'y']);
  });

  test('PortablePrefsStore 只读回 flutter. 前缀、clear 不误删其它键', () async {
    final store = PortablePrefsStore(dir.path);
    await store.setValue('String', 'flutter.a', '1');
    await store.setValue('String', 'other.b', '2');

    expect((await store.getAll()).keys, ['flutter.a']);
    await store.clear();
    expect(await store.getAll(), isEmpty);

    final raw = await File('${dir.path}/shared_preferences.json').readAsString();
    expect(raw, contains('other.b'));
  });

  test('PortablePrefsStore remove 与损坏文件容错', () async {
    final store = PortablePrefsStore(dir.path);
    await store.setValue('String', 'flutter.a', '1');
    await store.remove('flutter.a');
    expect(await store.getAll(), isEmpty);

    await File('${dir.path}/shared_preferences.json').writeAsString('{坏数据');
    expect(await PortablePrefsStore(dir.path).getAll(), isEmpty);
  });
}
