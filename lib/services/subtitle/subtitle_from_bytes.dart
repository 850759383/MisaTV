/// 字节 → 可用字幕：非归档直接解码；归档解压后挑最匹配的条目再解码。
///
/// 移植自旧版 `assrtProvider.ts` 的 `subtitleFromBytes`（纯函数，不做网络）。
library;

import 'archive.dart';
import 'pick_entry.dart';
import 'subtitle_models.dart';
import 'subtitle_text.dart';

SubtitleFile subtitleFromBytes(
  List<int> bytes, {
  String fileName = '',
  String videoName = '',
  String ep = '',
}) {
  final kind = detectArchiveKind(bytes);
  if (kind == null) {
    final text = SubtitleText.decode(bytes);
    if (text.trim().isEmpty) {
      throw const SubtitleException('字幕内容为空或无法解码');
    }
    return SubtitleFile(
      name: fileName,
      format: extOf(fileName),
      text: text,
    );
  }

  final entries = extractArchiveEntries(bytes);
  if (entries.isEmpty) {
    throw SubtitleException(
      '${kind.label} 压缩包解压失败或包内无文件',
    );
  }
  final picked = pickSubtitleEntry<ArchiveEntry>(
    entries,
    opts: PickOptions(videoName: videoName, ep: ep),
  );
  if (picked == null) {
    throw SubtitleException(
      '压缩包内未找到字幕文件（共 ${entries.length} 个条目）',
    );
  }
  final text = SubtitleText.decode(picked.bytes);
  if (text.trim().isEmpty) {
    throw SubtitleException('包内字幕解码为空：${picked.name}');
  }
  return SubtitleFile(
    name: picked.name,
    format: extOf(picked.name),
    text: text,
  );
}
