import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/services/play_page_unwrap.dart';

void main() {
  group('PlayPageUnwrap', () {
    test('识别云播播放页/分享页', () {
      expect(
        PlayPageUnwrap.needsUnwrap('https://hn.bfvvs.com/play/dL9YVj4e'),
        isTrue,
      );
      expect(
        PlayPageUnwrap.needsUnwrap(
          'https://vodcnd17.ky32e.com/share/Ho2ezRYGZn',
        ),
        isTrue,
      );
      expect(
        PlayPageUnwrap.needsUnwrap(
          'https://hn.bfvvs.com/play/dL9YVj4e/index.m3u8',
        ),
        isFalse,
      );
      expect(
        PlayPageUnwrap.needsUnwrap('https://cdn.example.com/a.mp4'),
        isFalse,
      );
      expect(
        PlayPageUnwrap.needsUnwrap('http://127.0.0.1:9978/proxy?do=live'),
        isFalse,
      );
    });

    test('提取 const vid 的绝对直链', () {
      const html = """
      <script>
      const vid = 'https://hn.bfvvs.com/play/dL9YVj4e/index.m3u8';
      </script>
      """;
      expect(
        PlayPageUnwrap.extractMediaUrl(
          html,
          'https://hn.bfvvs.com/play/dL9YVj4e',
        ),
        'https://hn.bfvvs.com/play/dL9YVj4e/index.m3u8',
      );
    });

    test('提取 var main 的相对清单并补全域名', () {
      const html =
          '<script>var main = "/20260724/q6oju1DY/index.m3u8";</script>';
      expect(
        PlayPageUnwrap.extractMediaUrl(
          html,
          'https://vodcnd16.0jtv2.com/share/WgtdMnoieh',
        ),
        'https://vodcnd16.0jtv2.com/20260724/q6oju1DY/index.m3u8',
      );
    });

    test('提取转义斜杠的 main 与签名参数', () {
      const html =
          r'<script>var main = "\/20261021\/13873_29bdda88\/index.m3u8?sign=abc";</script>';
      expect(
        PlayPageUnwrap.extractMediaUrl(
          html,
          'https://svip.ryiplay18.com/share/827cf4bc2f28f73e24c151cad3be7567',
        ),
        'https://svip.ryiplay18.com/20261021/13873_29bdda88/index.m3u8?sign=abc',
      );
    });

    test('没有 main 时退回 playlist 里的相对地址', () {
      const html =
          '<script>var playlist = \'[{"url":"/20261008/q1QuUgw8/517kb/hls/index.m3u8"}]\';</script>';
      expect(
        PlayPageUnwrap.extractMediaUrl(
          html,
          'https://vodcnd17.ky32e.com/share/Ho2ezRYGZn',
        ),
        'https://vodcnd17.ky32e.com/20261008/q1QuUgw8/517kb/hls/index.m3u8',
      );
    });

    test('图片地址（封面 / 图床模板）在打开播放器前被识别', () {
      // 真机日志里的「嗷呜橘汁」线路：源站把图床变换地址当播放地址。
      expect(
        looksLikeImageMediaUrl(
          'https://p3-heycan-sign.byteimg.com/tos-cn-i-3jr8j4ixpe/'
          'bc2147ca48a046c1b36c7e78cd542373~tplv-q356p4ooq1-image.image?rk3s=1',
        ),
        isTrue,
      );
      expect(
        looksLikeImageMediaUrl('https://cdn.example.com/poster/cover.jpg'),
        isTrue,
      );
      // 视频（含带签名的 query）不受影响。
      expect(
        looksLikeImageMediaUrl('https://cdn.example.com/a.mp4?sign=abc'),
        isFalse,
      );
      expect(
        looksLikeImageMediaUrl(
          'https://cdn.example.com/media/index.m3u8?image=1',
        ),
        isFalse,
      );
      expect(
        looksLikeImageMediaUrl('http://127.0.0.1:9978/play?url=a.mp4'),
        isFalse,
      );
    });

    test('页面里没有直链时返回 null', () {
      expect(
        PlayPageUnwrap.extractMediaUrl(
          '<html><body>404 Not Found</body></html>',
          'https://hn.bfvvs.com/play/x',
        ),
        isNull,
      );
    });
  });
}
