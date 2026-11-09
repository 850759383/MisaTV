import 'drive_login_types.dart';

/// 一条线路（flag）或一条错误文案指向的网盘。
///
/// 用来回答两个问题：这条线路要登录哪个网盘？本机能不能直接扫码登录？
class DriveLineHint {
  const DriveLineHint({
    required this.provider,
    required this.name,
    required this.supported,
    this.needsToken = false,
  });

  /// 与 `driveAccounts` / `driveProviderNames` 一致的键（quark / uc / baidu…）。
  final String provider;
  final String name;

  /// 本机内置了扫码登录（夸克 / UC / 百度）。
  final bool supported;

  /// 除了 Cookie 还需要额外授权（目前只有 UC 电视端令牌）。
  final bool needsToken;
}

class _HintRule {
  const _HintRule(this.provider, this.name, this.patterns, {this.supported = false});

  final String provider;
  final String name;
  final List<Pattern> patterns;
  final bool supported;
}

/// 顺序即优先级：先认能扫码的三家，再认只能换线路的其它网盘。
final _rules = <_HintRule>[
  _HintRule('quark', driveProviderNames['quark']!, [
    '夸克',
    RegExp('quark', caseSensitive: false),
  ], supported: true),
  _HintRule('baidu', driveProviderNames['baidu']!, [
    '百度',
    RegExp('baidu', caseSensitive: false),
  ], supported: true),
  _HintRule('uc', driveProviderNames['uc']!, [
    // 避免把 quark / uhd 之类误判成 UC。
    RegExp(r'(^|[^a-z])uc([^a-z]|$)', caseSensitive: false),
    '优视',
  ], supported: true),
  _HintRule('aliyun', '阿里云盘', [
    '阿里',
    RegExp('aliyun', caseSensitive: false),
    RegExp(r'(^|[^a-z])ali([^a-z]|$)', caseSensitive: false),
  ]),
  _HintRule('pan115', '115 网盘', [
    RegExp(r'(^|[^0-9])115([^0-9]|$)'),
  ]),
  _HintRule('pan123', '123 云盘', [
    RegExp(r'(^|[^0-9])123([^0-9]|$)'),
    '123盘',
  ]),
  _HintRule('pan139', '移动云盘', [
    RegExp(r'(^|[^0-9])139([^0-9]|$)'),
    '移动云',
  ]),
  _HintRule('pan189', '天翼云盘', [
    RegExp(r'(^|[^0-9])189([^0-9]|$)'),
    '天翼',
  ]),
  _HintRule('guangya', '光雅云盘', [
    '光雅',
    RegExp('guangya', caseSensitive: false),
  ]),
  _HintRule('thunder', '迅雷', [
    '迅雷',
    RegExp('thunder', caseSensitive: false),
  ]),
  _HintRule('pikpak', 'PikPak', [
    RegExp('pikpak', caseSensitive: false),
  ]),
  _HintRule('magnet', '磁力链接', [
    '磁力',
    RegExp('magnet', caseSensitive: false),
  ]),
];

final _ucTokenPattern = RegExp(
  r'token|高会|电视端|TV\s*授权',
  caseSensitive: false,
);

DriveLineHint? _matchRule(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  for (final rule in _rules) {
    for (final pattern in rule.patterns) {
      if (pattern.allMatches(value).isNotEmpty) {
        return DriveLineHint(
          provider: rule.provider,
          name: rule.name,
          supported: rule.supported,
        );
      }
    }
  }
  return null;
}

/// 线路名（如「夸克原画」「百度」「UC」）→ 需要的网盘。
DriveLineHint? driveHintFromFlag(String flag) => _matchRule(flag);

/// 蜘蛛的失败文案（如「还没有配置百度网盘 Cookie」）→ 需要补登录的网盘。
DriveLineHint? driveHintFromMessage(String message) {
  final hint = _matchRule(message);
  if (hint == null) return null;
  if (!hint.supported || hint.provider != 'uc') return hint;
  if (!_ucTokenPattern.hasMatch(message)) return hint;
  return DriveLineHint(
    provider: hint.provider,
    name: hint.name,
    supported: true,
    needsToken: true,
  );
}
