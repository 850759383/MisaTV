import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/models/site_config.dart';
import 'package:kniephos/ui/widgets/drive_config_sheet.dart';

SourceBean _site(String key, String name, String api) =>
    SourceBean(key: key, name: name, type: 3, api: api);

void main() {
  test('识别订阅里的网盘配置源', () {
    expect(
      isDriveConfigSource(
        _site('Wexconfig', '🐮通用类型┃配置中心🐮', 'csp_WexconfigGuard'),
      ),
      isTrue,
    );
    expect(
      isDriveConfigSource(
        _site('Wexokconfig', '🐮影视专用┃配置中心🐮', 'csp_WexokconfigGuard'),
      ),
      isTrue,
    );
    expect(
      isDriveConfigSource(_site('MyConfig', '⚙️配置┃中心', 'csp_AAConfigAmns')),
      isTrue,
    );
    expect(
      isDriveConfigSource(_site('PanConfig', '网盘设置', 'csp_PanConfigGuard')),
      isTrue,
    );
    // 饭太硬：`MyDriveGuard` 名称是「我的云盘┃配置」，不是网盘浏览源。
    expect(
      isDriveConfigSource(_site('MDrive', '🗂我的云盘┃配置', 'csp_MyDriveGuard')),
      isTrue,
    );
  });

  test('不误伤正常网盘浏览源和资源站', () {
    expect(
      isDriveConfigSource(_site('夸克', '💓我的┃夸克💓', 'csp_WexWoquarkpanGuard')),
      isFalse,
    );
    expect(
      isDriveConfigSource(
        _site('Doubanaaa', '⬇️【网盘类先扫码】⬇️', 'csp_DoubanGuard'),
      ),
      isFalse,
    );
    expect(
      isDriveConfigSource(_site('PanHj', '☁️花卷┃4K', 'csp_PanHjAmns')),
      isFalse,
    );
    // 真正的「我的网盘」浏览源没有「配置」字样，继续走正常视频列表。
    expect(
      isDriveConfigSource(_site('MyPan', '我的网盘', 'csp_MyPanGuard')),
      isFalse,
    );
  });
}
