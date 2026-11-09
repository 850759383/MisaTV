/// 字幕压缩包解压（zip / gz）。
///
/// 移植自旧版 `src/main/subtitle/archive.ts`。旧版 rar/7z/bz2 依赖 wasm，
/// Flutter 侧不引入额外依赖，因此这三种格式明确不支持并抛出中文原因。
library;

import 'package:archive/archive.dart';

import 'pick_entry.dart';
import 'subtitle_models.dart';

enum ArchiveKind { zip, gz, rar, sevenZip, bz2 }

extension ArchiveKindX on ArchiveKind {
  String get label => switch (this) {
    ArchiveKind.zip => 'ZIP',
    ArchiveKind.gz => 'GZ',
    ArchiveKind.rar => 'RAR',
    ArchiveKind.sevenZip => '7Z',
    ArchiveKind.bz2 => 'BZ2',
  };

  bool get supported => this == ArchiveKind.zip || this == ArchiveKind.gz;
}

/// 归档类型识别（魔数；非归档返回 null）。允许短字节数组。
ArchiveKind? detectArchiveKind(List<int> bytes) {
  if (bytes.length < 2) return null;
  if (bytes.length >= 4 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x61 &&
      bytes[2] == 0x72 &&
      bytes[3] == 0x21) {
    return ArchiveKind.rar; // Rar!
  }
  if (bytes[0] == 0x50 && bytes[1] == 0x4b) return ArchiveKind.zip; // PK
  if (bytes[0] == 0x1f && bytes[1] == 0x8b) return ArchiveKind.gz;
  if (bytes.length >= 6 &&
      bytes[0] == 0x37 &&
      bytes[1] == 0x7a &&
      bytes[2] == 0xbc &&
      bytes[3] == 0xaf &&
      bytes[4] == 0x27 &&
      bytes[5] == 0x1c) {
    return ArchiveKind.sevenZip;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x42 &&
      bytes[1] == 0x5a &&
      bytes[2] == 0x68) {
    return ArchiveKind.bz2; // BZh
  }
  return null;
}

/// 包内条目。
class ArchiveEntry extends PickableEntry {
  ArchiveEntry({required super.name, required super.bytes});
}

/// 解出归档内的全部文件条目（目录项剔除）。
///
/// zip/gz 解不出来时返回空数组（调用方给出可读原因），绝不抛错；
/// rar/7z/bz2 明确不支持，抛 [SubtitleException]。
List<ArchiveEntry> extractArchiveEntries(List<int> bytes) {
  final kind = detectArchiveKind(bytes);
  if (kind == null) return const <ArchiveEntry>[];
  if (!kind.supported) {
    throw SubtitleException(
      '暂不支持解压 ${kind.label} 压缩包，请手动解压后选择字幕文件',
    );
  }
  try {
    if (kind == ArchiveKind.zip) return _zipEntries(bytes);
    return _gunzipEntry(bytes);
  } catch (_) {
    return const <ArchiveEntry>[];
  }
}

List<ArchiveEntry> _zipEntries(List<int> bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <ArchiveEntry>[];
    for (final f in archive.files) {
      if (f.isDirectory || f.name.endsWith('/')) continue;
      final data = f.content;
      if (data.isEmpty) continue;
      out.add(ArchiveEntry(name: f.name, bytes: data));
    }
    return out;
  } catch (_) {
    return const <ArchiveEntry>[];
  }
}

/// gzip：单文件流；条目名优先取头里的 FNAME，缺失时用占位名。
List<ArchiveEntry> _gunzipEntry(List<int> bytes) {
  final data = const GZipDecoder().decodeBytes(bytes);
  return <ArchiveEntry>[
    ArchiveEntry(name: _gzName(bytes) ?? 'subtitle.srt', bytes: data),
  ];
}

/// gzip 头 FNAME 字段（FLG bit3；偏移 10 起，0 结尾）。
String? _gzName(List<int> buf) {
  if (buf.length < 11) return null;
  final flg = buf[3];
  if ((flg & 0x08) == 0) return null;
  var end = 10;
  while (end < buf.length && buf[end] != 0) {
    end++;
  }
  if (end <= 10) return null;
  final raw = String.fromCharCodes(buf.sublist(10, end));
  final name = raw.replaceAll('\\', '/').split('/').last;
  return name.isEmpty ? null : name;
}
