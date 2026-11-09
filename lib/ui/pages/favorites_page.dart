import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/user_data.dart';
import '../../models/vod.dart';
import '../../state/app_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_card.dart';
import 'detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    // 进页时静默检查一次收藏更新（AppState 内部 30 分钟节流）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkUpdates());
    });
  }

  Future<void> _checkUpdates({bool force = false}) async {
    final app = AppScope.of(context);
    final found = await app.checkFavoriteUpdates(force: force);
    if (!mounted || found <= 0) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('发现 $found 部收藏有更新')));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final updateCount = app.favoriteUpdateCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final maxWidth = constraints.maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      narrow ? 18 : 28,
                      8,
                      narrow ? 18 : 28,
                      14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '我的片单',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: 26,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '收藏 ${app.favorites.length} 部'
                                '${updateCount > 0 ? ' · $updateCount 部有更新' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: updateCount > 0
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: app.favoriteChecking
                              ? null
                              : () => _checkUpdates(force: true),
                          icon: app.favoriteChecking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(app.favoriteChecking ? '检查中' : '检查更新'),
                        ),
                      ],
                    ),
                  ),
                ),
                ..._favoritesSlivers(context, app, narrow),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _favoritesSlivers(
    BuildContext context,
    AppState app,
    bool narrow,
  ) {
    if (app.favorites.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.favorite_border_rounded,
            title: '还没有收藏',
            message: '在详情页点击心形按钮，把想看的留在这里',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(narrow ? 18 : 28, 0, narrow ? 18 : 28, 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 188,
            mainAxisExtent: 292,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = app.favorites[index];
            return PosterCard(
              item: VodItem(
                id: item.vodId,
                name: item.displayTitle,
                pic: item.pic,
                remarks: item.hasUpdate && item.updateNote.isNotEmpty
                    ? item.updateNote
                    : (item.note.isNotEmpty ? item.note : item.remarks),
                year: item.year,
                type: item.type,
                sourceKey: item.sourceKey,
                sourceName: item.sourceName,
              ),
              badge: item.hasUpdate ? '有更新' : '',
              onSecondaryLongPress: () => app.requestSearch(item.name),
              onTap: () async {
                await app.markFavoriteSeen(item.key);
                if (!context.mounted) return;
                if (app.isDoubanSourceKey(item.sourceKey)) {
                  app.requestSearch(item.name);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetailPage(
                      item: VodItem(
                        id: item.vodId,
                        name: item.name,
                        pic: item.pic,
                        remarks: item.remarks,
                        sourceKey: item.sourceKey,
                      ),
                    ),
                  ),
                );
              },
              onLongPress: () => _favActions(context, item),
            );
          }, childCount: app.favorites.length),
        ),
      ),
    ];
  }

  Future<void> _favActions(BuildContext context, FavoriteItem item) async {
    final app = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑标题与备注'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _editFavorite(context, item);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: const Text('取消收藏'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  app.removeFavorite(item.key);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editFavorite(BuildContext context, FavoriteItem item) async {
    final app = AppScope.of(context);
    final title = TextEditingController(text: item.title);
    final note = TextEditingController(text: item.note);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑收藏'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '显示标题（留空使用片名）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注 / 短评'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await app.updateFavorite(
        item.key,
        title: title.text.trim(),
        note: note.text.trim(),
      );
    }
  }
}
