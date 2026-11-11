/// TMDB 的两种鉴权方式（官方文档 API Reference → Authentication）：
///   · v3 API Key：32 位十六进制，作为 **query 参数** `api_key` 传；
///   · v4 Read Access Token：JWT，放在请求头 `Authorization: Bearer <token>`。
///
/// 两种不能混用：给 v4 Token 加 `api_key` 会被判 401，给 v3 Key 加 Bearer 头也一样。
/// 用户往往从 TMDB 页面整段复制（带 `Bearer `、带引号、带前后空白），所以这里先归一再判断。
enum TmdbCredentialKind { none, apiKey, readToken }

class TmdbCredential {
  const TmdbCredential._(this.kind, this.value, this.problem);

  final TmdbCredentialKind kind;
  final String value;

  /// 填了但明显不是 Key / Token 时的提示；合法或为空时为空串。
  final String problem;

  static const none = TmdbCredential._(TmdbCredentialKind.none, '', '');

  bool get isConfigured => kind != TmdbCredentialKind.none;
  bool get usesBearer => kind == TmdbCredentialKind.readToken;

  /// 请求头：只有 v4 Token 需要。
  Map<String, String> get headers =>
      usesBearer ? {'Authorization': 'Bearer $value'} : const {};

  /// 查询参数：只有 v3 Key 需要。
  Map<String, String> get queryParams =>
      isConfigured && !usesBearer ? {'api_key': value} : const {};

  /// 给设置页用的一行说明。
  String get label => switch (kind) {
    TmdbCredentialKind.readToken => 'v4 Read Access Token',
    TmdbCredentialKind.apiKey => 'v3 API Key',
    TmdbCredentialKind.none => '',
  };

  static final RegExp _v3Key = RegExp(r'^[0-9a-fA-F]{32}$');
  static final RegExp _jwt = RegExp(
    r'^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  );

  factory TmdbCredential.parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return none;
    // 整段粘贴：`Authorization: Bearer xxx`、`Bearer xxx`、带引号的值。
    text = text.replaceFirst(
      RegExp(r'^authorization\s*:\s*', caseSensitive: false),
      '',
    );
    text = text.replaceFirst(RegExp(r'^bearer\s+', caseSensitive: false), '');
    text = text.replaceAll('\u201c', '"').replaceAll('\u201d', '"');
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1);
    }
    text = text.trim();
    if (text.isEmpty) return none;
    if (_jwt.hasMatch(text)) {
      return TmdbCredential._(TmdbCredentialKind.readToken, text, '');
    }
    if (_v3Key.hasMatch(text)) {
      return TmdbCredential._(TmdbCredentialKind.apiKey, text, '');
    }
    // 兜底容错：带点的长串按 v4 Token，纯字母数字的 24 位以上按 v3 Key。
    if (text.length > 60 && !text.contains(' ')) {
      return TmdbCredential._(TmdbCredentialKind.readToken, text, '');
    }
    if (text.length >= 24 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(text)) {
      return TmdbCredential._(TmdbCredentialKind.apiKey, text, '');
    }
    return TmdbCredential._(
      TmdbCredentialKind.none,
      '',
      '看起来不是 TMDB 的 API Key（32 位）或 v4 Read Access Token（eyJ 开头的长串）',
    );
  }

  /// 从设置里的两个框解析出**实际使用**的凭据。
  ///
  /// TMDB 后台同时给「API 密钥（v3）」和「API 读访问令牌（v4）」，两者都能用；
  /// 同时填了两份时优先用令牌：令牌走请求头，不会把密钥带进 URL（也就不会进日志/代理）。
  /// 兼容旧配置：以前只有一个输入框，令牌粘在 key 框里也能当令牌用。
  static TmdbCredential resolve({String apiKey = '', String readToken = ''}) {
    final token = TmdbCredential.parse(readToken);
    if (token.isConfigured && token.usesBearer) return token;
    final key = TmdbCredential.parse(apiKey);
    if (key.isConfigured) return key;
    if (token.isConfigured) return token;
    // 两份都认不出：把更具体的提示带出去（有内容的那个优先）。
    if (readToken.trim().isNotEmpty) return token;
    return key;
  }

  /// 只在内部日志里用：绝不把明文 Key / Token 写进日志或界面。
  String get masked {
    if (!isConfigured) return '';
    if (value.length <= 8) return '••••';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  @override
  String toString() => isConfigured
      ? 'TmdbCredential(${kind.name}, $masked)'
      : 'TmdbCredential(none)';
}
