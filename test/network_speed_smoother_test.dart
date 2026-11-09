import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/player/network_speed_smoother.dart';

void main() {
  group('NetworkSpeedSmoother', () {
    test('前两次采样不展示，第三次开始给出稳定值', () {
      final smoother = NetworkSpeedSmoother();
      smoother.add(8000000);
      expect(smoother.value, 0);
      smoother.add(8000000);
      expect(smoother.value, 0);
      smoother.add(8000000);
      expect(smoother.value, 8000000);
    });

    test('关键帧尖峰不会被当成网速', () {
      final smoother = NetworkSpeedSmoother();
      for (var i = 0; i < 3; i++) {
        smoother.add(8000000);
      }
      smoother.add(4000000000);
      expect(smoother.value, 8000000);
      smoother.add(8000000);
      expect(smoother.value, 8000000);
    });

    test('正常上升不会一秒钟跳满', () {
      final smoother = NetworkSpeedSmoother();
      for (var i = 0; i < 3; i++) {
        smoother.add(4000000);
      }
      expect(smoother.value, 4000000);
      smoother.add(8000000);
      expect(smoother.value, greaterThan(4000000));
      expect(smoother.value, lessThan(8000000));
    });

    test('暂停 / 未知码率与 reset 清空展示', () {
      final smoother = NetworkSpeedSmoother();
      for (var i = 0; i < 3; i++) {
        smoother.add(8000000);
      }
      smoother.add(0);
      expect(smoother.value, 0);
      smoother.add(8000000);
      expect(smoother.value, 0);

      smoother.reset();
      expect(smoother.value, 0);
    });
  });
}
