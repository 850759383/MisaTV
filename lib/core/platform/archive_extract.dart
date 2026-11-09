import 'package:archive/archive_io.dart';

/// 用 Dart 内置解压（不依赖系统 `tar.exe` / 7-Zip）。
///
/// 之前运行时安装走 `tar -xf`：部分精简版 Windows 没有 tar，或 Process 启动失败
/// 时只会得到「解压失败（tar 退出码 -1）」。这里直接读 zip（`.whl` 同样是 zip）。
Future<void> extractZipArchive(String zipPath, String targetDir) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    await extractArchiveToDisk(archive, targetDir);
  } finally {
    input.closeSync();
  }
}
