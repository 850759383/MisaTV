// 第三方播放器的选集播放列表：桌面端写 M3U，Web 端不可用。
export 'external_playlist_io.dart'
    if (dart.library.js_interop) 'external_playlist_web.dart';
