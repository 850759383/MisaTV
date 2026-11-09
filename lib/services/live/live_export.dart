import '../../models/live.dart';

/// 直播输出：把已解析的分组按 _TXT_ / M3U 格式化成文本（纯本地，不发请求）。
class LiveExport {
  const LiveExport._();

  static const _eol = '\r\n';

  /// `分组,#genre#` + `名称,url`（能被 TxtSubscribe 再解析回来）。
  static String renderTxt(List<LiveGroup> groups) {
    final lines = <String>[];
    for (final group in groups) {
      final channels = group.channels.where((c) => c.urls.isNotEmpty).toList();
      if (channels.isEmpty) continue;
      lines.add('${group.group},#genre#');
      for (final channel in channels) {
        for (final url in channel.urls) {
          lines.add('${channel.name},$url');
        }
      }
    }
    return lines.isEmpty ? '' : '${lines.join(_eol)}$_eol';
  }

  /// 标准 M3U 播放列表（保留 tvg-id / tvg-name / 台标 / 分组）。
  static String renderM3u(List<LiveGroup> groups) {
    final lines = <String>['#EXTM3U'];
    for (final group in groups) {
      final channels = group.channels.where((c) => c.urls.isNotEmpty).toList();
      if (channels.isEmpty) continue;
      for (final channel in channels) {
        final attrs = <String>[
          'tvg-id="${channel.tvgId}"',
          'tvg-name="${channel.tvgName}"',
          'tvg-logo="${channel.logo}"',
          'group-title="${group.group}"',
        ].join(' ');
        for (final url in channel.urls) {
          lines.add('#EXTINF:-1 $attrs,${channel.name}');
          lines.add(url);
        }
      }
    }
    return lines.length <= 1 ? '' : '${lines.join(_eol)}$_eol';
  }

  /// 导出文件名：线路名 + 日期，去掉 Windows 不允许的字符。
  static String suggestedName(String liveName, String date, String ext) {
    final raw = '${liveName}_$date';
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${cleaned.isEmpty ? 'live' : cleaned}.$ext';
  }
}
