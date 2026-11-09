/// 注入 QuickJS 的宿主 API（与 TVBox 安卓沙箱语义对齐的常用子集）。
///
/// 这里只放「与宿主交互」和「海阔规则 DSL」的纯 JS 实现；第三方库
/// （cheerio / crypto-js / cat.js / gbk.js / 模板.js …）由 Dart 侧从
/// `assets/js_lib` 提供源码，JS 里按需 require。
const String spiderJsBootstrap = r'''
(function () {
  var G = globalThis;

  function __callNative(name, payload) {
    try {
      var r = sendMessage(name, JSON.stringify(payload || {}));
      return r == null ? '' : String(r);
    } catch (e) {
      return '';
    }
  }
  function __json(text, def) {
    if (text == null) return def;
    try { return JSON.parse(String(text)); } catch (e) { return def; }
  }
  function __errText(e) {
    try {
      var msg = String((e && e.message) || e);
      var stack = e && e.stack ? String(e.stack) : '';
      if (stack) {
        var lines = stack.split('\n');
        for (var i = 0; i < lines.length && i < 6; i++) {
          var line = lines[i];
          if (line && line !== msg && msg.indexOf(line) < 0) msg += '\n' + line;
        }
      }
      return msg;
    } catch (_) {
      return 'unknown error';
    }
  }

  // ---------------- 网络 ----------------
  function __headersOf(raw) {
    var out = {};
    if (!raw) return out;
    if (typeof raw === 'string') {
      var parsed = __json(raw, null);
      if (parsed && typeof parsed === 'object') raw = parsed; else return out;
    }
    for (var k in raw) {
      if (Object.prototype.hasOwnProperty.call(raw, k) && raw[k] != null) out[k] = String(raw[k]);
    }
    return out;
  }
  function __buildBody(opts) {
    var headers = __headersOf(opts.headers);
    if (opts.body != null) return { headers: headers, body: String(opts.body) };
    if (opts.data == null) return { headers: headers, body: '' };
    var pt = opts.postType || 'json';
    if (pt === 'json') {
      if (!headers['Content-Type']) headers['Content-Type'] = 'application/json';
      return { headers: headers, body: typeof opts.data === 'string' ? opts.data : JSON.stringify(opts.data) };
    }
    if (pt === 'form') {
      if (!headers['Content-Type']) headers['Content-Type'] = 'application/x-www-form-urlencoded';
      var parts = [];
      var data = opts.data;
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch (e) {}
      }
      if (data && typeof data === 'object') {
        for (var k in data) {
          if (Object.prototype.hasOwnProperty.call(data, k)) {
            parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(String(data[k])));
          }
        }
      } else {
        parts.push(String(data));
      }
      return { headers: headers, body: parts.join('&') };
    }
    if (pt === 'form-data') {
      var boundary = '----KniephosBoundary' + Math.floor(Math.random() * 1e9);
      var lines = [];
      var fd = opts.data;
      if (fd && typeof fd === 'object') {
        for (var fk in fd) {
          if (!Object.prototype.hasOwnProperty.call(fd, fk)) continue;
          lines.push('--' + boundary + '\r\nContent-Disposition: form-data; name="' + fk + '"\r\n\r\n' + String(fd[fk]) + '\r\n');
        }
      }
      lines.push('--' + boundary + '--\r\n');
      headers['Content-Type'] = headers['Content-Type'] || ('multipart/form-data; boundary=' + boundary);
      return { headers: headers, body: lines.join('') };
    }
    return { headers: headers, body: String(opts.data) };
  }
  function __request(url, options) {
    var opts = options || {};
    var built = __buildBody(opts);
    var res = __json(__callNative('__net', {
      url: String(url == null ? '' : url),
      method: String(opts.method || 'get').toLowerCase(),
      headers: built.headers,
      body: built.body,
      timeout: opts.timeout ? Math.round(Number(opts.timeout) * 1000) : 10000,
      charset: opts.charset ? String(opts.charset) : '',
      buffer: Number(opts.buffer == null ? 0 : opts.buffer),
      redirect: opts.redirect === 0 ? 0 : 1
    }), null);
    if (!res || typeof res !== 'object') return { headers: {}, content: '' };
    if (res.headers == null) res.headers = {};
    if (res.content == null) res.content = '';
    return res;
  }
  function req(url, options) { return __request(url, options); }
  function _http(url, options) {
    if (options && options.async === false) return __request(url, options);
    var p = Promise.resolve(__request(url, options));
    if (options && typeof options.complete === 'function') {
      return p.then(function (r) {
        try { options.complete(r); } catch (e) {}
        return undefined;
      });
    }
    return p;
  }
  function http(url, options) {
    if (options && options.async === false) return _http(url, options);
    return _http(url, options).catch(function () {
      return { ok: false, status: 500, url: url };
    });
  }

  // ---------------- 存储 / 加解密 ----------------
  var local = {
    get: function (key, def) {
      var v = __callNative('__local', { op: 'get', key: String(key == null ? '' : key) });
      if (v === '') return def === undefined ? '' : def;
      return v;
    },
    set: function (key, value) {
      __callNative('__local', {
        op: 'set',
        key: String(key == null ? '' : key),
        value: typeof value === 'string' ? value : JSON.stringify(value)
      });
      return true;
    },
    del: function (key) {
      __callNative('__local', { op: 'del', key: String(key == null ? '' : key) });
      return true;
    }
  };
  function md5(s) { return __callNative('__md5', { s: String(s == null ? '' : s) }); }
  function sha1(s) { return __callNative('__sha1', { s: String(s == null ? '' : s) }); }
  function sha256(s) { return __callNative('__sha256', { s: String(s == null ? '' : s) }); }
  function base64Encode(s) { return __callNative('__b64e', { s: String(s == null ? '' : s) }); }
  function base64Decode(s) { return __callNative('__b64d', { s: String(s == null ? '' : s) }); }
  if (typeof G.btoa !== 'function') G.btoa = base64Encode;
  if (typeof G.atob !== 'function') G.atob = base64Decode;
  G.req = req;
  G.http = http;
  G._http = _http;
  G.local = local;
  G.md5 = md5;
  G.sha1 = sha1;
  G.sha256 = sha256;
  G.base64Encode = base64Encode;
  G.base64Decode = base64Decode;

  function joinUrl(parent, child) {
    parent = String(parent == null ? '' : parent);
    child = String(child == null ? '' : child);
    if (!parent) return child;
    if (!child) return parent;
    try { return new URL(child, parent).toString(); } catch (e) {}
    if (/^https?:\/\//i.test(child)) return child;
    if (child.charAt(0) === '/') {
      var m = /^(https?:\/\/[^\/]+)/i.exec(parent);
      return m ? m[1] + child : child;
    }
    if (parent.charAt(parent.length - 1) === '/') return parent + child.replace(/^\.\//, '');
    return parent.replace(/\/[^\/]*$/, '') + '/' + child.replace(/^\.\//, '');
  }

  // ---------------- console / timers ----------------
  function __stringifyArg(v) {
    if (typeof v === 'string') return v;
    try { return JSON.stringify(v); } catch (e) { return String(v); }
  }
  var __consoleFn = function () {
    var parts = [];
    for (var i = 0; i < arguments.length; i++) parts.push(__stringifyArg(arguments[i]));
    if (typeof print === 'function') {
      try { print(parts.join(' ')); return; } catch (e) {}
    }
  };
  G.console = { log: __consoleFn, info: __consoleFn, warn: __consoleFn, error: __consoleFn, debug: __consoleFn };
  if (typeof G.setInterval !== 'function') {
    G.setInterval = function (fn, ms) {
      var token = { alive: true };
      function tick() {
        if (!token.alive) return;
        try { fn(); } catch (e) {}
        if (typeof G.setTimeout === 'function') G.setTimeout(tick, ms || 0);
      }
      if (typeof G.setTimeout === 'function') G.setTimeout(tick, ms || 0);
      return token;
    };
    G.clearInterval = function (token) { if (token) token.alive = false; };
  }
  if (typeof G.clearTimeout !== 'function') G.clearTimeout = function () {};

  // ---------------- 模块系统 ----------------
  var __MODULES = {};
  var __LOADING = {};
  var __MAIN_URL = '';

  function __evalModule(code, key) {
    if (Object.prototype.hasOwnProperty.call(__MODULES, key)) return __MODULES[key];
    var module = { exports: {} };
    var fn;
    try {
      fn = new Function('module', 'exports', 'require', '__filename', code + '\n//# sourceURL=' + key);
    } catch (e) {
      __MODULES[key] = {};
      throw e;
    }
    fn(module, module.exports, function (spec) { return __requireFrom(spec, key); }, key);
    __MODULES[key] = module.exports;
    return module.exports;
  }
  function __requireFrom(spec, baseUrl) {
    spec = String(spec == null ? '' : spec);
    if (!spec) return {};
    if (spec.indexOf('net.js') >= 0) return { req: req, http: http };
    var r = __json(__callNative('__module', { spec: spec, baseUrl: String(baseUrl || '') }), null);
    if (!r || !r.ok) return {};
    var key = r.key || spec;
    if (Object.prototype.hasOwnProperty.call(__MODULES, key)) return __MODULES[key];
    if (__LOADING[key]) return {};
    __LOADING[key] = true;
    try {
      return __evalModule(r.source, key);
    } catch (e) {
      __MODULES[key] = {};
      return {};
    } finally {
      delete __LOADING[key];
    }
  }
  function require(spec) { return __requireFrom(spec, __MAIN_URL); }
  G.require = require;
  G.$ = { require: require };

  // ---------------- cheerio / CryptoJS 懒加载 ----------------
  var __cheerioCache = null;
  function __cheerio() {
    if (__cheerioCache) return __cheerioCache;
    var m = __requireFrom('cheerio.min.js', __MAIN_URL);
    var ns = (m && m.default) || m || {};
    if (m && m.default) {
      for (var k in m) {
        if (k !== 'default' && ns[k] === undefined) {
          try { ns[k] = m[k]; } catch (e) {}
        }
      }
    }
    __cheerioCache = ns;
    return ns;
  }
  var __cryptoCache = null;
  function __crypto() {
    if (__cryptoCache) return __cryptoCache;
    var m = __requireFrom('crypto-js.js', __MAIN_URL);
    __cryptoCache = (m && (m.CryptoJS || m.default)) || m || {};
    return __cryptoCache;
  }
  try {
    Object.defineProperty(G, 'cheerio', { configurable: true, get: function () { return __cheerio(); } });
    Object.defineProperty(G, 'CryptoJS', { configurable: true, get: function () { return __crypto(); } });
  } catch (e) {
    G.cheerio = null;
    G.CryptoJS = null;
  }

  // ---------------- 海阔规则 DSL（cheerio 实现，1:1 对齐 HtmlParser.java） ----------------
  var NOADD_INDEX = /:eq|:lt|:gt|:first|:last|^body$|^#/;
  var URLJOIN_ATTR = /(url|src|href|-original|-src|-play|-url|style)$/i;
  var SPECIAL_URL = /^(ftp|magnet|thunder|ws):/i;

  function __parseInfo(nparse) {
    var info = { rule: nparse, index: 0, excludes: [], first: false, last: false, lt: null, gt: null };
    if (nparse.indexOf(':eq') >= 0) {
      info.rule = nparse.split(':')[0];
      var pos = nparse.split(':')[1] || '';
      if (info.rule.indexOf('--') >= 0) {
        var rules = info.rule.split('--');
        info.excludes = rules.slice(1);
        info.rule = rules[0];
      } else if (pos.indexOf('--') >= 0) {
        var rules2 = pos.split('--');
        info.excludes = rules2.slice(1);
        pos = rules2[0];
      }
      var m = /eq\(\s*(-?\d+)\s*\)/.exec(pos);
      info.index = m ? parseInt(m[1], 10) : 0;
    } else {
      if (nparse.indexOf('--') >= 0) {
        var rules3 = info.rule.split('--');
        info.excludes = rules3.slice(1);
        info.rule = rules3[0];
      }
      if (/:first(?![\w-])/.test(info.rule)) info.first = true;
      if (/:last(?![\w-])/.test(info.rule)) info.last = true;
      var lt = /:lt\((\d+)\)/.exec(info.rule);
      if (lt) info.lt = parseInt(lt[1], 10);
      var gt = /:gt\((\d+)\)/.exec(info.rule);
      if (gt) info.gt = parseInt(gt[1], 10);
      info.rule = info.rule.replace(/:(?:first|last)(?![\w-])/g, '').replace(/:lt\(\d+\)/g, '').replace(/:gt\(\d+\)/g, '');
    }
    return info;
  }
  function __hikerToJq(parse, first) {
    if (parse.indexOf('&&') >= 0) {
      var parses = parse.split('&&');
      var out = [];
      for (var i = 0; i < parses.length; i++) {
        var pss = parses[i].split(' ');
        var ps = pss[pss.length - 1];
        if (!NOADD_INDEX.test(ps)) {
          if (!first && i >= parses.length - 1) out.push(parses[i]);
          else out.push(parses[i] + ':eq(0)');
        } else {
          out.push(parses[i]);
        }
      }
      return out.join(' ');
    }
    var pss2 = parse.split(' ');
    var ps2 = pss2[pss2.length - 1];
    if (!NOADD_INDEX.test(ps2) && first) return parse + ':eq(0)';
    return parse;
  }
  function __selectOne(ch, $, nparse, prev) {
    var info = __parseInfo(nparse);
    var rule = info.rule.trim();
    var ret;
    if (!prev || prev.length === 0) ret = rule ? $(rule) : $([]);
    else ret = rule ? prev.find(rule) : $([]);
    if (nparse.indexOf(':eq') >= 0) {
      var size = ret.length;
      ret = ret.eq(info.index < 0 ? size + info.index : info.index);
    }
    if (info.first) ret = ret.eq(0);
    else if (info.last) ret = ret.eq(-1);
    if (info.lt !== null) ret = ret.slice(0, info.lt);
    if (info.gt !== null) ret = ret.slice(info.gt + 1);
    if (info.excludes.length > 0 && ret.length > 0) {
      var clone = ret.clone();
      for (var i = 0; i < info.excludes.length; i++) {
        if (info.excludes[i]) clone.find(info.excludes[i]).remove();
      }
      ret = clone;
    }
    return ret;
  }
  function __selectChain(ch, $, rule, first) {
    var jq = __hikerToJq(rule, first);
    var ret = null;
    var segs = jq.split(' ');
    for (var i = 0; i < segs.length; i++) {
      if (!segs[i]) continue;
      ret = __selectOne(ch, $, segs[i], ret);
      if (!ret || ret.length === 0) return null;
    }
    return ret;
  }
  function __parseDomForUrl(ch, html, rule, addUrl) {
    if (!html || !rule) return '';
    var $ = ch.load(html);
    if (rule === 'body&&Text' || rule === 'Text') return $('body').text();
    if (rule === 'body&&Html' || rule === 'Html') return $.html();
    var option = '';
    if (rule.indexOf('&&') >= 0) {
      var rs = rule.split('&&');
      option = rs[rs.length - 1];
      rule = rs.slice(0, -1).join('&&');
    }
    var ret = __selectChain(ch, $, rule, true);
    if (!ret || ret.length === 0) return '';
    var result = '';
    if (option) {
      if (option === 'Text') result = ret.text();
      else if (option === 'Html') result = ret.html() || '';
      else {
        result = ret.attr(option) || '';
        if (option.toLowerCase().indexOf('style') >= 0 && result.indexOf('url(') >= 0) {
          var m = /url\((.*?)\)/.exec(result);
          if (m) result = m[1];
          if (result) result = result.replace(/^['"](.*)['"]$/, '$1');
        }
        if (result && addUrl) {
          if (URLJOIN_ATTR.test(option) && !SPECIAL_URL.test(result)) {
            if (result.indexOf('http') >= 0) result = result.substring(result.indexOf('http'));
            else result = joinUrl(addUrl, result);
          }
        }
      }
    } else {
      result = ret.length > 0 ? $.html(ret[0]) : '';
    }
    return result;
  }
  function __parseDomForArray(ch, html, rule) {
    if (!html || !rule) return [];
    var $ = ch.load(html);
    var ret = __selectChain(ch, $, rule, false);
    if (!ret || ret.length === 0) return [];
    var arr = ret.toArray();
    var out = [];
    for (var i = 0; i < arr.length; i++) out.push($.html(arr[i]));
    return out;
  }
  function __parseDomForList(ch, html, p1, listText, listUrl, addUrl) {
    if (!html || !p1) return [];
    var $ = ch.load(html);
    var ret = __selectChain(ch, $, p1, false);
    if (!ret || ret.length === 0) return [];
    var arr = ret.toArray();
    var out = [];
    for (var i = 0; i < arr.length; i++) {
      var it = $.html(arr[i]);
      out.push(__parseDomForUrl(ch, it, listText, '').trim() + '$' + __parseDomForUrl(ch, it, listUrl, addUrl));
    }
    return out;
  }
  function pdfh(html, rule) { return __parseDomForUrl(__cheerio(), html, rule, ''); }
  function pd(html, rule, addUrl) { return __parseDomForUrl(__cheerio(), html, rule, addUrl || ''); }
  function pdfa(html, rule) { return __parseDomForArray(__cheerio(), html, rule); }
  function pdfla(html, p1, listText, listUrl, addUrl) {
    return __parseDomForList(__cheerio(), html, p1, listText, listUrl, addUrl || '');
  }
  G.pdfh = pdfh;
  G.pd = pd;
  G.pdfa = pdfa;
  G.pdfla = pdfla;
  G.joinUrl = joinUrl;

  // ---------------- 蜘蛛装载 / 调用 ----------------
  var __SPIDER = null;
  var __STYLE = 'unknown';
  var __METHODS = {
    home: ['homeContent', 'home'],
    homeVod: ['homeVideoContent', 'homeVod', 'homeVid'],
    category: ['categoryContent', 'category'],
    detail: ['detailContent', 'detail'],
    search: ['searchContent', 'search'],
    play: ['playerContent', 'play'],
    live: ['liveContent', 'live']
  };

  function __looksLikeSpider(o) {
    if (o == null || (typeof o !== 'object' && typeof o !== 'function')) return false;
    for (var a in __METHODS) {
      var names = __METHODS[a];
      for (var i = 0; i < names.length; i++) {
        try { if (typeof o[names[i]] === 'function') return true; } catch (e) {}
      }
    }
    return false;
  }
  function __hasModuleSyntax(src) {
    return /(^|[\n;])\s*(import|export)\b/.test(src);
  }
  function __pickSpider(exp) {
    var spider = null;
    var isCat = false;
    try {
      if (exp && typeof exp.__jsEvalReturn === 'function') {
        spider = exp.__jsEvalReturn();
        isCat = true;
      }
    } catch (e) {}
    if (!spider && exp && exp.default != null) {
      try { spider = typeof exp.default === 'function' ? exp.default() : exp.default; } catch (e) {}
    }
    if (!__looksLikeSpider(spider) && __looksLikeSpider(exp)) spider = exp;
    if (!__looksLikeSpider(spider)) {
      if (G.spider && __looksLikeSpider(G.spider)) spider = G.spider;
      else if (G.rule && __looksLikeSpider(G.rule)) spider = G.rule;
    }
    return { spider: spider, isCat: isCat };
  }
  function __initSpider(source, apiUrl, ext, isModule) {
    __MAIN_URL = String(apiUrl || '');
    __SPIDER = null;
    __STYLE = 'unknown';
    var exp;
    if (isModule) {
      var key = __MAIN_URL || 'spider.js';
      exp = __evalModule(source, key);
    } else {
      try { (0, eval)(source); } catch (e) { throw e; }
      exp = G;
    }
    var picked = __pickSpider(exp);
    if (!__looksLikeSpider(picked.spider) && isModule) {
      var mod = __MODULES[__MAIN_URL || 'spider.js'];
      if (mod && __looksLikeSpider(mod)) picked.spider = mod;
    }
    if (!__looksLikeSpider(picked.spider)) {
      throw new Error('脚本未导出可识别的蜘蛛对象（__jsEvalReturn / default / 方法集）');
    }
    __SPIDER = picked.spider;
    var has = function (m) { return typeof __SPIDER[m] === 'function'; };
    if (has('homeContent') || has('categoryContent') || has('detailContent')) __STYLE = 'hiker';
    else if (has('home') || has('category') || has('detail')) __STYLE = 'drpy';
    if (typeof __SPIDER.init === 'function') {
      var arg = ext == null ? '' : ext;
      var parsedExt = null;
      if (typeof arg === 'string') parsedExt = __json(arg, null);
      var initArg = picked.isCat
        ? { stype: 3, skey: '', ext: parsedExt == null ? arg : parsedExt }
        : (parsedExt == null ? arg : parsedExt);
      try { __SPIDER.init(initArg); } catch (e) {}
    }
    return __STYLE;
  }
  function __stringifyResult(v) {
    if (v == null) return '';
    if (typeof v === 'string') return v;
    try { return JSON.stringify(v); } catch (e) { return String(v); }
  }
  function __callSpider(action, args) {
    var names = __METHODS[action] || [action];
    var fn = null;
    for (var i = 0; i < names.length; i++) {
      if (typeof __SPIDER[names[i]] === 'function') { fn = __SPIDER[names[i]]; break; }
    }
    if (!fn) return Promise.resolve('');
    return new Promise(function (resolve) {
      try {
        var r = fn.apply(__SPIDER, args || []);
        if (r && typeof r.then === 'function') {
          r.then(function (v) { resolve(__stringifyResult(v)); },
                 function (e) { resolve(JSON.stringify({ __error: __errText(e) })); });
        } else {
          resolve(__stringifyResult(r));
        }
      } catch (e) {
        resolve(JSON.stringify({ __error: __errText(e) }));
      }
    });
  }
  function __invoke(action, argsJson) {
    if (!__SPIDER) return Promise.resolve(JSON.stringify({ __error: '蜘蛛未初始化' }));
    var args = __json(argsJson, []);
    if (!Array.isArray(args)) args = [args];
    return __callSpider(action, args);
  }
  G.__kniephosInitSpider = function (source, apiUrl, extJson, isModule) {
    try {
      var style = __initSpider(
        String(source == null ? '' : source),
        String(apiUrl || ''),
        extJson,
        isModule === true
      );
      return JSON.stringify({ ok: true, style: style });
    } catch (e) {
      return JSON.stringify({ ok: false, error: __errText(e) });
    }
  };
  G.__kniephosInvoke = function (action, argsJson) {
    if (!__SPIDER) return Promise.resolve(JSON.stringify({ __error: '蜘蛛未初始化' }));
    var args = Array.isArray(argsJson) ? argsJson : __json(String(argsJson || '[]'), []);
    if (!Array.isArray(args)) args = [args];
    return __callSpider(String(action || ''), args);
  };
})();
''';
