import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/logging/app_log.dart';
import '../../core/logging/log_redact.dart';
import '../../core/net/app_http.dart';

const _defaultUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0';

/// 验证页把 jQuery 的 jqXHR 直接 return 给阿里云 SDK。SDK 内部会 `await`
/// 这个返回值，拿到的是 do_v2 的响应体；响应体只有 `captchaVerifyResult`，
/// 没有 SDK 要求的 `captchaResult`，所以滑块正确也会提示“网络不给力，请刷新重试”。
///
/// 这里不再让页面自己发跨域 AJAX（还依赖 jQuery 与同步 XHR），而是把
/// do_v2 的验证参数通过 `HymsVerify` 交给 Dart 原生请求；返回值换成
/// `await` 后得到 `{captchaResult: boolean}` 的 thenable，页面自己的 success
/// 回调仍然会通过 `SlideVerifyJsInterface` 把 session 传回 Dart。
const _installScript = r'''
(function () {
  console.log('[MisaTV] UA=' + navigator.userAgent);

  function ensureButton() {
    try {
      if (document.getElementById('button')) return;
      var root = document.body || document.documentElement;
      if (!root) return;
      var button = document.createElement('button');
      button.id = 'button';
      button.type = 'button';
      button.style.display = 'none';
      root.appendChild(button);
      console.log('[MisaTV] injected #button');
    } catch (e) {
      console.error('[MisaTV] inject #button failed: ' + e);
    }
  }

  // 验证页把 <button id="button"> 注释掉了，阿里云 SDK 找不到按钮时会
  // 立刻走 fallback，用空 certifyId 自动提交，表现为“怎么滑都失败”。
  // 这里直接重写 querySelector：SDK 来查 #button 时同步造一个隐藏按钮，
  // 保证它在 initAliyunCaptcha 里一定找得到。
  function installButtonSelector() {
    try {
      if (window.__hymsButtonSelector) return;
      window.__hymsButtonSelector = true;
      var original = document.querySelector.bind(document);
      document.querySelector = function (selector) {
        if (selector === '#button') {
          var existing = document.getElementById('button');
          if (existing) return existing;
          try {
            var button = document.createElement('button');
            button.id = 'button';
            button.type = 'button';
            button.style.display = 'none';
            (document.body || document.documentElement).appendChild(button);
            console.log('[MisaTV] injected #button (selector)');
            return button;
          } catch (e) {
            console.error('[MisaTV] inject #button failed: ' + e);
            return null;
          }
        }
        return original(selector);
      };
    } catch (e) {
      console.error('[MisaTV] install #button selector failed: ' + e);
    }
  }

  function logNet(url, status, body) {
    try {
      var u = String(url || '');
      if (!/captcha-open|aliyuncs|cloudauth|alicdn/i.test(u)) return;
      console.log('[MisaTV] net ' + status + ' ' + u.split('?')[0] +
        ' body=' + String(body || '').slice(0, 400));
    } catch (e) {}
  }

  // 阿里云验证码初始化失败时只会静默回退到空 certifyId；这里把
  // 初始化请求的状态与响应体记下来，便于定位场景过期/风控/网络问题。
  function installNetLogger() {
    try {
      if (window.__hymsNetLogger) return;
      window.__hymsNetLogger = true;
      var origFetch = window.fetch;
      if (typeof origFetch === 'function') {
        window.fetch = function (input, init) {
          var url = typeof input === 'string' ? input : (input && input.url) || '';
          return origFetch.apply(this, arguments).then(function (res) {
            try {
              res.clone().text().then(function (text) {
                logNet(url, res.status, text);
              });
            } catch (e) {}
            return res;
          });
        };
      }
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__hymsUrl = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function (body) {
        var xhr = this;
        xhr.addEventListener('load', function () {
          logNet(xhr.__hymsUrl, xhr.status, xhr.responseText);
        });
        xhr.addEventListener('error', function () {
          logNet(xhr.__hymsUrl, 0, 'network error');
        });
        return origSend.apply(this, arguments);
      };
      console.log('[MisaTV] net logger installed');
    } catch (e) {
      console.error('[MisaTV] net logger failed: ' + e);
    }
  }

  // 阿里云验证码默认约 10 秒就自动走 fallback；用户还没滑完就被重置。
  // 在外部 SDK 给 window.initAliyunCaptcha 赋值时包一层，延长超时并关闭自动刷新。
  function installInitConfigPatch() {
    try {
      if (window.__hymsInitPatched) return;
      window.__hymsInitPatched = true;
      var wrapped = null;
      Object.defineProperty(window, 'initAliyunCaptcha', {
        configurable: true,
        enumerable: true,
        get: function () { return wrapped; },
        set: function (fn) {
          if (typeof fn !== 'function') {
            wrapped = fn;
            return;
          }
          wrapped = function (config) {
            try {
              config = config || {};
              config.timeout = 60000;
              config.autoRefresh = true;
              console.log('[MisaTV] captcha timeout=60000 autoRefresh=true');
            } catch (e) {}
            return fn(config);
          };
        }
      });
      console.log('[MisaTV] initAliyunCaptcha patch armed');
    } catch (e) {
      console.error('[MisaTV] init patch failed: ' + e);
    }
  }

  var fallbackGuard = function (e) {
    if (e && e.preventDefault) e.preventDefault();
    console.log('[MisaTV] captcha fallback blocked');
  };

  function guardFallback() {
    try {
      var button = document.getElementById('button');
      if (button && button.onclick !== fallbackGuard) {
        button.onclick = fallbackGuard;
      }
    } catch (e) {}
  }

  function send(data) {
    try {
      var raw = typeof data === 'string' ? data : JSON.stringify(data);
      window.flutter_inappwebview.callHandler('SlideVerifyJsInterface', raw);
    } catch (e) {
      console.error('[MisaTV] captcha bridge error: ' + e);
    }
  }

  function nativeVerify(data) {
    try {
      return window.flutter_inappwebview.callHandler(
        'HymsVerify', JSON.stringify(data || {}));
    } catch (e) {
      return Promise.reject(e);
    }
  }

  function deviceToken() {
    try {
      var um = window.z_um || window.um;
      if (!um || typeof um.getToken !== 'function') return '';
      var token = um.getToken();
      return typeof token === 'string' ? token : '';
    } catch (e) {
      return '';
    }
  }

  function deviceState() {
    try {
      var um = window.z_um || window.um;
      if (!um) return 'none';
      if (typeof um.getToken !== 'function') return 'no-getToken';
      return 'len=' + String(um.getToken() || '').length;
    } catch (e) {
      return 'err';
    }
  }

  // 阿里云设备指纹是异步初始化的；滑块回调触发过早时
  // captchaVerifyParam 里没有 deviceToken，服务端必然判失败。
  function withDeviceToken(data) {
    if (data && data.deviceToken) return Promise.resolve(data);
    return new Promise(function (resolve) {
      var tries = 0;
      var timer = setInterval(function () {
        var token = deviceToken();
        if (token) {
          clearInterval(timer);
          data = data || {};
          data.deviceToken = token;
          console.log('[MisaTV] 补齐 deviceToken len=' + token.length);
          resolve(data);
        } else if (++tries >= 20) {
          clearInterval(timer);
          console.log('[MisaTV] deviceToken 仍为空 device=' + deviceState());
          resolve(data);
        }
      }, 500);
    });
  }

  function resultFor(ok) {
    var result = { captchaResult: ok, bizResult: true };
    return {
      captchaResult: ok,
      bizResult: true,
      then: function (resolve, reject) {
        return Promise.resolve(result).then(resolve, reject);
      },
      catch: function (reject) {
        return Promise.resolve(result).catch(reject);
      },
      finally: function (fn) {
        return Promise.resolve(result).finally(fn);
      }
    };
  }

  function isDoV2(opts) {
    return !!opts && typeof opts.url === 'string' &&
      opts.url.indexOf('/api/check/do_v2') >= 0;
  }

  function handleDoV2(opts) {
    var data = opts.data;
    if (typeof data === 'string') {
      try { data = JSON.parse(data); } catch (e) {}
    }
    var promise = withDeviceToken(data).then(function (payload) {
      try {
        var dataText = '';
        try {
          dataText = typeof (payload && payload.data) === 'string'
            ? payload.data
            : JSON.stringify((payload && payload.data) || '');
        } catch (e) {}
        console.log('[MisaTV] verify param keys=' + Object.keys(payload || {}).join(',') +
          ' scene=' + String((payload && payload.sceneId) || '') +
          ' certifyLen=' + String((payload && payload.certifyId) || '').length +
          ' deviceLen=' + String((payload && payload.deviceToken) || '').length +
          ' dataLen=' + String(dataText).length +
          ' data=' + String(dataText).slice(0, 80) +
          ' err=' + String((payload && payload.err) || ''));
      } catch (e) {}
      return nativeVerify(payload);
    }).then(function (ok) {
      ok = !!ok;
      console.log('[MisaTV] native do_v2 captchaResult=' + ok);
      if (opts && typeof opts.success === 'function') {
        try {
          opts.success({ captchaVerifyResult: ok });
        } catch (e) {
          console.error('[MisaTV] success callback error: ' + e);
        }
      }
      if (opts && typeof opts.complete === 'function') {
        try { opts.complete(); } catch (e) {}
      }
      return ok;
    }).catch(function (e) {
      console.error('[MisaTV] native verify failed: ' + e);
      return false;
    });
    return {
      then: function (resolve, reject) {
        promise.then(function (ok) { resolve(resultFor(ok)); }, reject);
      },
      catch: function (reject) {
        promise.catch(reject);
      },
      finally: function (fn) {
        promise.finally(fn);
      }
    };
  }

  function stubElement() {
    return {
      hide: function () { return this; },
      show: function () { return this; },
      css: function () { return this; },
      html: function () { return this; },
      on: function () { return this; }
    };
  }

  function installStub() {
    if (window.$ && window.$.__hymsNativeStub) return;
    if (window.jQuery) return;
    var stub = function () { return stubElement(); };
    stub.__hymsNativeStub = true;
    stub.ajax = function (opts) {
      if (isDoV2(opts)) return handleDoV2(opts);
      return { status: 0, responseJSON: null };
    };
    window.$ = stub;
    window.jQuery = stub;
    console.log('[MisaTV] jQuery 未加载，使用 native stub');
  }

  function patchJquery() {
    var jq = window.jQuery;
    if (!jq || typeof jq.ajax !== 'function' || jq.__hymsNativeStub) return;
    if (jq.ajax.__hymsPatched) return;
    var original = jq.ajax;
    function wrapped(opts) {
      if (isDoV2(opts)) return handleDoV2(opts);
      return original.apply(this, arguments);
    }
    wrapped.__hymsPatched = true;
    jq.ajax = wrapped;
    console.log('[MisaTV] jQuery ajax patched (native verify)');
  }

  var deviceLogged = false;

  function tick() {
    ensureButton();
    guardFallback();
    patchJquery();
    installStub();
    if (!deviceLogged && (window.z_um || window.um)) {
      deviceLogged = true;
      console.log('[MisaTV] device ready ' + deviceState());
    }
  }

  window.__hymsInstall = function () {
    window.SlideVerifyJsInterface = { getSlideVerifyData: send };
    installInitConfigPatch();
    installButtonSelector();
    installNetLogger();
    tick();
    if (!window.__hymsDeviceTimer) {
      window.__hymsDeviceTimer = setTimeout(function () {
        console.log('[MisaTV] device@12s ' + deviceState());
      }, 12000);
    }
    if (window.__hymsTimer) return;
    var tries = 0;
    window.__hymsTimer = setInterval(function () {
      tick();
      if (++tries > 600) {
        clearInterval(window.__hymsTimer);
        window.__hymsTimer = 0;
      }
    }, 50);
  };
  window.__hymsInstall();
})();
''';

/// 海绵源的阿里云滑块验证页。
///
/// 页面校验通过后会调用 `window.SlideVerifyJsInterface.getSlideVerifyData(...)`，
/// 这里接住 `session_id / sig / nc_token`，连同 WebView 里的 Cookie 一起返回，
/// 由 HymsNative 重新调 collection 换真实 m3u8。
Future<Map<String, String>?> showHymsCaptchaDialog(
  BuildContext context,
  String url,
) {
  return showGeneralDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '海绵源验证',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => _HymsCaptchaDialog(url: url),
    transitionBuilder: (ctx, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _HymsCaptchaDialog extends StatefulWidget {
  const _HymsCaptchaDialog({required this.url});

  final String url;

  @override
  State<_HymsCaptchaDialog> createState() => _HymsCaptchaDialogState();
}

class _HymsCaptchaDialogState extends State<_HymsCaptchaDialog> {
  bool _done = false;
  final AppHttp _verifyHttp = AppHttp();
  String _nativeCookie = '';

  /// 使用 WebView2 自己的 UA（桌面浏览器），不要伪装成 Android。
  /// 阿里云验证码会把“桌面浏览器模拟移动设备”识别为虚拟环境（F009）
  /// 直接判验证失败，滑块怎么滑都过不了。
  String _pageUa = _defaultUa;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final navigator = Navigator.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: (size.width * 0.92).clamp(420, 760),
          height: (size.height * 0.94).clamp(600, 900),
          decoration: BoxDecoration(
            color: const Color(0xFF121715),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('海绵源需要验证')),
                    IconButton(
                      onPressed: () => navigator.pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '按住滑块拖动，直到图片完全拼合；失败时点右上角刷新图标换一张再试。',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: _installScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    transparentBackground: true,
                    supportZoom: true,
                    thirdPartyCookiesEnabled: true,
                    sharedCookiesEnabled: true,
                  ),
                  onWebViewCreated: (controller) {
                    controller.addJavaScriptHandler(
                      handlerName: 'HymsVerify',
                      callback: (args) async {
                        final raw = args.isEmpty ? '' : '${args.first}'.trim();
                        return _verify(raw);
                      },
                    );
                    controller.addJavaScriptHandler(
                      handlerName: 'SlideVerifyJsInterface',
                      callback: (args) async {
                        if (_done) return null;
                        final raw = args.isEmpty ? '' : '${args.first}'.trim();
                        final session = _parseSession(raw);
                        if (session == null) {
                          AppLog.w('hyms', '验证页回传参数无法解析 ${shorten(raw, 120)}');
                          return null;
                        }
                        final cookies = await _cookies();
                        final merged = [
                          cookies,
                          _nativeCookie,
                        ].where((e) => e.trim().isNotEmpty).join('; ');
                        if (merged.isNotEmpty) session['cookie'] = merged;
                        AppLog.i('hyms', '滑块验证完成 cookie=${merged.isNotEmpty}');
                        _done = true;
                        if (navigator.mounted) navigator.pop(session);
                        return null;
                      },
                    );
                  },
                  // Windows 插件 0.6.0 的权限回调不判空，Dart 返回 null 会闪退。
                  onPermissionRequest: (controller, request) async =>
                      PermissionResponse(action: PermissionResponseAction.DENY),
                  onConsoleMessage: (controller, message) {
                    final text = message.message.trim();
                    if (text.isEmpty) return;
                    final lower = text.toLowerCase();
                    if (text.contains('[MisaTV]') ||
                        text.contains('错误') ||
                        text.contains('失败') ||
                        lower.contains('error') ||
                        lower.contains('fail')) {
                      AppLog.i('hyms', '验证页 ${shorten(text, 280)}');
                    }
                  },
                  onLoadStop: (controller, url) async {
                    // initialUserScripts 在旧版本 Windows WebView 上可能不生效，
                    // 页面加载后补注入一次；jQuery 尚未加载时脚本会自行轮询。
                    await controller.evaluateJavascript(
                      source:
                          '''
(function () {
  if (window.__hymsInstall) { window.__hymsInstall(); return; }
  $_installScript
})();
''',
                    );
                    try {
                      final actual = await controller.evaluateJavascript(
                        source: 'navigator.userAgent',
                      );
                      if (actual is String && actual.trim().isNotEmpty) {
                        _pageUa = actual.trim();
                        AppLog.i('hyms', '验证页 UA ${shorten(_pageUa, 160)}');
                      }
                    } catch (_) {
                      // 读不到 UA 时使用默认桌面 UA
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, String>? _parseSession(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final sessionId = '${decoded['session_id'] ?? ''}'.trim();
      final sig = '${decoded['sig'] ?? ''}'.trim();
      final ncToken = '${decoded['nc_token'] ?? ''}'.trim();
      if (sig.isEmpty || ncToken.isEmpty) return null;
      return {'session_id': sessionId, 'sig': sig, 'nc_token': ncToken};
    } catch (_) {
      return null;
    }
  }

  /// 用 Dart 原生请求调 do_v2，绕开验证页对 jQuery / 同步跨域 XHR 的依赖。
  ///
  /// 返回值会经 JS 桥传回验证页，再交给阿里云 SDK。
  Future<bool> _verify(String raw) async {
    if (raw.isEmpty) return false;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      AppLog.w('hyms', '验证参数不是 JSON ${shorten(raw, 120)}');
      return false;
    }
    final body = <String, String>{};
    for (final entry in data.entries) {
      _addField(body, entry.key, entry.value);
    }
    final err = '${data['err'] ?? ''}'.trim();
    final certifyId = '${data['certifyId'] ?? ''}';
    final deviceToken = '${data['deviceToken'] ?? ''}';
    final sceneId = '${data['sceneId'] ?? ''}';
    AppLog.i(
      'hyms',
      'do_v2 参数 keys=${data.keys.join(',')} scene=$sceneId '
          'certifyLen=${certifyId.length} deviceLen=${deviceToken.length} '
          'err=${shorten(err, 120)}',
    );
    final uri = Uri.tryParse(widget.url);
    final origin = uri == null ? '' : '${uri.scheme}://${uri.host}';
    final referer = origin.isEmpty ? widget.url : '$origin/';
    for (final host in const [
      'https://u.gslock.com',
      'https://u.yyxdmn.com',
      'https://u.jsyysm.com',
    ]) {
      try {
        final res = await _verifyHttp.postForm(
          '$host/api/check/do_v2',
          body: body,
          headers: {
            if (origin.isNotEmpty) 'Origin': origin,
            'Referer': referer,
            'User-Agent': _pageUa,
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Sec-Fetch-Site': 'cross-site',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Dest': 'empty',
          },
          timeout: const Duration(seconds: 15),
        );
        final cookie = _verifyHttp.cookiesFor(host);
        if (cookie.isNotEmpty) _nativeCookie = cookie;
        final json = jsonDecode(res.body);
        final ok = json is Map && json['captchaVerifyResult'] == true;
        AppLog.i(
          'hyms',
          '原生 do_v2 ${Uri.parse(host).host} ok=$ok '
              'body=${shorten(res.body, 200)}',
        );
        return ok;
      } catch (e) {
        AppLog.w(
          'hyms',
          '原生 do_v2 ${Uri.parse(host).host} 失败 '
              '${shorten(e.toString(), 140)}',
        );
      }
    }
    return false;
  }

  /// 与 jQuery `$.param` 保持一致的扁平化：嵌套对象用 `a[b]`，数组用 `a[]`。
  void _addField(Map<String, String> body, String key, dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        _addField(body, '$key[${entry.key}]', entry.value);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _addField(body, '$key[]', item);
      }
      return;
    }
    body[key] = value == null ? '' : '$value';
  }

  Future<String> _cookies() async {
    final manager = CookieManager.instance();
    final values = <String>{};
    for (final uri in [
      WebUri(widget.url),
      WebUri('https://u.gslock.com/'),
      WebUri('https://u.yyxdmn.com/'),
      WebUri('https://u.jsyysm.com/'),
    ]) {
      try {
        for (final cookie in await manager.getCookies(url: uri)) {
          if (cookie.name.isNotEmpty) {
            values.add('${cookie.name}=${cookie.value}');
          }
        }
      } catch (_) {
        // WebView 还没写入该域 Cookie 时忽略
      }
    }
    return values.join('; ');
  }
}
