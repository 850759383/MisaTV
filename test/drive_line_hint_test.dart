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
      final aliyun = driveHintFromFlag('阿里云盘');
      expect(aliyun?.provider, 'aliyun');
      expect(aliyun?.supported, isFalse);
    });

    test('115 与哔哩可配置凭据', () {
      final pan115 = driveHintFromFlag('115');
      expect(pan115?.provider, '115');
      expect(pan115?.supported, isTrue);
      // 115 没有网页扫码，只能手动粘贴 Cookie。
      expect(pan115?.webLogin, isFalse);
      expect(pan115?.optional, isFalse);

      final bili = driveHintFromFlag('B站');
      expect(bili?.provider, 'bili');
      expect(bili?.supported, isTrue);
      expect(bili?.webLogin, isFalse);
      // 哔哩没 Cookie 也能播 360P / 480P，不能拦播放。
      expect(bili?.optional, isTrue);
    });

    test('哔哩线路不会被其它规则抢走', () {
      expect(driveHintFromFlag('哔哩哔哩')?.provider, 'bili');
      expect(driveHintFromFlag('bilibili')?.provider, 'bili');
      expect(driveHintFromFlag('B 站 1080P')?.provider, 'bili');
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

    test('115 的未登录文案命中 115，且不是可选增强', () {
      final hint = driveHintFromMessage('还没有配置 115 网盘 Cookie，请先去配置中心');
      expect(hint?.provider, '115');
      expect(hint?.supported, isTrue);
      expect(hint?.optional, isFalse);
    });

    test('哔哩的未登录文案命中哔哩，且是可选增强（不拦播放）', () {
      final hint = driveHintFromMessage('哔哩哔哩 Cookie 已失效，请重新登录');
      expect(hint?.provider, 'bili');
      expect(hint?.supported, isTrue);
      // 没有 Cookie 也能播 360P / 480P，提示不能阻断播放。
      expect(hint?.optional, isTrue);
    });
  });
}
