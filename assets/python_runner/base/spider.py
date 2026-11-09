# -*- coding: utf-8 -*-
# base.spider —— .py 蜘蛛基类（CPython3 版，桌面端经嵌入式 Python 运行）。
# 对齐上游 Box pyramid（.tmp/box-src/Box-main/pyramid/src/python/base/spider.py）核心
# 调用面：kkys 类蜘蛛通过 `from base.spider import Spider` 继承，依赖：
#   - self.fetch(url, headers=..., timeout=..., verify=False) → requests.Response（.text/.raw/.status_code/.close/.encoding）
#   - self.html(content) → lxml etree（HTML 解析；_html 类蜘蛛常自行实现）
#   - regStr / str2json / json2str / getProxyUrl 等工具
# 运行时自带 requests/urllib3/lxml 到 site-packages（见 JarSpiderBridge.ensureRuntimeLibs）。

from urllib.parse import quote, urlencode
import json
import re
import os
import threading
import time
from urllib.parse import urlparse

import requests
import urllib3  # noqa: F401  与源内 `import urllib3` 对齐（可选，装了即用）
urllib3.disable_warnings()


_DEFAULT_NET_HEADERS = {
    'User-Agent': 'okhttp/4.12.0',
    'Accept': '*/*',
}


class _NetSession:
    """`self.net.session()` 返回的会话：按域名保存 Cookie，并复用 net.req。"""

    def __init__(self, net):
        self._net = net
        self._cookies = {}
        self._closed = False

    def setCookie(self, host, cookie):
        try:
            host = (host or '').strip().lower()
            text = str(cookie or '').strip()
            if not host or not text:
                return False
            parts = [p.strip() for p in text.split(';') if p.strip()]
            first = parts[0]
            if '=' not in first:
                return False
            name, value = first.split('=', 1)
            name = name.strip()
            if not name:
                return False
            domain = host
            for part in parts[1:]:
                if '=' not in part:
                    continue
                key, val = part.split('=', 1)
                if key.strip().lower() == 'domain' and val.strip():
                    domain = val.strip().lower().lstrip('.')
            self._cookies.setdefault(domain, {})[name] = value.strip()
            return True
        except Exception:
            return False

    def _cookie_for(self, url):
        host = (urlparse(url).hostname or '').lower()
        merged = {}
        for domain, values in self._cookies.items():
            if host == domain or host.endswith('.' + domain):
                merged.update(values)
        return '; '.join('%s=%s' % (k, v) for k, v in merged.items())

    def req(self, url, options=None):
        options = dict(options or {})
        headers = dict(options.get('headers') or {})
        cookie = self._cookie_for(url)
        if cookie:
            headers['Cookie'] = cookie
        return self._net.req(url, options, _extra_headers=headers)

    def close(self):
        self._closed = True

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


class _Net:
    """新版 PY 蜘蛛的 `self.net`（对齐 Box pyramid 网络层）：

    - `net.req(url, options)` → `{code, content, headers, contentType, error?}`
      （`buffer>0` 时 content 是 bytes，否则是文本）
    - `net.json(url, options)` → 解析后的 JSON
    - `net.cached(key, {"ttl": 毫秒}, loader)` / `net.clearCache(key)`
    - `net.session()` → 带 Cookie 的会话
    """

    def __init__(self):
        self._cache = {}
        self._lock = threading.RLock()

    def req(self, url, options=None, _extra_headers=None):
        options = dict(options or {})
        headers = dict(_DEFAULT_NET_HEADERS)
        headers.update(options.get('headers') or {})
        if _extra_headers:
            headers.update(_extra_headers)
        raw_timeout = options.get('timeout') or options.get('callTimeout') or 15000
        try:
            timeout = max(1.0, float(raw_timeout) / 1000.0)
        except Exception:
            timeout = 15.0
        method = str(options.get('method') or 'GET').upper()
        params = options.get('params')
        data = options.get('data')
        # 新版迁移规范用 options['body'] 传原始请求体（字符串 / bytes / 字节数组）；
        # 旧实现只读 data，会把已加密的表单 body 丢掉，服务端便报“缺少参数”。
        raw_body = options.get('body')
        if raw_body is not None and method not in ('GET', 'HEAD'):
            if isinstance(raw_body, list):
                raw_body = bytes([int(x) & 255 for x in raw_body])
            data = raw_body
        want_bytes = int(options.get('buffer') or 0) > 0
        try:
            if method == 'POST':
                post_type = str(options.get('postType') or '').lower()
                if post_type in ('json', 'application/json'):
                    resp = requests.post(url, params=params, headers=headers, json=data,
                                         timeout=timeout, verify=False)
                else:
                    resp = requests.post(url, params=params, headers=headers, data=data,
                                         timeout=timeout, verify=False)
            elif method == 'HEAD':
                resp = requests.head(url, params=params, headers=headers,
                                     timeout=timeout, verify=False)
            elif method == 'GET':
                resp = requests.get(url, params=params, headers=headers,
                                    timeout=timeout, verify=False)
            else:
                # OPTIONS / PUT / DELETE 等：有些源要先发 CORS 预检
                # （如廣東廣電），当成 GET 会直接 401。
                resp = requests.request(method, url, params=params, headers=headers,
                                        data=data, timeout=timeout, verify=False)
        except Exception as error:
            return {
                'code': 0,
                'content': b'' if want_bytes else '',
                'headers': {},
                'contentType': '',
                'error': str(error),
            }
        content = resp.content if want_bytes else resp.text
        return {
            'code': resp.status_code,
            'content': content,
            'headers': dict(resp.headers),
            'contentType': resp.headers.get('Content-Type', ''),
            'url': resp.url,
        }

    def json(self, url, options=None):
        result = self.req(url, options)
        if result.get('error'):
            raise ValueError(str(result['error']))
        if result['code'] >= 400:
            raise ValueError('HTTP %s' % result['code'])
        text = result['content']
        if isinstance(text, bytes):
            text = text.decode('utf-8', 'ignore')
        try:
            return json.loads(text)
        except ValueError as error:
            raise ValueError('%s（%s，前 80 字符：%r）'
                             % (error, url, text[:80])) from None

    def text(self, url, options=None):
        return self.req(url, options).get('content', '')

    def get(self, url, headers=None, params=None, timeout=None):
        options = {'headers': headers or {}, 'params': params}
        if timeout is not None:
            options['timeout'] = timeout
        return self.req(url, options)

    def post(self, url, headers=None, params=None, data=None, postType='form', timeout=None):
        options = {'headers': headers or {}, 'params': params, 'method': 'POST',
                   'data': data, 'postType': postType}
        if timeout is not None:
            options['timeout'] = timeout
        return self.req(url, options)

    def cached(self, key, options=None, loader=None):
        opts = options if isinstance(options, dict) else {}
        try:
            ttl = float(opts.get('ttl') or 0) / 1000.0
        except Exception:
            ttl = 0
        now = time.time()
        with self._lock:
            entry = self._cache.get(key)
        if entry is not None and entry[1] > now:
            return entry[0]
        value = loader() if callable(loader) else None
        with self._lock:
            self._cache[key] = (value, now + ttl) if ttl > 0 else (value, float('inf'))
        return value

    def clearCache(self, key=None):
        with self._lock:
            if key is None:
                self._cache.clear()
            else:
                self._cache.pop(key, None)

    def session(self):
        return _NetSession(self)

    def ws(self, url, options=None):
        """`net.ws(url, {headers, data, timeout})`：发一条 JSON 消息并读回一条。

        上游（如廣東廣電的 wsnode 接口）用它把 TCP 节点换成 WS 节点；返回
        `{code: 101, content: 文本, headers: {}}`，失败时 `error` 带原因。
        """
        options = dict(options or {})
        headers = dict(options.get('headers') or {})
        timeout = options.get('timeout') or 10000
        try:
            timeout = max(1.0, float(timeout) / 1000.0)
        except Exception:
            timeout = 10.0
        payload = options.get('data')
        if payload is None:
            payload = {}
        body = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii=False)
        origin = headers.pop('Origin', None) or headers.pop('origin', None)
        try:
            import websocket
        except ImportError:
            return {'code': 0, 'content': '', 'headers': {},
                    'error': "No module named 'websocket'"}
        connection = None
        try:
            connection = websocket.create_connection(
                url,
                header=['%s: %s' % (k, v) for k, v in headers.items()],
                origin=origin,
                suppress_origin=bool(origin),
                timeout=timeout,
                sslopt={'cert_reqs': 0},
            )
            connection.send(body)
            return {'code': 101, 'content': connection.recv(), 'headers': {},
                    'contentType': 'application/json'}
        except Exception as error:
            return {'code': 0, 'content': '', 'headers': {}, 'error': str(error)}
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass


class Spider:
    def __init__(self):
        self.extend = ''
        self.net = _Net()

    def init(self, extend=""):
        pass

    def homeContent(self, filter):
        return {"class": [], "list": []}

    def homeVideoContent(self):
        return {"list": []}

    def categoryContent(self, tid, pg, filter, extend):
        return {"page": pg, "pagecount": 1, "limit": 0, "total": 0, "list": []}

    def detailContent(self, ids):
        return {"list": []}

    def searchContent(self, key, quick, pg="1"):
        return {"list": [], "page": 1}

    def playerContent(self, flag, id, vipFlags):
        return {}

    def liveContent(self, url):
        return {}

    def localProxy(self, param):
        return None

    def isVideoFormat(self, url):
        return False

    def manualVideoCheck(self):
        return False

    def destroy(self):
        pass

    def getName(self):
        return ""

    # ---- 网络（requests 直连；桌面端无系统拼装/代理差异） ----
    def fetch(self, url, params=None, cookies=None, headers=None, timeout=5, verify=False, stream=False,
              allow_redirects=True):
        resp = requests.get(url, params=params, cookies=cookies, headers=headers, timeout=timeout, verify=verify,
                            stream=stream, allow_redirects=allow_redirects)
        resp.encoding = 'utf-8'
        return resp

    def post(self, url, params=None, data=None, json=None, cookies=None, headers=None, timeout=5, verify=False,
             stream=False, allow_redirects=True):
        resp = requests.post(url, params=params, data=data, json=json, cookies=cookies, headers=headers,
                             timeout=timeout, verify=verify, stream=stream, allow_redirects=allow_redirects)
        resp.encoding = 'utf-8'
        return resp

    def html(self, content):
        from lxml import etree
        return etree.HTML(content.encode('utf-8') if isinstance(content, str) else content)

    def regStr(self, reg, src, group=1):
        m = re.search(reg, src)
        return m.group(group) if m else ''

    def removeHtmlTags(self, src):
        return re.sub('<.*?>', '', src)

    def cleanText(self, src):
        return re.sub(r'[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF\U0001F1E0-\U0001F1FF]', '',
                      src)

    def str2json(self, s):
        return json.loads(s)

    def json2str(self, o):
        return json.dumps(o, ensure_ascii=False)

    def getProxyUrl(self, param=None, local=True):
        """生成宿主 `/proxy?do=py` 地址；param 为字典时按查询串拼接。

        新版蜘蛛（央視頻/央視網/廣東廣電）会在频道里写
        `getProxyUrl({"pid": ..., "cnlid": ...})`，点击时宿主再回调
        `localProxy(param)` 拿动态播放地址。
        """
        base = os.environ.get('WINBOX_PY_PROXY') or '%s/proxy?do=py' % self._proxy_base()
        if isinstance(param, dict) and param:
            query = urlencode([(k, v) for k, v in param.items() if v is not None])
            if query:
                base += ('&' if '?' in base else '?') + query
        return base

    def _proxy_base(self):
        return 'http://127.0.0.1:9978'

    def log(self, msg):
        if isinstance(msg, (dict, list)):
            print(json.dumps(msg, ensure_ascii=False))
        else:
            print(msg)
