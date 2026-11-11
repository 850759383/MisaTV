import 'package:shared_preferences/shared_preferences.dart';

/// Web 版没有本地安装目录，保持默认（无持久化数据目录）。
Future<String?> enablePortableAppData() async => null;

/// Web 版没有独立播放器窗口；这里只重置 shared_preferences 内存缓存。
Future<void> reloadPortablePrefs() async {
  try {
    await SharedPreferences.getInstance().then((prefs) => prefs.reload());
  } catch (_) {
    // 读取失败时保持当前内存值
  }
}
