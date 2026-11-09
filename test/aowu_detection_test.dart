import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/jar_spider/jar_spider.dart';

void main() {
  group('isAowuShellClass', () {
    test('wex 的 Guard 壳不按嗷呜处理', () {
      expect(isAowuShellClass('com.github.catvod.spider.WoggGuard'), isFalse);
      expect(
        isAowuShellClass('com.github.catvod.spider.WexAiHanXiaoQuanGuard'),
        isFalse,
      );
      expect(isAowuShellClass('com.github.catvod.spider.DoubanGuard'), isFalse);
    });

    test('嗷呜的 Amns / Aowu 壳仍走嗷呜路径', () {
      expect(isAowuShellClass('com.github.catvod.spider.WoggAmns'), isTrue);
      expect(isAowuShellClass('com.github.catvod.spider.TSaowuAmns'), isTrue);
      expect(isAowuShellClass('com.github.catvod.spider.AowuShinidie'), isTrue);
    });
  });

  group('isJarShimMissMessage', () {
    test('真实实现与壳版本不兼容的错误应回退 payload', () {
      expect(
        isJarShimMissMessage(
          'ShellShim 真实实现与壳版本不兼容（InitOrigin 签名不匹配）: '
          "NoSuchMethodError: 'java.lang.StringBuilder "
          "com.github.catvod.spider.merge.by.yq(java.lang.String)'",
        ),
        isTrue,
      );
      expect(
        isJarShimMissMessage(
          'Cannot invoke "android.content.Context.getSharedPreferences'
          '(String, int)" because "<parameter1>" is null',
        ),
        isTrue,
      );
      expect(
        isJarShimMissMessage(
          'Cannot invoke "com.github.catvod.crawler.Spider.init'
          '(android.content.Context, String)" because '
          '"this.o0oOoOOoOoOoOOo" is null',
        ),
        isTrue,
      );
      expect(isJarShimMissMessage('app-api-verify-sign == null'), isTrue);
      expect(
        isJarShimMissMessage(
          'A JSONObject text must begin with \'{\' at 1 [character 2 line 1]',
        ),
        isTrue,
      );
    });

    test('普通网络/业务错误不误判成壳不兼容', () {
      expect(isJarShimMissMessage('站点返回 HTTP 403'), isFalse);
      expect(isJarShimMissMessage('没有找到视频文件'), isFalse);
    });
  });
}
