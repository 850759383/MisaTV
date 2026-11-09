import 'dart:io';

import 'package:path/path.dart' as p;

/// 本地文件 → `file://` URL。
///
/// TVBox 的本地 Python / JAR 源按 `file://` 前缀识别；这里统一成
/// `file:///C:/dir/名称.py` 形态，空格与中文由 [Uri] 负责转义。
String fileUrlOf(String path) {
  final absolute = p.normalize(p.absolute(path));
  var unix = absolute.replaceAll('\\', '/');
  if (!unix.startsWith('/')) unix = '/$unix';
  return Uri(scheme: 'file', path: unix).toString();
}

/// `file://` URL → 本地绝对路径（Windows 下还原盘符与反斜杠）。
String filePathOf(String url) {
  if (!url.startsWith('file://')) return url;
  try {
    return Uri.parse(url).toFilePath(windows: Platform.isWindows);
  } catch (_) {
    var raw = url.substring('file://'.length);
    if (Platform.isWindows && RegExp(r'^/[A-Za-z]:').hasMatch(raw)) {
      raw = raw.substring(1);
    }
    return Uri.decodeFull(raw);
  }
}
