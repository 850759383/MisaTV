/// 播放器「详情」里的实时网速平滑器。
///
/// libmdk 的实时 `bitRate` 是短窗口值：关键帧突发时会瞬间冲到几 Gbps，
/// 直接展示就是「网速乱跳 + 4000M/s」。这里用最近几次采样的中位数过滤
/// 单次尖峰，再做指数平滑（上升慢、下降稍快）。
class NetworkSpeedSmoother {
  static const int _window = 7;
  static const int _minSamples = 3;
  static const int _maxBits = 1000 * 1000 * 1000;
  static const int _outlierRatio = 4;
  static const int _outlierDelta = 50 * 1000 * 1000;

  final List<int> _samples = <int>[];
  int _value = 0;

  /// 平滑后的 bit/s；0 表示暂时不展示。
  int get value => _value;

  void reset() {
    _samples.clear();
    _value = 0;
  }

  void add(int bits) {
    if (bits <= 0) {
      reset();
      return;
    }
    // 超过 1 Gbps 的采样基本都是单位 / 瞬时突发异常，不当作网速展示。
    final sample = bits.clamp(0, _maxBits);
    _samples.add(sample);
    if (_samples.length > _window) _samples.removeAt(0);
    if (_samples.length < _minSamples) {
      // 前两次采样先不展示，避免开局那一下尖峰直接上屏。
      _value = 0;
      return;
    }
    final sorted = [..._samples]..sort();
    final median = sorted[sorted.length ~/ 2];
    var target = sample;
    if (sample > median * _outlierRatio && sample - median > _outlierDelta) {
      target = median;
    }
    if (_value <= 0) {
      // 开局先取最低值，避免第一屏就落在关键帧尖峰上。
      _value = sorted.first;
      return;
    }
    final alpha = target > _value ? 0.22 : 0.45;
    _value = (_value + (target - _value) * alpha).round();
  }
}
