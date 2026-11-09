import 'package:flutter/material.dart';

import '../../models/user_data.dart';

/// 点播 / 直播播放器共用的「详情」指标设置结果。
class PlayerOverlaySettingsResult {
  const PlayerOverlaySettingsResult({
    required this.metrics,
    required this.fontSize,
  });

  final List<String> metrics;
  final double fontSize;
}

/// 「详情」悬浮层指标设置弹层：按四角分组勾选指标，并可调字号。
///
/// 点播和直播各自传入自己的指标全集与默认值；保存仍由调用方写回
/// [PlayerSettings.overlayMetrics] 或 [PlayerSettings.liveOverlayMetrics]。
Future<PlayerOverlaySettingsResult?> showPlayerOverlaySettings({
  required BuildContext context,
  required String title,
  required List<PlayerOverlayMetric> metrics,
  required List<String> defaultMetrics,
  required List<String> selectedMetrics,
  required double fontSize,
}) async {
  final selected = selectedMetrics
      .where((id) => metrics.any((metric) => metric.id == id))
      .toSet();
  var size = fontSize.clamp(10.0, 28.0).toDouble();
  return showModalBottomSheet<PlayerOverlaySettingsResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheet(() {
                        selected
                          ..clear()
                          ..addAll(defaultMetrics);
                        size = 14;
                      }),
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
                Text(
                  '勾选要显示的指标；播放器里的「详情」可随时开关，长按再次打开这里。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                for (final group in const [
                  ('tl', '左上角'),
                  ('tr', '右上角'),
                  ('bl', '左下角'),
                  ('br', '右下角'),
                ]) ...[
                  Text(
                    group.$2,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final metric in metrics.where(
                        (metric) => metric.corner == group.$1,
                      ))
                        FilterChip(
                          label: Text(metric.label),
                          selected: selected.contains(metric.id),
                          onSelected: (on) => setSheet(() {
                            if (on) {
                              selected.add(metric.id);
                            } else {
                              selected.remove(metric.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Text(
                      '字号',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 10,
                        max: 28,
                        divisions: 18,
                        value: size,
                        label: '${size.round()}',
                        onChanged: (v) => setSheet(() => size = v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${size.round()}px',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(
                      PlayerOverlaySettingsResult(
                        metrics: selected.toList(),
                        fontSize: size,
                      ),
                    ),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
