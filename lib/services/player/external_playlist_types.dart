import '../../models/vod.dart';

/// 交到外部播放器前，把播放结果按本机中继口径包装。
typedef ExternalPreparePlayFn = PlayResult Function(
  PlayResult play, {
  bool forceRelay,
});

/// 云播播放页（`/play/<id>`、`/share/<hash>`）解成直链。
typedef ExternalUnwrapPlayFn = Future<PlayResult> Function(PlayResult play);

/// `/chunk` 取流地址预热；非本机取流地址直接返回 true。
typedef ExternalWarmUpFn = Future<bool> Function(String url);
