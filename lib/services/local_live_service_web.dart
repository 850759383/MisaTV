class LocalLiveImport {
  const LocalLiveImport({required this.name, required this.filePath});
  final String name;
  final String filePath;
}

class LocalLiveService {
  const LocalLiveService._();

  static Future<LocalLiveImport> importFile(String path) async =>
      throw UnsupportedError('Web 版不支持导入本地直播源');
}
