/// 播放器画面比例（对齐 TVBox 的「画面比例」菜单）。
enum PlayerFit {
  contain('适应（保持比例）'),
  fill('拉伸填满'),
  cover('裁剪填满'),
  ratio169('强制 16:9'),
  ratio43('强制 4:3'),
  original('原始尺寸');

  const PlayerFit(this.label);
  final String label;
  String get id => name;
}

const List<PlayerFit> playerFits = PlayerFit.values;

PlayerFit normalizePlayerFit(String? value) {
  final v = (value ?? '').trim();
  for (final fit in PlayerFit.values) {
    if (fit.name == v) return fit;
  }
  return PlayerFit.contain;
}

String playerFitLabel(String? value) => normalizePlayerFit(value).label;
