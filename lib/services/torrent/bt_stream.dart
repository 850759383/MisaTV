/// 磁力（BT）取流的宿主接口：中继 `/bt/<hash>/<index>` 依赖它读盘与做 piece 门控。
///
/// 由 `TorrentPlay` 实现；Web 版没有本地中继，永远不注入。
abstract class BtStreamSource {
  /// 命中会话且文件序号一致才返回（其余返回 null → 中继回 404）。
  BtStreamInfo? resolveStream(String infoHash, int fileIndex);

  /// 等 [start,end]（文件内相对字节）所在 piece 全部落盘；false = 超时/零进度放弃。
  ///
  /// [isCancelled] 供「磁力准备弹窗点取消」时**立即**中止等待，不再空转到超时。
  Future<bool> waitCovered(
    String infoHash,
    int fileIndex,
    int start,
    int end, {
    Duration? timeout,
    Duration? stall,
    bool Function()? isCancelled,
  });
}

/// 会话中选中文件的取流信息。
class BtStreamInfo {
  const BtStreamInfo({
    required this.absPath,
    required this.length,
    required this.fileOffset,
    required this.pieceLength,
  });

  final String absPath;
  final int length;

  /// 该文件在 torrent 数据流内的起始偏移（piece 映射必需）。
  final int fileOffset;
  final int pieceLength;
}
