import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/jar_spider/hyms_native.dart';

void main() {
  group('HymsNative API 响应解密', () {
    test('collection 响应补齐缺省左括号后可解析', () {
      const body =
          '5XzFVp82kJsrZO7aOwLbTMgM+C4jkArvcbNx7MPMZH6CAe6CN4Nu3Z/4a2cJZyf'
          'D4UCxH1sV/8wRPz/0SgnaA57kQR9hez12kxjRWhf3eDHbfD0ZmTLbD2oZw+XHDYcQ';
      final text = HymsNative.decryptApiBody(body);
      expect(text, isNotEmpty);
      final json = jsonDecode(text) as Map;
      expect(json['message'], '成功');
      expect(json['result'], isA<Map>());
    });
  });
}
