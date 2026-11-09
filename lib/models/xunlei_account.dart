import 'dart:convert';

/// 迅雷云盘登录态（只存令牌，不存账号密码）。
class XunleiAccount {
  const XunleiAccount({
    this.accessToken = '',
    this.refreshToken = '',
    this.tokenType = 'Bearer',
    this.expiresAt = 0,
    this.userId = '',
    this.nickName = '',
    this.deviceId = '',
    this.peerId = '',
    this.enabled = true,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  /// access_token 过期时间（毫秒时间戳）；0 = 未记录。
  final int expiresAt;
  final String userId;
  final String nickName;

  /// 登录设备 id（32 位十六进制，首次登录生成后固定）。
  final String deviceId;

  /// 登录请求里的 peerID（32 位十六进制，与 deviceId 一起固定）。
  final String peerId;

  /// 是否优先把磁力交给迅雷云盘离线下载。
  final bool enabled;

  bool get loggedIn => refreshToken.trim().isNotEmpty;

  bool get tokenExpired =>
      expiresAt > 0 &&
      DateTime.now().millisecondsSinceEpoch >= expiresAt - 60 * 1000;

  String get displayName {
    if (nickName.trim().isNotEmpty) return nickName.trim();
    if (userId.trim().isNotEmpty) {
      final id = userId.trim();
      return id.length <= 6 ? '迅雷用户 $id' : '迅雷用户 ${id.substring(0, 6)}…';
    }
    return '迅雷账号';
  }

  XunleiAccount copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    int? expiresAt,
    String? userId,
    String? nickName,
    String? deviceId,
    String? peerId,
    bool? enabled,
  }) {
    return XunleiAccount(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId ?? this.userId,
      nickName: nickName ?? this.nickName,
      deviceId: deviceId ?? this.deviceId,
      peerId: peerId ?? this.peerId,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': tokenType,
    'expiresAt': expiresAt,
    'userId': userId,
    'nickName': nickName,
    'deviceId': deviceId,
    'peerId': peerId,
    'enabled': enabled,
  };

  String toJsonString() => jsonEncode(toJson());

  factory XunleiAccount.fromJson(Map<String, dynamic> json) {
    return XunleiAccount(
      accessToken: (json['accessToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      tokenType: (json['tokenType'] ?? '').toString().trim().isEmpty
          ? 'Bearer'
          : json['tokenType'].toString(),
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] ?? '').toString(),
      nickName: (json['nickName'] ?? '').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      peerId: (json['peerId'] ?? '').toString(),
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  static XunleiAccount fromJsonString(String raw) {
    if (raw.trim().isEmpty) return const XunleiAccount();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return XunleiAccount.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const XunleiAccount();
  }
}
