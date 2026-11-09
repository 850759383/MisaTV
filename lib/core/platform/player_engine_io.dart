import 'package:flutter/foundation.dart';
import 'package:fvp/fvp.dart' as fvp;

/// 在桌面端用 fvp 接管 video_player，获得 HLS / MKV / FLV 等格式支持。
///
/// Android 继续使用官方 ExoPlayer 实现，不覆盖。
void setupPlayerEngine() {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    fvp.registerWith(
      options: {
        'platforms': ['windows', 'linux', 'macos'],
      },
    );
  }
}
