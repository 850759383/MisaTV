class LocalImportPayload {
  const LocalImportPayload({required this.name, required this.text});
  final String name;
  final String text;
}

class LocalImportService {
  const LocalImportService._();

  static Future<LocalImportPayload> fromJsonFile(String path) async =>
      throw UnsupportedError('Web 版不支持导入本地订阅文件');

  static Future<LocalImportPayload> fromPyFile(String path) async =>
      throw UnsupportedError('Web 版不支持导入本地 Python 蜘蛛');

  static Future<LocalImportPayload> fromPackage(String dirPath) async =>
      throw UnsupportedError('Web 版不支持导入本地包');

  static Future<LocalImportPayload> fromPackageArchive(String zipPath) async =>
      throw UnsupportedError('Web 版不支持导入本地包 ZIP');

  static Future<List<Map<String, dynamic>>> pySites(List<String> paths) async =>
      throw UnsupportedError('Web 版不支持导入本地 Python 蜘蛛');

  static String rewriteLocalPaths(String text, String packageRoot) => text;
}
