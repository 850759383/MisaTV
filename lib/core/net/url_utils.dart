/// 把 URL 里的中文 / Unicode 域名转成 punycode（`影视仓.com` → `xn--5mqx81b535a.com`）。
///
/// Dart 的 `Uri.parse` 不接受非 ASCII 主机名，直接请求会报
/// “not a valid link-local address”；而 TVBox / okhttp 会自动做 IDNA 转换，
/// 所以订阅里常见的中文域名必须在这里先归一化。
String normalizeHostUrl(String url) {
  final text = url.trim();
  if (text.isEmpty) return text;
  final match = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*://)([^/?#]*)(.*)$')
      .firstMatch(text);
  if (match == null) return text;
  final scheme = match.group(1)!;
  final authority = match.group(2)!;
  final rest = match.group(3)!;
  var userInfo = '';
  var hostPort = authority;
  final at = authority.lastIndexOf('@');
  if (at >= 0) {
    userInfo = authority.substring(0, at + 1);
    hostPort = authority.substring(at + 1);
  }
  if (hostPort.isEmpty || hostPort.startsWith('[')) return text;

  var host = hostPort;
  var port = '';
  final colon = hostPort.lastIndexOf(':');
  if (colon >= 0 && int.tryParse(hostPort.substring(colon + 1)) != null) {
    host = hostPort.substring(0, colon);
    port = hostPort.substring(colon);
  }
  if (host.contains('%')) {
    try {
      host = Uri.decodeComponent(host);
    } catch (_) {
      // 保留原文，交给下面的 ASCII 判断
    }
  }
  final ascii = host.runes.every((r) => r < 0x80);
  if (ascii) return text;

  final hostLabels = host
      .split('.')
      .map((label) {
        if (label.runes.every((r) => r < 0x80)) return label;
        return 'xn--${_punycode(label)}';
      })
      .join('.');
  return '$scheme$userInfo$hostLabels$port$rest';
}

/// Referer 用的站根：`https://a.b/c/d.json?x=1` → `https://a.b/`。
String siteRootOf(String url) {
  final uri = Uri.tryParse(normalizeHostUrl(url));
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return '';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port/';
}

/// GitHub raw / blob 地址在国内网络常被阻断，返回可用的 jsDelivr 镜像候选。
///
/// 支持：
///   `raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>`
///   `raw.githubusercontent.com/<owner>/<repo>/refs/heads/<ref>/<path>`
///   `github.com/<owner>/<repo>/(raw|blob)/<ref>/<path>`
/// 非 GitHub 地址返回空列表。
List<String> githubMirrorUrls(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return const [];
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments;
  var owner = '';
  var repo = '';
  var ref = '';
  var rest = <String>[];
  if (host == 'raw.githubusercontent.com') {
    if (segs.length < 4) return const [];
    owner = segs[0];
    repo = segs[1];
    if (segs.length >= 6 &&
        segs[2] == 'refs' &&
        (segs[3] == 'heads' || segs[3] == 'tags')) {
      ref = segs[4];
      rest = segs.sublist(5);
    } else {
      ref = segs[2];
      rest = segs.sublist(3);
    }
  } else if (host == 'github.com' || host == 'www.github.com') {
    if (segs.length < 5) return const [];
    final kind = segs[2];
    if (kind != 'raw' && kind != 'blob') return const [];
    owner = segs[0];
    repo = segs[1];
    if (segs.length >= 7 &&
        segs[3] == 'refs' &&
        (segs[4] == 'heads' || segs[4] == 'tags')) {
      ref = segs[5];
      rest = segs.sublist(6);
    } else {
      ref = segs[3];
      rest = segs.sublist(4);
    }
  } else {
    return const [];
  }
  if (owner.isEmpty || repo.isEmpty || ref.isEmpty || rest.isEmpty) {
    return const [];
  }
  final encodedRef = Uri.encodeComponent(ref);
  final path = rest.join('/');
  return [
    'https://cdn.jsdelivr.net/gh/$owner/$repo@$encodedRef/$path',
    'https://fastly.jsdelivr.net/gh/$owner/$repo@$encodedRef/$path',
  ];
}

/// 同路径换协议（http ↔ https），部分镜像只通一边。
String protocolAltUrl(String url) {
  final uri = Uri.tryParse(normalizeHostUrl(url));
  if (uri == null) return '';
  if (uri.scheme == 'http') return uri.replace(scheme: 'https').toString();
  if (uri.scheme == 'https') return uri.replace(scheme: 'http').toString();
  return '';
}

/// RFC 3492 punycode（单段 label），与浏览器 / okhttp 的 IDNA 结果一致。
String _punycode(String label) {
  const base = 36;
  const tMin = 1;
  const tMax = 26;
  const initialBias = 72;
  const initialN = 128;
  final input = label.runes.toList();
  final out = StringBuffer();
  final basic = input.where((c) => c < 0x80).toList();
  for (final c in basic) {
    out.writeCharCode(c);
  }
  var h = basic.length;
  final b = h;
  if (b > 0) out.write('-');
  var n = initialN;
  var delta = 0;
  var bias = initialBias;
  while (h < input.length) {
    var m = 0x7FFFFFFF;
    for (final c in input) {
      if (c >= n && c < m) m = c;
    }
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in input) {
      if (c < n) {
        delta++;
      } else if (c == n) {
        var q = delta;
        for (var k = base; ; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          out.writeCharCode(_digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        out.writeCharCode(_digit(q));
        bias = _adapt(delta, h + 1, h == b);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}

int _adapt(int delta, int numPoints, bool firstTime) {
  const base = 36;
  const tMin = 1;
  const tMax = 26;
  const skew = 38;
  const damp = 700;
  delta = firstTime ? delta ~/ damp : delta ~/ 2;
  delta += delta ~/ numPoints;
  var k = 0;
  while (delta > ((base - tMin) * tMax) ~/ 2) {
    delta ~/= base - tMin;
    k += base;
  }
  return k + (((base - tMin + 1) * delta) ~/ (delta + skew));
}

int _digit(int d) => d < 26 ? 0x61 + d : 0x30 + d - 26;
