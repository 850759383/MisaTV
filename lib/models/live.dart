class LiveChannel {
  const LiveChannel({
    required this.name,
    required this.urls,
    this.logo = '',
    this.epg = '',
    this.ua = '',
    this.click = '',
    this.format = '',
    this.origin = '',
    this.referer = '',
    this.tvgId = '',
    this.tvgName = '',
    this.tvgChno = '',
    this.header,
    this.catchupType = '',
    this.catchupSource = '',
    this.catchupReplace = '',
  });

  final String name;
  final List<String> urls;
  final String logo;
  final String epg;
  final String ua;
  final String click;
  final String format;
  final String origin;
  final String referer;
  final String tvgId;
  final String tvgName;
  final String tvgChno;
  final Map<String, String>? header;
  final String catchupType;
  final String catchupSource;
  final String catchupReplace;
}

class LiveLine {
  const LiveLine({required this.index, required this.name, required this.url});
  final int index;
  final String name;
  final String url;
}

class LiveGroup {
  const LiveGroup({required this.group, required this.channels});
  final String group;
  final List<LiveChannel> channels;
}

List<LiveLine> channelLines(LiveChannel channel) {
  final out = <LiveLine>[];
  for (var i = 0; i < channel.urls.length; i++) {
    final raw = channel.urls[i];
    final parts = raw.split(r'$');
    final url = parts.first.trim();
    final name = parts.length > 1 && parts[1].trim().isNotEmpty ? parts[1].trim() : '源${i + 1}';
    if (url.isEmpty) continue;
    out.add(LiveLine(index: i + 1, name: name, url: url));
  }
  return out;
}
