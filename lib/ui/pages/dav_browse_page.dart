import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/dav.dart';
import '../../models/vod.dart';
import '../../services/player/external_players.dart';
import '../../services/relay/local_relay.dart';
import '../raw_play.dart';
import '../widgets/empty_state.dart';

/// WebDAV 目录浏览：只读列目录 + 点开视频播放（播放走本地 `/play?dav=` 中继注凭据）。
class DavBrowsePage extends StatefulWidget {
  const DavBrowsePage({super.key, required this.server});

  final DavServer server;

  @override
  State<DavBrowsePage> createState() => _DavBrowsePageState();
}

class _DavBrowsePageState extends State<DavBrowsePage> {
  static const String _flag = 'WebDAV';

  String _path = '/';
  bool _loading = true;
  String _error = '';
  DavBrowseResult? _data;
  int _seq = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load('/');
  }

  Future<void> _load(String path) async {
    final app = AppScope.of(context);
    final seq = ++_seq;
    setState(() {
      _path = path;
      _loading = true;
      _error = '';
    });
    try {
      final data = await app.davService.browse(widget.server.id, path: path);
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _data = data;
        _path = data.path;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _wrappedUrl(DavEntry entry) {
    final relay = LocalRelay.instance;
    if (!relay.running) return entry.url;
    return wrapDavPlayUrl(relay.baseUrl, entry.url, widget.server.id);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEntry(DavEntry entry) async {
    if (entry.isDir) {
      await _load(entry.path);
      return;
    }
    if (!looksVideo(entry.name)) {
      _toast('该文件不是视频');
      return;
    }
    final url = _wrappedUrl(entry);
    // mkv/avi 等容器交外部播放器；没有外部播放器时仍回落到内置（部分桌面内核能硬解）。
    if (!isDavInlinePlayable(entry.name)) {
      final players = detectExternalPlayers(
        custom: AppScope.of(context).customExternalPlayers,
      );
      if (players.isNotEmpty) {
        final player = players.firstWhere(
          (p) => externalPlayerExists(p.path),
          orElse: () => players.first,
        );
        final ok = launchExternalPlayer(player.path, url);
        _toast(
          ok ? '已在 ${player.name} 中打开（服务器不支持拖动，可能受限）' : '启动 ${player.name} 失败',
        );
        return;
      }
    }
    final videos = (_data?.entries ?? const <DavEntry>[])
        .where((e) => !e.isDir && looksVideo(e.name))
        .toList();
    if (videos.isEmpty) {
      _toast('这个目录里没有可播放的视频');
      return;
    }
    final episodes = [
      for (final item in videos)
        Episode(name: item.name, url: _wrappedUrl(item)),
    ];
    final index = videos.indexWhere((v) => v.path == entry.path);
    await openRawPlayback(
      context,
      title: entry.name,
      subtitle: 'WebDAV · ${widget.server.name}',
      episodes: episodes,
      initialIndex: index < 0 ? 0 : index,
      sourceKey: 'dav:${widget.server.id}',
      flag: _flag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
        actions: [
          if (_path != '/')
            IconButton(
              tooltip: '上一级',
              onPressed: () => _load(davParentPath(_path)),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(_path),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: '目录读取失败',
                message: _error,
                action: FilledButton.tonalIcon(
                  onPressed: () => _load(_path),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ),
            )
          : data == null || data.entries.isEmpty
          ? const Center(
              child: EmptyState(
                icon: Icons.folder_open_rounded,
                title: '空目录',
                message: '这里没有文件',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
              itemCount: data.entries.length + (_path == '/' ? 0 : 1),
              itemBuilder: (context, index) {
                if (_path != '/' && index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.arrow_upward_rounded),
                    title: const Text('上一级'),
                    onTap: () => _load(davParentPath(_path)),
                  );
                }
                final entry = data.entries[index - (_path == '/' ? 0 : 1)];
                final icon = entry.isDir
                    ? Icons.folder_rounded
                    : looksVideo(entry.name)
                    ? Icons.movie_outlined
                    : Icons.insert_drive_file_outlined;
                final size = entry.isDir ? '' : davSizeLabel(entry.size);
                return ListTile(
                  leading: Icon(
                    icon,
                    color: entry.isDir ? theme.colorScheme.primary : null,
                  ),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [size, entry.mtime].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openEntry(entry),
                );
              },
            ),
    );
  }
}
