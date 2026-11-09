import 'dart:async';
import 'dart:io';

/// 运行时 / 支持库下载的线路选择：先并发测速，再按实测速度从快到慢下载。
///
/// 之前每类下载只有一个（或少量）固定地址，GitHub / 镜像站一被网络挡住就整条
/// 安装失败。这里把「多个镜像 + GitHub 加速代理」统一成候选列表，测速后取最快
/// 的一条；失败时调用方继续试下一条。

const _userAgent = 'MisaTV/0.1';

/// 测速只读取开头这一小段，既能判断可用性也能测出带宽，不会白下整个文件。
const _probeBytes = 256 * 1024;

/// 单条线路最多测这么久（含慢速线路），避免测速本身拖住安装。
const _probeWindow = Duration(seconds: 5);

/// 并发测速候选线路，按实测速度降序返回**可用**地址。
///
/// 全部不可达时返回空列表，调用方回落到原始顺序（由它自己报最后一次错误）。
Future<List<String>> rankMirrors(Iterable<String> urls) async {
  final list = urls.toSet().toList();
  if (list.length <= 1) return list;
  final scores = await Future.wait(
    list.map((url) async => MapEntry(url, await probeSpeed(url))),
  );
  final reachable = scores.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return reachable.map((e) => e.key).toList();
}

/// 单个线路的实测速度（bytes/ms）；不可达 / 内容过小返回 0。
Future<double> probeSpeed(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..autoUncompress = false;
  final watch = Stopwatch();
  var bytes = 0;
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 9));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..set(HttpHeaders.acceptEncodingHeader, 'identity')
      // 只取开头一段；不支持 Range 的服务器会先回 200 再被我们主动掐断。
      ..set(HttpHeaders.rangeHeader, 'bytes=0-${_probeBytes - 1}');
    final response = await request.close().timeout(const Duration(seconds: 9));
    if (response.statusCode >= 400) {
      await response.drain<void>();
      return 0;
    }
    watch.start();
    await for (final chunk in response.timeout(_probeWindow)) {
      bytes += chunk.length;
      if (bytes >= _probeBytes || watch.elapsed >= _probeWindow) break;
    }
    watch.stop();
    if (bytes < 32 * 1024) return 0;
    final ms = watch.elapsedMicroseconds / 1000.0;
    return bytes / (ms <= 0 ? 1 : ms);
  } catch (_) {
    return 0;
  } finally {
    client.close(force: true);
  }
}
