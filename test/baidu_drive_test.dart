import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/drive/baidu_native.dart';

void main() {
  group('百度 bdstoken 解析', () {
    test('读取 result.bdstoken', () {
      expect(
        baiduBdstokenFromTemplate({
          'errno': 0,
          'result': {'bdstoken': 'abc123'},
        }),
        'abc123',
      );
    });

    test('兼容旧字段 bstoken', () {
      expect(
        baiduBdstokenFromTemplate({
          'errno': 0,
          'result': {'bstoken': 'legacy'},
        }),
        'legacy',
      );
    });

    test('未登录 / 异常响应返回空', () {
      expect(baiduBdstokenFromTemplate({'errno': -6}), isEmpty);
      expect(
        baiduBdstokenFromTemplate({'errno': 0, 'result': 'null'}),
        isEmpty,
      );
      expect(
        baiduBdstokenFromTemplate({
          'errno': 0,
          'result': {'bdstoken': ''},
        }),
        isEmpty,
      );
    });
  });
}
