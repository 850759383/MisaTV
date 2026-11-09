import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_theme.dart';

/// 播放器弹幕层使用的轻量条目（从 [DanmakuItem] 转换而来）。
class DanmakuLine {
  const DanmakuLine({
    required this.time,
    required this.type,
    required this.text,
    this.size = 24,
    this.color = '#ffffff',
  });

  final double time;
  final String type; // scroll / top / bottom
  final String text;
  final int size;
  final String color;
}

/// 指定区域能容纳的轨道数：区域高度按 [regionRatio]（0.1–1.0）等比缩放。
int danmakuLaneCount({
  required double height,
  required double fontSize,
  required double regionRatio,
}) {
  final laneHeight = fontSize + 8;
  if (laneHeight <= 0) return 1;
  final ratio = regionRatio.clamp(0.1, 1.0).toDouble();
  final count = (height * ratio / laneHeight).floor();
  // 4K / 8K 下全屏需要的轨道可能超过旧上限 40；上限只防极端值，不能截断区域。
  return math.max(1, math.min(240, count));
}

/// 一条弹幕在时间轴上的排轨结果。
class DanmakuSlot {
  const DanmakuSlot({
    required this.index,
    required this.lane,
    required this.start,
    required this.life,
    required this.speed,
    required this.type,
  });

  /// 对应传入 `items` 的下标。
  final int index;
  final int lane;
  final double start;

  /// 在屏幕上的存活时长（视频秒）。
  final double life;
  final double speed;
  final String type;
}

/// 按时间轴给弹幕分配轨道；没有空轨的条目直接丢弃（不重叠）。
///
/// 滚动弹幕占用轨道的时间 = 文字宽度 / 速度 + 间距，保证同一条轨道
/// 上一条的尾巴完全进屏后才放行下一条。顶部 / 底部弹幕按固定 4 秒占轨。
/// 轨道数越少，被丢弃的弹幕越多 —— 这就是把显示区域调小后不会再“全挤在一小块”的原因。
List<DanmakuSlot> scheduleDanmaku({
  required List<DanmakuLine> items,
  required List<double> widths,
  required double width,
  required int laneCount,
  required double speed,
  double gap = 24,
  double fixedLife = 4.0,
  int fixedLanes = 3,
}) {
  final lanes = math.max(1, math.min(240, laneCount));
  final pxPerSecond = speed.clamp(20.0, 400.0).toDouble();
  final scrollFree = List<double>.filled(lanes, double.negativeInfinity);
  final topFree = List<double>.filled(lanes, double.negativeInfinity);
  final bottomFree = List<double>.filled(lanes, double.negativeInfinity);
  final order = [
    for (var i = 0; i < items.length; i++)
      if (i < widths.length) i,
  ]..sort((a, b) => items[a].time.compareTo(items[b].time));
  final out = <DanmakuSlot>[];
  final maxFixed = math.max(1, math.min(lanes, fixedLanes));

  for (final index in order) {
    final item = items[index];
    if (item.text.trim().isEmpty) continue;
    final textWidth = widths[index];
    if (textWidth <= 0) continue;
    if (item.type == 'top' || item.type == 'bottom') {
      final free = item.type == 'top' ? topFree : bottomFree;
      var lane = -1;
      var best = double.negativeInfinity;
      for (var i = 0; i < maxFixed; i++) {
        if (free[i] <= item.time && (lane < 0 || free[i] > best)) {
          best = free[i];
          lane = i;
        }
      }
      if (lane < 0) continue;
      free[lane] = item.time + fixedLife;
      out.add(
        DanmakuSlot(
          index: index,
          lane: lane,
          start: item.time,
          life: fixedLife,
          speed: 0,
          type: item.type,
        ),
      );
      continue;
    }

    var lane = -1;
    var best = double.negativeInfinity;
    for (var i = 0; i < lanes; i++) {
      if (scrollFree[i] <= item.time && (lane < 0 || scrollFree[i] > best)) {
        best = scrollFree[i];
        lane = i;
      }
    }
    if (lane < 0) continue;
    final life = (width + textWidth) / pxPerSecond;
    scrollFree[lane] = item.time + (textWidth + gap) / pxPerSecond;
    out.add(
      DanmakuSlot(
        index: index,
        lane: lane,
        start: item.time,
        life: life,
        speed: pxPerSecond,
        type: 'scroll',
      ),
    );
  }
  return out;
}

/// fvp 画面之上的弹幕层：滚动 / 顶部 / 底部三种。
///
/// 性能要点：
///   · 用 [CustomPainter] + 预排版 [TextPainter] 绘制，不再为每条弹幕建
///     `Positioned + Text`，避免播放器每帧重建整棵弹幕组件树；
///   · 用独立 [Ticker] 平滑时钟，不必等播放器低频的 position 回调，
///     弹幕滚动不会一跳一跳；
///   · 排轨时按时间轴给每条弹幕找空轨，找不到就丢弃（不重叠），
///     区域越小只保留对应高度能容纳的条数，而不是把所有弹幕挤进小区域。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.position,
    this.enabled = true,
    this.playing = true,
    this.rate = 1.0,
    this.fontSize = 24,
    this.opacity = 0.85,
    this.speed = 110,
    this.regionRatio = 1,
    this.density = 1,
  });

  final List<DanmakuLine> items;
  final Duration position;
  final bool enabled;
  final bool playing;

  /// 播放倍速：2x 时弹幕也按 2 倍速前进。
  final double rate;
  final double fontSize;
  final double opacity;
  final double speed;

  /// 弹幕显示区域占屏幕高度的比例（0.1–1.0，1 = 全屏）。
  final double regionRatio;

  /// 弹幕密度（0.1–1）：只按比例抽稀条目，不改变显示区域 / 轨道高度，1 = 全量。
  final double density;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _clockMs = ValueNotifier<int>(0);
  late final Ticker _ticker;
  DateTime _baseWall = DateTime.now();
  double _baseSeconds = 0;
  double _rate = 1;

  _DanmakuSchedule? _schedule;
  _ScheduleKey? _key;
  _DanmakuPainter? _painter;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _resetClock();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resumed = !oldWidget.playing && widget.playing;
    final reenabled = !oldWidget.enabled && widget.enabled;
    if (widget.position != oldWidget.position ||
        widget.rate != oldWidget.rate ||
        resumed ||
        reenabled) {
      _resetClock();
    }
    _syncTicker();
  }

  void _resetClock() {
    _baseSeconds =
        widget.position.inMicroseconds / Duration.microsecondsPerSecond;
    _baseWall = DateTime.now();
    _rate = widget.rate.clamp(0.25, 4.0);
    _clockMs.value = widget.position.inMilliseconds;
  }

  void _onTick(Duration _) {
    final elapsed =
        DateTime.now().difference(_baseWall).inMicroseconds /
        Duration.microsecondsPerSecond;
    _clockMs.value = ((_baseSeconds + elapsed * _rate) * 1000).round();
  }

  void _syncTicker() {
    final shouldTick =
        widget.enabled && widget.playing && widget.items.isNotEmpty;
    if (shouldTick) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _schedule?.dispose();
    _clockMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.items.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final key = _ScheduleKey(
                size: size,
                regionRatio: widget.regionRatio,
                fontSize: widget.fontSize,
                opacity: widget.opacity,
                speed: widget.speed,
                density: widget.density,
                items: widget.items,
              );
              if (_key != key) {
                _schedule?.dispose();
                _schedule = _buildSchedule(key);
                _painter = _DanmakuPainter(_schedule!, _clockMs);
                _key = key;
              }
              return SizedBox.expand(child: CustomPaint(painter: _painter!));
            },
          ),
        ),
      ),
    );
  }

  _DanmakuSchedule _buildSchedule(_ScheduleKey key) {
    final width = key.size.width;
    final regionHeight =
        key.size.height * key.regionRatio.clamp(0.1, 1.0).toDouble();
    final laneHeight = key.fontSize + 8;
    final density = key.density.clamp(0.1, 1.0).toDouble();
    // 显示区域只决定可用轨道高度；密度只抽稀条目数量，不能再压缩轨道数，
    // 否则「显示区域 100%」也会因为密度低而只占屏幕上方一小块。
    final laneCount = danmakuLaneCount(
      height: key.size.height,
      fontSize: key.fontSize,
      regionRatio: key.regionRatio,
    );

    final prepared = <_PreparedDanmaku>[];
    for (final item in key.items) {
      if (item.text.trim().isEmpty) continue;
      if (!_keepForDensity(item, density)) continue;
      final painter = _textPainter(item, key.fontSize, key.opacity);
      prepared.add(
        _PreparedDanmaku(item: item, painter: painter, width: painter.width),
      );
    }

    final slots = scheduleDanmaku(
      items: [for (final item in prepared) item.item],
      widths: [for (final item in prepared) item.width],
      width: width,
      laneCount: laneCount,
      speed: key.speed,
      fixedLanes: math.min(3, laneCount),
    );

    final used = <int>{};
    final entries = <_DanmakuEntry>[];
    for (final slot in slots) {
      used.add(slot.index);
      final preparedItem = prepared[slot.index];
      entries.add(
        _DanmakuEntry(
          painter: preparedItem.painter,
          textWidth: preparedItem.width,
          type: slot.type,
          start: slot.start,
          life: slot.life,
          lane: slot.lane,
          speed: slot.speed,
          laneHeight: laneHeight,
        ),
      );
    }
    // 被丢弃的条目不再参与绘制，及时释放 TextPainter。
    for (var i = 0; i < prepared.length; i++) {
      if (!used.contains(i)) prepared[i].painter.dispose();
    }
    return _DanmakuSchedule(
      entries: entries,
      width: width,
      regionHeight: regionHeight,
    );
  }

  /// 按密度抽稀：用「时间 + 文本」的稳定散列保留对应比例，同一视频重进或
  /// 拖动进度条后抽到的还是同一批，不会忽多忽少。
  static bool _keepForDensity(DanmakuLine item, double density) {
    if (density >= 0.999) return true;
    final bucket = Object.hash(item.time, item.text) % 1000;
    return bucket < (density * 1000).round();
  }

  TextPainter _textPainter(DanmakuLine item, double fontSize, double opacity) {
    final color = _colorOf(item.color).withValues(alpha: opacity);
    return TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontFamilyFallback: AppTheme.fontFamilyFallback,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  static Color _colorOf(String raw) {
    final text = raw.replaceFirst('#', '');
    final value = int.tryParse(text, radix: 16);
    if (value == null || text.length != 6) return Colors.white;
    return Color(0xFF000000 | value);
  }
}

class _PreparedDanmaku {
  const _PreparedDanmaku({
    required this.item,
    required this.painter,
    required this.width,
  });

  final DanmakuLine item;
  final TextPainter painter;
  final double width;
}

class _ScheduleKey {
  const _ScheduleKey({
    required this.size,
    required this.regionRatio,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.density,
    required this.items,
  });

  final Size size;
  final double regionRatio;
  final double fontSize;
  final double opacity;
  final double speed;
  final double density;
  final List<DanmakuLine> items;

  @override
  bool operator ==(Object other) =>
      other is _ScheduleKey &&
      other.size == size &&
      other.regionRatio == regionRatio &&
      other.fontSize == fontSize &&
      other.opacity == opacity &&
      other.speed == speed &&
      other.density == density &&
      identical(other.items, items);

  @override
  int get hashCode => Object.hash(
    size,
    regionRatio,
    fontSize,
    opacity,
    speed,
    density,
    identityHashCode(items),
  );
}

class _DanmakuSchedule {
  _DanmakuSchedule({
    required this.entries,
    required this.width,
    required this.regionHeight,
  });

  final List<_DanmakuEntry> entries;
  final double width;
  final double regionHeight;

  void dispose() {
    for (final entry in entries) {
      entry.painter.dispose();
    }
  }
}

class _DanmakuEntry {
  const _DanmakuEntry({
    required this.painter,
    required this.textWidth,
    required this.type,
    required this.start,
    required this.life,
    required this.lane,
    required this.speed,
    required this.laneHeight,
  });

  final TextPainter painter;
  final double textWidth;
  final String type;
  final double start;
  final double life;
  final int lane;
  final double speed;
  final double laneHeight;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.schedule, this.clock) : super(repaint: clock);

  final _DanmakuSchedule schedule;
  final ValueListenable<int> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final current = clock.value / 1000.0;
    final width = schedule.width;
    final regionHeight = schedule.regionHeight;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, regionHeight));
    for (final entry in schedule.entries) {
      final elapsed = current - entry.start;
      if (elapsed < 0 || elapsed > entry.life) continue;
      final double x;
      final double y;
      if (entry.type == 'top') {
        x = (width - entry.textWidth) / 2;
        y = entry.lane * entry.laneHeight;
      } else if (entry.type == 'bottom') {
        x = (width - entry.textWidth) / 2;
        y = regionHeight - entry.laneHeight - entry.lane * entry.laneHeight;
      } else {
        x = width - elapsed * entry.speed;
        y = entry.lane * entry.laneHeight;
        if (x > width || x + entry.textWidth < 0) continue;
      }
      entry.painter.paint(canvas, Offset(x, y));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) =>
      !identical(oldDelegate.schedule, schedule);
}
