import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/net/download_mirrors.dart';
import '../../core/platform/archive_extract.dart';

class PyRuntimeProgress {
  const PyRuntimeProgress(this.message, {this.value});
  final String message;
  final double? value;
}

/// 按需安装的嵌入式 Python 运行时（Windows 版 TVBox .py 蜘蛛依赖）。
///
/// 不做 pip：直接下载 python-3.11.6-embed-amd64.zip，并把 requests 等
/// wheel 解压进 `Lib/site-packages`（embed 包 _pth 隔离由 runner.py 手动注入 sys.path）。
class PyRuntime {
  PyRuntime._();
  static final instance = PyRuntime._();

  static const version = '3.11.6';

  /// runner.py / base/spider.py 的资源版本：升级后强制重写旧运行时里的这两个文件。
  static const assetsVersion = 8;
  static const _embedUrls = <String>[
    'https://mirrors.huaweicloud.com/python/$version/python-$version-embed-amd64.zip',
    'https://mirrors.aliyun.com/python-release/windows/python-$version-embed-amd64.zip',
    'https://registry.npmmirror.com/-/binary/python/$version/python-$version-embed-amd64.zip',
    'https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip',
    'https://mirrors.tuna.tsinghua.edu.cn/python/$version/python-$version-embed-amd64.zip',
  ];
  static const _simpleBases = <String>[
    'https://mirrors.aliyun.com/pypi/simple/',
    'https://mirrors.huaweicloud.com/repository/pypi/simple/',
    'https://mirrors.cloud.tencent.com/pypi/simple/',
    'https://pypi.tuna.tsinghua.edu.cn/simple/',
  ];

  /// 项目名 / 导入名 / 平台标签 / 是否必需
  static const _wheels = <_WheelSpec>[
    _WheelSpec('requests', 'requests', ['py3-none-any'], true),
    _WheelSpec('urllib3', 'urllib3', [
      'py3-none-any',
      'py2.py3-none-any',
    ], true),
    _WheelSpec('certifi', 'certifi', ['py3-none-any'], true),
    _WheelSpec('charset_normalizer', 'charset_normalizer', [
      'py3-none-any',
    ], true),
    _WheelSpec('idna', 'idna', ['py3-none-any'], true),
    _WheelSpec('lxml', 'lxml', ['cp311-cp311-win_amd64'], false),
    _WheelSpec('beautifulsoup4', 'bs4', ['py3-none-any'], false),
    _WheelSpec('soupsieve', 'soupsieve', ['py3-none-any'], false),
    _WheelSpec('pycryptodome', 'Crypto', [
      'cp311-cp311-win_amd64',
      'cp35-abi3-win_amd64',
    ], false),
    _WheelSpec('pyquery', 'pyquery', ['py3-none-any'], false),
    _WheelSpec('cssselect', 'cssselect', [
      'py3-none-any',
      'py2.py3-none-any',
    ], false),
    _WheelSpec('chardet', 'chardet', ['py3-none-any'], false),
    _WheelSpec('requests-toolbelt', 'requests_toolbelt', [
      'py3-none-any',
    ], false),
    _WheelSpec('typing_extensions', 'typing_extensions', [
      'py3-none-any',
    ], false),
    // 央視頻等新版蜘蛛用 net.ws() 换 WS 节点。
    _WheelSpec('websocket-client', 'websocket', [
      'py3-none-any',
      'py2.py3-none-any',
    ], false),
    // 央視頻的播放签名 keygen_bg.wasm：必须用 1.x 之前的 execution API，
    // 且 1.0.0 起会额外拖入 numpy，因此锁在无依赖的 0.4.8。
    _WheelSpec(
      'pywasm',
      'pywasm',
      ['py2.py3-none-any', 'py3-none-any'],
      false,
      '0.4.8',
    ),
  ];

  final ValueNotifier<PyRuntimeProgress?> progress = ValueNotifier(null);
  Future<Directory>? _installing;
  Directory? _cachedDir;
  bool? _cachedInstalled;

  Future<Directory> _dir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'python', version));
    _cachedDir = dir;
    return dir;
  }

  /// 已确认安装后取运行时目录（不触发安装；供每次调用复用）。
  Future<Directory> directory() => _dir();

  /// 是否正在下载 / 安装（源调用据此避免重复弹窗）。
  bool get installing => _installing != null;

  Future<bool> installed() async {
    final cached = _cachedInstalled;
    if (cached != null) return cached;
    final dir = await _dir();
    final ok =
        File(p.join(dir.path, 'python.exe')).existsSync() &&
        File(p.join(dir.path, 'runner.py')).existsSync() &&
        Directory(p.join(dir.path, 'Lib', 'site-packages', 'requests'))
            .existsSync();
    _cachedInstalled = ok;
    return ok;
  }

  /// runner / 基类资源是否是当前版本（老版本安装的运行时需要原地升级）。
  Future<bool> assetsCurrent() async {
    final dir = await _dir();
    return File(p.join(dir.path, 'base', '.kniephos-assets-v$assetsVersion'))
        .existsSync();
  }

  /// 已安装运行时的原地补齐：重写 runner.py / base/spider.py 并补装新增依赖。
  ///
  /// 只在资源版本变化时执行一次；旧版运行时缺少 `self.net`、`typing_extensions`
  /// 时，这些源会在升级后第一次调用时自动修好，不需要用户重新安装。
  Future<void> ensurePatched() async {
    final dir = await _dir();
    if (!File(p.join(dir.path, 'python.exe')).existsSync()) return;
    if (await assetsCurrent()) return;
    await ensureInstalled();
  }

  String? get installPath => _cachedDir?.path;

  /// 安装/补齐运行时；并发调用共享同一个任务。
  Future<Directory> ensureInstalled({bool force = false}) {
    if (force) {
      _cachedInstalled = null;
      _installing = null;
    }
    final running = _installing;
    if (running != null) return running;
    final task = _install();
    _installing = task;
    return task.whenComplete(() {
      _installing = null;
    });
  }

  Future<void> remove() async {
    final dir = await _dir();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 删除失败（文件被占用）时保留原状，下次启动可重试
    }
    _cachedInstalled = null;
  }

  Future<Directory> _install() async {
    final dir = await _dir();
    final pythonExe = File(p.join(dir.path, 'python.exe'));
    dir.createSync(recursive: true);
    final http = HttpClient();
    http.connectionTimeout = const Duration(seconds: 20);
    try {
      if (!pythonExe.existsSync()) {
        await _installEmbed(dir, http);
      }
      _setProgress('安装依赖库…', 0.65);
      await _installWheels(dir, http);
      _setProgress('写入运行器…', 0.98);
      await _writeRunner(dir);
      _cachedInstalled = null;
      if (!await installed()) {
        throw StateError('Python 运行时安装不完整（缺少 python.exe / requests）');
      }
      _setProgress('Python 运行时已就绪', 1);
      return dir;
    } finally {
      http.close(force: true);
      Future<void>.delayed(const Duration(seconds: 4), () {
        progress.value = null;
      });
    }
  }

  Future<void> _installEmbed(Directory dir, HttpClient http) async {
    var lastError = '';
    final urls = await _ranked(_embedUrls, '测速选择最快的 Python 下载线路…', 0);
    for (final url in urls) {
      final tmp = File(
        p.join(
          dir.parent.path,
          'python-embed-${DateTime.now().millisecondsSinceEpoch}.zip',
        ),
      );
      try {
        _setProgress('下载 Python 运行时（约 11 MB）…', 0);
        await _download(
          http,
          url,
          tmp,
          (v) => _setProgress('下载 Python 运行时（约 11 MB）…', v * 0.55),
        );
        final size = tmp.lengthSync();
        if (size < 1024 * 1024) throw StateError('下载内容过小（$size 字节）');
        _setProgress('解压 Python 运行时…', 0.58);
        try {
          await extractZipArchive(tmp.path, dir.path);
        } catch (e) {
          throw StateError('解压失败：$e');
        }
        if (!File(p.join(dir.path, 'python.exe')).existsSync()) {
          throw StateError('解压后未找到 python.exe');
        }
        return;
      } catch (e) {
        lastError = '$e';
      } finally {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {
          // 临时文件清理失败忽略
        }
      }
    }
    throw StateError('Python 运行时下载失败：$lastError');
  }

  Future<void> _installWheels(Directory dir, HttpClient http) async {
    final sitePackages = Directory(p.join(dir.path, 'Lib', 'site-packages'));
    sitePackages.createSync(recursive: true);
    final marker = File(p.join(sitePackages.path, '.kniephos-libs-v2'));
    if (!marker.existsSync()) {
      // 没有标记视为不完整/来源不明 → 清空重装（自愈旧版本装错 wheel 的目录）
      try {
        if (sitePackages.existsSync()) sitePackages.deleteSync(recursive: true);
      } catch (_) {
        // 删除失败则尽量覆盖安装
      }
      sitePackages.createSync(recursive: true);
    }
    final temp = Directory(p.join(dir.path, '.wheel-tmp'));
    if (temp.existsSync()) temp.deleteSync(recursive: true);
    temp.createSync(recursive: true);
    try {
      final bases = await _rankedBases();
      var index = 0;
      for (final wheel in _wheels) {
        index++;
        if (marker.existsSync() && _wheelInstalled(sitePackages, wheel)) {
          continue;
        }
        _setProgress(
          '安装依赖 ${wheel.project}（$index/${_wheels.length}）…',
          0.65 + 0.3 * index / _wheels.length,
        );
        try {
          final url = await _resolveWheel(http, wheel, bases);
          if (url == null) throw StateError('镜像中未找到匹配的 wheel');
          final file = File(p.join(temp.path, '${wheel.project}.whl'));
          await _download(http, url, file, null);
          try {
            if (wheel.version.isNotEmpty) {
              // 锁定版本时先清掉同名旧版本（例如 pywasm 2.x 的残留文件）。
              final old = Directory(
                p.join(sitePackages.path, wheel.importName),
              );
              if (old.existsSync()) old.deleteSync(recursive: true);
            }
            await extractZipArchive(file.path, sitePackages.path);
            if (wheel.version.isNotEmpty) {
              File(_wheelMarker(sitePackages, wheel))
                  .writeAsStringSync(DateTime.now().toIso8601String());
            }
          } catch (e) {
            throw StateError('解压失败：$e');
          }
        } catch (e) {
          if (wheel.required) rethrow;
          // 可选依赖失败不影响纯 Python 源
        }
      }
      marker.writeAsStringSync(DateTime.now().toIso8601String());
    } finally {
      try {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      } catch (_) {
        // ignore
      }
    }
  }

  /// 锁版本的 wheel 用标记文件判断（同名目录可能是其它版本）。
  bool _wheelInstalled(Directory sitePackages, _WheelSpec wheel) {
    if (wheel.version.isNotEmpty) {
      return File(_wheelMarker(sitePackages, wheel)).existsSync();
    }
    // 单文件模块（如 typing_extensions.py）装出来不是目录，
    // 只查目录会让它每次启动都被判为缺失、重复联网安装。
    final base = p.join(sitePackages.path, wheel.importName);
    return Directory(base).existsSync() || File('$base.py').existsSync();
  }

  String _wheelMarker(Directory sitePackages, _WheelSpec wheel) => p.join(
    sitePackages.path,
    '.kniephos-wheel-${wheel.project}-${wheel.version}',
  );

  Future<String?> _resolveWheel(
    HttpClient http,
    _WheelSpec wheel,
    List<String> bases,
  ) async {
    for (final base in bases) {
      try {
        final uri = Uri.parse('$base${wheel.project}/');
        final req = await http.getUrl(uri);
        req.headers.set('User-Agent', 'kniephos/0.1');
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final html = await utf8.decoder.bind(res).join();
        final hrefs = RegExp(r'href="([^"]+\.whl[^"]*)"')
            .allMatches(html)
            .map((m) => m.group(1)!.replaceAll('&amp;', '&'))
            .toList();
        for (final tag in wheel.tags) {
          final candidates = <String>[];
          for (final href in hrefs) {
            if (!href.contains(tag)) continue;
            if (href.contains('macosx') ||
                href.contains('manylinux') ||
                href.contains('musllinux')) {
              continue;
            }
            if (wheel.version.isNotEmpty &&
                _wheelVersion(href) != wheel.version) {
              continue;
            }
            candidates.add(href);
          }
          if (candidates.isEmpty) continue;
          candidates.sort(
            (a, b) => _compareVersion(_wheelVersion(a), _wheelVersion(b)),
          );
          final stable = candidates
              .where((h) => !_isPrerelease(_wheelVersion(h)))
              .toList();
          final pick = (stable.isNotEmpty ? stable : candidates).last;
          return uri.resolve(pick).toString();
        }
      } catch (_) {
        // 尝试下一个镜像
      }
    }
    return null;
  }

  /// wheel 文件名第二段就是版本号（`requests-2.32.3-py3-none-any.whl`）。
  String _wheelVersion(String href) {
    final file = href.split('/').last.split('#').first;
    final parts = file.split('-');
    return parts.length > 1 ? parts[1] : '0';
  }

  bool _isPrerelease(String version) {
    final v = version.toLowerCase();
    return RegExp(r'(^|[0-9])(a|b|rc|dev)[0-9]').hasMatch(v);
  }

  int _compareVersion(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? _leadingInt(pa[i]) : 0;
      final y = i < pb.length ? _leadingInt(pb[i]) : 0;
      if (x != y) return x.compareTo(y);
    }
    return a.compareTo(b);
  }

  int _leadingInt(String part) {
    final m = RegExp(r'^\d+').firstMatch(part);
    return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
  }

  Future<void> _writeRunner(Directory dir) async {
    final runner = await rootBundle.loadString(
      'assets/python_runner/runner.py',
    );
    final spider = await rootBundle.loadString(
      'assets/python_runner/base/spider.py',
    );
    File(p.join(dir.path, 'runner.py')).writeAsStringSync(runner);
    final base = Directory(p.join(dir.path, 'base'));
    base.createSync(recursive: true);
    File(p.join(base.path, 'spider.py')).writeAsStringSync(spider);
    File(p.join(base.path, '__init__.py')).writeAsStringSync('');
    File(p.join(base.path, '.kniephos-assets-v$assetsVersion'))
        .writeAsStringSync(DateTime.now().toIso8601String());
  }

  /// 下载前并发测速：返回可用线路（快 → 慢）；全不通则保留原顺序逐个试。
  Future<List<String>> _ranked(
    List<String> urls,
    String message,
    double progress,
  ) async {
    _setProgress(message, progress);
    final ranked = await rankMirrors(urls);
    return ranked.isEmpty ? urls : ranked;
  }

  /// PyPI 镜像测速一次，所有 wheel 都按「快 → 慢」顺序查。
  Future<List<String>> _rankedBases() async {
    _setProgress('测速选择最快的 PyPI 镜像…', 0.64);
    final rel = '${_wheels.first.project}/';
    final ranked = await rankMirrors(
      _simpleBases.map((base) => '$base$rel').toList(),
    );
    if (ranked.isEmpty) return _simpleBases;
    return ranked
        .map((url) => url.substring(0, url.length - rel.length))
        .toList();
  }

  Future<void> _download(
    HttpClient http,
    String url,
    File target,
    ValueChanged<double>? onProgress,
  ) async {
    final req = await http.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'kniephos/0.1');
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw StateError('HTTP ${res.statusCode}：$url');
    }
    final total = res.contentLength;
    target.parent.createSync(recursive: true);
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress((received / total).clamp(0, 1));
        }
      }
    } finally {
      await sink.close();
    }
  }

  void _setProgress(String message, double value) {
    progress.value = PyRuntimeProgress(message, value: value.clamp(0, 1));
  }
}

class _WheelSpec {
  const _WheelSpec(
    this.project,
    this.importName,
    this.tags,
    this.required, [
    this.version = '',
  ]);
  final String project;
  final String importName;
  final List<String> tags;
  final bool required;

  /// 锁定版本（空 = 取镜像里最新稳定版）。
  final String version;
}
