import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/torrent/xunlei_cloud.dart';
import '../../state/app_state.dart';
import 'xunlei_verify_dialog.dart';

/// 迅雷云盘登录弹窗；成功后返回 true。
Future<bool> showXunleiLoginDialog(BuildContext context, AppState app) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _XunleiLoginDialog(app: app),
  );
  return result == true;
}

enum _LoginMode { password, refreshToken }

class _XunleiLoginDialog extends StatefulWidget {
  const _XunleiLoginDialog({required this.app});
  final AppState app;

  @override
  State<_XunleiLoginDialog> createState() => _XunleiLoginDialogState();
}

class _XunleiLoginDialogState extends State<_XunleiLoginDialog> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _mobile = TextEditingController();
  final _smsCode = TextEditingController();
  final _refreshToken = TextEditingController();

  _LoginMode _mode = _LoginMode.password;
  XunleiLoginStep? _smsStep;
  bool _busy = false;
  bool _smsSent = false;
  String _error = '';

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _mobile.dispose();
    _smsCode.dispose();
    _refreshToken.dispose();
    super.dispose();
  }

  bool _looksLikePhone(String value) =>
      RegExp(r'^\+?\d{11,18}$').hasMatch(value.trim());

  /// 发短信接口建议不带 +86；用户名里带区号时先去掉再预填。
  String _phoneForSms(String value) {
    final phone = value.trim();
    return phone.startsWith('+86') ? phone.substring(3) : phone;
  }

  Future<void> _loginWithPassword() async {
    if (_busy) return;
    final username = _account.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写迅雷账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _smsStep = null;
      _smsSent = false;
    });
    try {
      final step = await widget.app.loginXunlei(
        username: username,
        password: password,
      );
      if (!mounted) return;
      if (step.success) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        if (step.needSms) {
          _smsStep = step;
          if (_mobile.text.trim().isEmpty && _looksLikePhone(username)) {
            _mobile.text = _phoneForSms(username);
          }
        } else {
          _error = step.message.isEmpty ? '登录失败' : step.message;
        }
      });
    } on XunleiCloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '登录失败：$e';
      });
    }
  }

  Future<void> _sendSms() async {
    if (_busy) return;
    final mobile = _mobile.text.trim();
    if (mobile.isEmpty) {
      setState(() => _error = '请填写接收验证码的手机号');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final step = await widget.app.sendXunleiSms(mobile);
      if (!mounted) return;
      final previous = _smsStep;
      setState(() {
        _busy = false;
        _smsSent = step.creditKey.isNotEmpty;
        _smsStep = (previous ?? const XunleiLoginStep(needSms: true)).copyWith(
          needSms: true,
          creditKey: step.creditKey.isNotEmpty
              ? step.creditKey
              : previous?.creditKey,
          smsToken: step.smsToken.isNotEmpty
              ? step.smsToken
              : previous?.smsToken,
          message: step.message,
        );
      });
    } on XunleiCloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '短信发送失败：$e';
      });
    }
  }

  Future<void> _completeSmsLogin() async {
    if (_busy) return;
    final step = _smsStep;
    final code = _smsCode.text.trim();
    final mobile = _mobile.text.trim();
    if (step == null) return;
    if (mobile.isEmpty || code.isEmpty) {
      setState(() => _error = '请填写手机号和短信验证码');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.app.completeXunleiSmsLogin(
        mobile: mobile,
        code: code,
        creditKey: step.creditKey,
        smsToken: step.smsToken,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on XunleiCloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '验证码校验失败：$e';
      });
    }
  }

  Future<void> _loginWithRefreshToken() async {
    if (_busy) return;
    final token = _refreshToken.text.trim();
    if (token.isEmpty) {
      setState(() => _error = '请粘贴 refresh_token');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _smsStep = null;
      _smsSent = false;
    });
    try {
      await widget.app.loginXunleiWithRefreshToken(token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on XunleiCloudException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '刷新令牌登录失败：$e';
      });
    }
  }

  Future<void> _pasteRefreshToken() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty && mounted) {
      setState(() => _refreshToken.text = text);
    }
  }

  Future<void> _verifyInApp() async {
    final step = _smsStep;
    if (step == null || step.reviewUrl.isEmpty) return;
    final ok = await showXunleiVerifyDialog(
      context,
      reviewUrl: step.reviewUrl,
      deviceId: widget.app.xunleiAccount.deviceId,
    );
    if (!mounted || !ok) return;
    // 设备已验证通过：清掉短信步骤，重新走一次密码登录。
    setState(() {
      _smsStep = null;
      _smsSent = false;
      _error = '';
    });
    await _loginWithPassword();
  }

  Future<void> _retryAfterVerify() async {
    if (_busy) return;
    setState(() {
      _smsStep = null;
      _smsSent = false;
      _error = '';
    });
    await _loginWithPassword();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smsStep = _smsStep;
    return AlertDialog(
      title: const Text('登录迅雷云盘'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (smsStep == null)
                SegmentedButton<_LoginMode>(
                  segments: const [
                    ButtonSegment(
                      value: _LoginMode.password,
                      label: Text('账号密码'),
                      icon: Icon(Icons.password_rounded),
                    ),
                    ButtonSegment(
                      value: _LoginMode.refreshToken,
                      label: Text('刷新令牌'),
                      icon: Icon(Icons.key_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _mode = value.first;
                          _error = '';
                        }),
                ),
              const SizedBox(height: 14),
              if (smsStep == null && _mode == _LoginMode.password) ...[
                Text(
                  '登录后磁力会先提交到迅雷云盘离线下载；账号密码登录若触发安全验证，'
                  '会直接进入短信验证码流程。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _account,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '迅雷账号',
                    hintText: '手机号 / 邮箱 / 用户名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  onSubmitted: (_) => _loginWithPassword(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _loginWithPassword,
                    child: Text(_busy ? '登录中…' : '登录'),
                  ),
                ),
              ],
              if (smsStep != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '账号密码登录触发了迅雷安全验证',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        smsStep.message.isEmpty
                            ? '请输入短信验证码完成登录。'
                            : smsStep.message,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _mobile,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    hintText: '接收短信验证码的手机号（不带 +86）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _smsCode,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _completeSmsLogin(),
                        decoration: const InputDecoration(
                          labelText: '短信验证码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _busy ? null : _sendSms,
                      child: Text(_smsSent ? '重新发送' : '发送验证码'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _completeSmsLogin,
                    child: Text(_busy ? '验证中…' : '验证并登录'),
                  ),
                ),
                if (smsStep.reviewUrl.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '收不到短信时，可在应用内完成安全验证后自动重新登录。',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _verifyInApp,
                        child: const Text('应用内验证'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _retryAfterVerify,
                        child: const Text('已验证，重试'),
                      ),
                    ],
                  ),
                ],
              ],
              if (smsStep == null && _mode == _LoginMode.refreshToken) ...[
                Text(
                  '刷新令牌登录不需要密码与短信验证。可在已登录迅雷的机器上抓包 '
                  'POST /v1/auth/token，把返回的 refresh_token 粘贴到这里；'
                  '也可以从 OpenList 等工具导出。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _refreshToken,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'refresh_token',
                    hintText: '粘贴迅雷 refresh_token',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _pasteRefreshToken,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('从剪贴板粘贴'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _loginWithRefreshToken,
                    child: Text(_busy ? '登录中…' : '登录'),
                  ),
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
