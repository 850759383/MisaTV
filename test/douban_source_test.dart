import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/services/discover/cover_images.dart';

void main() {
  test('豆瓣图床域名识别', () {
    expect(
      isDoubanImageUrl(
        'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p2195469915.jpg',
      ),
      isTrue,
    );
    expect(
      isDoubanImageUrl(
        'https://qnmob3-sign.doubanio.com/view/photo/large/public/p1.jpg',
      ),
      isTrue,
    );
    expect(isDoubanImageUrl('https://example.com/a.jpg'), isFalse);
    expect(isDoubanImageUrl(''), isFalse);
  });

  test('豆瓣推荐源识别（key 或 api 命中）', () {
    const byApi = SourceBean(
      key: 'drpy_js_豆瓣',
      name: '推荐',
      type: 3,
      api: 'csp_Douban',
    );
    expect(byApi.isDouban, isTrue);

    const byKey = SourceBean(key: '豆瓣', name: '豆瓣推荐', type: 3, api: 'csp_X');
    expect(byKey.isDouban, isTrue);

    const cms = SourceBean(
      key: 'cms',
      name: '豆瓣影视',
      type: 0,
      api: 'http://example.com/api.php/provide/vod',
    );
    expect(cms.isDouban, isFalse);
  });
}
