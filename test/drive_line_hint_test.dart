import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/drive/drive_line_hint.dart';

void main() {
  group('driveHintFromFlag', () {
    test('扫码登录的三家都能识别', () {
      final quark = driveHintFromFlag('夸克原画');
      expect(quark?.provider, 'quark');
      expect(quark?.supported, isTrue);
      expect(quark?.needsToken, isFalse);

      final baidu = driveHintFromFlag('百度');
      expect(baidu?.provider, 'baidu');
      expect(baidu?.supported, isTrue);

      final uc = driveHintFromFlag('UC');
      expect(uc?.provider, 'uc');
      expect(uc?.supported, isTrue);
    });

    test('不支持的网盘也能认出来，但不提供扫码', () {
      final pan115 = driveHintFromFlag('115');
      expect(pan115?.provider, 'pan115');
      expect(pan115?.supported, isFalse);

      final aliyun = driveHintFromFlag('阿里云盘');
      expect(aliyun?.provider, 'aliyun');
      expect(aliyun?.supported, isFalse);
    });

    test('普通线路名不误判', () {
      expect(driveHintFromFlag('4K'), isNull);
      expect(driveHintFromFlag('高清线路'), isNull);
      expect(driveHintFromFlag(''), isNull);
    });
  });

  group('driveHintFromMessage', () {
    test('蜘蛛的「没配置」文案命中对应网盘', () {
      final baidu = driveHintFromMessage('还没有配置百度网盘 Cookie，请先去配置中心登录百度网盘');
      expect(baidu?.provider, 'baidu');
      expect(baidu?.supported, isTrue);

      final quark = driveHintFromMessage('quark cookie is empty');
      expect(quark?.provider, 'quark');
    });

    test('UC 的 token / 高会文案要求额外授权', () {
      final hint = driveHintFromMessage('UC网盘：token 已失效，请重新授权电视端');
      expect(hint?.provider, 'uc');
      expect(hint?.supported, isTrue);
      expect(hint?.needsToken, isTrue);
    });

    test('普通失败文案不产生提示', () {
      expect(driveHintFromMessage('分享链接失效或已取消'), isNull);
      expect(driveHintFromMessage(''), isNull);
    });
  });
}
