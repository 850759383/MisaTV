import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../services/file_dialog_service.dart';
import '../../services/local_import_service.dart';
import '../../state/app_state.dart';
import 'glass.dart';
import 'name_input_dialog.dart';

Future<ImportOutcome?> showImportConfigSheet(BuildContext context) async {
  return showModalBottomSheet<ImportOutcome>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const _ImportSheet(),
    ),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _url = TextEditingController();
  final _json = TextEditingController();
  final _name = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tabs.dispose();
    _url.dispose();
    _json.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit(bool fromUrl) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final outcome = fromUrl
          ? await app.importFromUrl(_url.text, name: _name.text)
          : await app.importFromJson(_json.text, name: _name.text);
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _importLocal({required bool py}) async {
    if (_loading) return;
    final app = AppScope.of(context);
    try {
      if (py) {
        final paths = await FileDialogService.pickFiles(
          types: [FileDialogService.pyType],
        );
        if (paths == null || paths.isEmpty) return;
        setState(() {
          _loading = true;
          _error = null;
        });
        final sites = await LocalImportService.pySites(paths);
        if (!mounted) return;
        final target = await showPyImportTargetDialog(
          context,
          profiles: [
            for (final profile in app.profiles)
              if (!profile.isLiveOnly) profile,
          ],
          initialProfileId: app.activeProfile?.id,
          suggestedName: sites.length == 1
              ? sites.first['name'].toString()
              : (_name.text.trim().isEmpty ? '本地 PY 源' : _name.text.trim()),
          fileCount: sites.length,
        );
        if (target == null || !mounted) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        if (target.profileId != null) {
          final ok = await app.addSitesToProfile(target.profileId!, sites);
          if (!mounted) return;
          if (!ok) {
            setState(() {
              _loading = false;
              _error = '目标订阅无法添加站点（可能不是 JSON 配置）';
            });
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已把 ${sites.length} 个 PY 源加入订阅「${target.name}」'),
            ),
          );
          Navigator.of(context).pop();
          return;
        }
        final outcome = await app.importFromLocalText(
          jsonEncode({'sites': sites}),
          name: target.name,
        );
        if (!mounted) return;
        Navigator.of(context).pop(outcome);
        return;
      }

      final path = await FileDialogService.pickFile(
        types: [FileDialogService.jsonType],
      );
      if (path == null) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final payload = await LocalImportService.fromJsonFile(path);
      final outcome = await app.importFromLocalText(
        payload.text,
        name: payload.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '本地导入失败：$e';
      });
    }
  }

  Future<void> _importPackage({bool zip = false}) async {
    if (_loading) return;
    final app = AppScope.of(context);
    try {
      final path = zip
          ? await FileDialogService.pickFile(types: [FileDialogService.zipType])
          : await FileDialogService.pickDirectory();
      if (path == null) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final payload = zip
          ? await LocalImportService.fromPackageArchive(path)
          : await LocalImportService.fromPackage(path);
      final outcome = await app.importFromLocalText(
        payload.text,
        name: payload.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '本地包导入失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 小分辨率窗口里整块内容比屏幕还高：限制高度并让中间区域滚动，
    // 「开始导入 / 取消」固定在底部，永远不会被裁掉。
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导入源', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        '支持 TVBox JSON / 多仓订阅，以及 M3U、TXT 直播源地址。'
                        '直播订阅与点播订阅分开保存、分开切换。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: '配置名称（可选）',
                          hintText: '例如：我的订阅',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TabBar(
                        controller: _tabs,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.16,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        labelColor: theme.colorScheme.onSurface,
                        tabs: const [
                          Tab(text: '订阅地址'),
                          Tab(text: '粘贴 JSON'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 260,
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            ListView(
                              children: [
                                TextField(
                                  controller: _url,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    hintText: 'https://example.com/tvbox.json 或直播源 .m3u/.txt',
                                    prefixIcon: Icon(Icons.link_rounded),
                                  ),
                                  onSubmitted: (_) => _submit(true),
                                ),
                                const SizedBox(height: 14),
                                GlassPanel(
                                  padding: const EdgeInsets.all(14),
                                  borderRadius: 16,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          '导入时会按订阅地址解析 ./ 与 ../ 相对资源路径；配置仅保存在本机。',
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            TextField(
                              controller: _json,
                              minLines: 8,
                              maxLines: 10,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              decoration: const InputDecoration(
                                hintText: '在此粘贴 TVBox 配置 JSON',
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _importLocal(py: false),
                              icon: const Icon(
                                Icons.file_open_outlined,
                                size: 17,
                              ),
                              label: const Text('导入本地 JSON'),
                            ),
                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _importLocal(py: true),
                              icon: const Icon(Icons.code_rounded, size: 17),
                              label: const Text('导入本地 PY（可多选）'),
                            ),
                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _importPackage(),
                              icon: const Icon(
                                Icons.folder_open_rounded,
                                size: 17,
                              ),
                              label: const Text('导入本地包'),
                            ),
                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _importPackage(zip: true),
                              icon: const Icon(
                                Icons.archive_outlined,
                                size: 17,
                              ),
                              label: const Text('导入本地包 ZIP'),
                            ),
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _submit(_tabs.index == 0),
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(_loading ? '正在导入…' : '开始导入'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
