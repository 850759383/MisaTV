# 开发约定与实现记录

面向改代码的人。用户向的功能说明、下载与免责声明在根目录 [README](../README.md)。

## 架构一句话

`AppState : ChangeNotifier` + `InheritedNotifier` 管全部状态，`shared_preferences` 管全部持久化，
不引入状态管理框架、路由框架与数据库。页面全部是 `StatefulWidget` / `StatelessWidget`，
跨页面取状态一律 `AppScope.of(context)`。

跨平台能力统一拆成三件套：`foo.dart` 做条件导出
（`export 'foo_io.dart' if (dart.library.js_interop) 'foo_web.dart';`），
`foo_io.dart` 是桌面 / 移动实现，`foo_web.dart` 是 Web 桩。新增涉及 `dart:io` 的能力时照此办理。

## 请求链路

```text
AppState ──> SourceService ──> CmsSource      (type 0 / 1 / 4，MovieParser 解析 XML / JSON)
                          ├──> JsSpiderService (type 3, .js  → QuickJS isolate)
                          ├──> PySpiderService (type 3, .py  → 嵌入式 Python)
                          ├──> JarSpiderService(type 3, jar  → JVM 反射调用)
                          └──> KazumiSource    (type 5, 规则源)
```

播放链路：`SourceService.resolvePlay` → `play_result_parser` 归一化 → `AppState.preparePlay`
（判断是否需要中继）→ `LocalRelay` 生成 `http://127.0.0.1:<port>/play?...` → fvp 播放。

## 本地中继

单例 `LocalRelay`，首选 `127.0.0.1:9978`，被占用时换临时端口（生成的中继地址都带真实端口）。

| 路由 | 作用 |
| --- | --- |
| `/play` | 注入 UA / Referer / Cookie，HLS 清单与分片递归改写，可选 m3u8 去广告 |
| `/file` `/pkg` | 中继应用数据目录内的本地文件（本地包源、字幕、封面） |
| `/img` | 图片兜底中继，补豆瓣要求的 `Referer` |
| `/bt/<infohash>/<index>` | 磁力 Range 取流 + piece 门控（512KB 一片） |
| `/proxy` `/proxy/<port>` | 直播代理；壳内路由（如 `do=hmys`）原样转发给常驻取流 JVM |

两个必须遵守的约束：

1. **请求头与超长地址要换成短 token**（`hk=` / `p=`）。网盘直链 + Cookie + UA + Referer 全塞进 query
   会超过 FFmpeg 的 `MAX_URL_SIZE`（4096），外部 MPV 直接报「URL too long」；内置 fvp 走 Dart 能忍，
   所以只在外部播放器上暴露。
2. **加固壳播放必须让 JVM 常驻**（`SpiderHost --hold`）。壳返回的播放地址指向该 JVM 自己的
   `127.0.0.1:<port>`，一次性进程退出后地址立即失效。

## 蜘蛛运行时

| 类型 | 实现要点 |
| --- | --- |
| `.js` | QuickJS 在独立 isolate 执行，`req()` 由 curl 子进程提供同步语义；脚本落盘缓存 6 小时，断网回退旧缓存。超时**不能**用 `Isolate.immediate` 强杀（会把原生 runtime 拆掉，之后 native 代码访问已释放内存 → `quickjs_c_bridge.dll` 里 c0000409 闪退），要用 `beforeNextEvent` 等当前原生调用回到事件循环后再终止 |
| `.py` | 首次使用按需下载 Python 3.11 嵌入式运行时；`assets/python_runner/runner.py` 是桥 |
| `jar` / DEX | 下载 jar → 若含 `classes.dex` 用 dex2jar 转换 → 反射调用 `stubs.jar` 里的 `SpiderRunner`；dex2jar 对 R8「去掉构造器」的 `NEW` 误译由 `DexJarRepair` 修正 |
| 加固壳 | 首次用 unidbg ARM 桥解包，缓存到 `jvm_cache/payloads/<jar>/`；之后用 shell-shim（纯 Java 影子 `DexNative`）加载缓存，不再启动模拟器 |

jar 系蜘蛛**不读 `ext` 里的网盘凭据**，必须由应用主动落盘到四个位置
（`.quarkcookie`、prefs 种子、Pixazz、`Cloud-drive.txt`），缺一个就会显示「还没有配置夸克 Cookie」。

## 设置页折叠规范

设置页里的**每个父分类都必须可折叠**：一律用 `_Section(collapsible: true, initiallyExpanded: false, summary: ...)`
（这两个参数默认值已是「可折叠 + 默认收起」），标题栏 `trailing` 放数量或当前值，`summary` 放收起时的一行摘要。

新增父分类时照此办理，不要留常驻展开的区块：设置页是长列表，任何一块展开都会把其他分类挤出屏幕。
没有合适摘要时至少保留 `trailing` 的计数 / 状态。**唯一例外是「关于」**（`collapsible: false`）。

## Windows 渲染与内存

`windows/runner/main.cpp` 关闭了 Impeller（`flutter::ImpellerSwitch::Disabled`，回退 Skia）。
Flutter 3.47 在 Windows 默认走 Impeller OpenGLESSDF 后端，本项目的圆角、渐变与光晕界面在该后端下
会保留大量整窗尺寸的离屏缓冲，空载提交内存实测 600MB 以上（峰值约 1.4GB）；回退 Skia 后同一界面
空载约 140MB、详情页约 150MB、播放（含 JVM 取流）约 240MB。

图片解码同时收敛：`imageCache` 上限 48MB / 220 张（`main.dart`），海报 `cacheWidth: 320`、
详情背景 960、收藏与直播台标 200 / 128。首页背景只用一层对角渐变，用 `CustomPainter`
（`AppBackdropPainter`）画在内容之下的同一绘制层，不用溢出视口的 `Stack`。

## Windows 关窗退出

关窗分两步：Dart 侧 `window_manager` 拦下关闭消息（`setPreventClose(true)`），先跑
`registerAppShutdown` 注册的收尾（结束常驻取流 JVM），再发 `WM_QUIT`；runner 退出消息循环后
**先销毁窗口**（让 `WM_DESTROY` 在视图还挂着时释放引擎），然后 `TerminateProcess` 直接结束进程。

这两处顺序不能省：窗口晚于 `FlutterViewController` 成员销毁，退出会在 `flutter_windows.dll` 里踩空；
不跳过静态析构 / `DllMain` 卸载，WebView2（`coremessaging.dll`）会 fail-fast。任何一次崩溃都会被
Windows 错误报告留下进程快照克隆，表现为任务管理器里一堆 0 线程的 `MisaTV.exe`，既关不掉也锁住 `build` 目录。

## 数据存储

全部 `shared_preferences`，键前缀 `kniephos.`（键名集中在 `lib/services/local_store.dart`）：

| 键 | 内容 |
| --- | --- |
| `kniephos.profiles` / `activeProfile` / `activeSite` | 订阅档案与当前站点 |
| `kniephos.activeLive` / `activeLiveProfile` / `localLives` | 当前直播源、直播订阅档案、本地导入的 TXT / M3U |
| `kniephos.themeMode` / `accentIndex` / `navBarSize` / `homeColumns` / `homeBrowseMode` | 外观与首页布局 |
| `kniephos.favorites` / `history` / `searchHistory` / `skipSegments` | 收藏、历史、搜索历史、跳过片头片尾 |
| `kniephos.playerSettings` / `danmakuSettings` / `contentFilter` | 播放、弹幕、内容过滤设置 |
| `kniephos.driveAccounts` / `xunleiAccount` / `davServers` / `proxy` | 网盘 Cookie（明文）、迅雷、WebDAV、代理 |
| `kniephos.assrtToken` / `customSubtitleApis` / `movieQuotes` / `eulaAccepted` / `windowSize` | 字幕、台词缓存、协议标记、窗口尺寸 |

数据目录默认**软件安装目录下的 `userdata`**（`lib/core/platform/portable_app_data_io.dart`，
绿色版可直接搬走），不可写时回落 `%APPDATA%\com.kniephos\MisaTV`。Windows 版自带一个
`shared_preferences` 文件存储实现（`PortablePrefsStore`），因为官方实现固定读 `PathProviderWindows()`，
不跟随 `PathProviderPlatform.instance`。

## 测试

`flutter test` 覆盖纯逻辑层：配置解析（字段默认值、多仓合并、宽容 JSON、`py_` 过滤）、影片解析
（XML / JSON、多线路、选集、筛选）、直播解析、XMLTV 时间与匹配、直播导出、播放器画面比例与外部播放器探测、
备份格式（原生 / 旧版 Win-Box / `user-config.json`）、合并导出、本地直播源、本地中继（含 WebDAV 鉴权与
`/bt` Range 取流）、m3u8 去广告、VIP 解析、字幕与弹幕（屏蔽词、屏占、排轨）、豆瓣元数据与封面补全、
WebDAV（PROPFIND 解析）、DLNA（SSDP / DIDL-SOAP / 投屏动作链）、磁力（magnet 解析 / 选片 / piece 位序）、
内容过滤（关键词归一 / 多字段匹配 / 密码摘要）、影视台词、本地包路径改写、网盘 Cookie 四通道落盘。

不覆盖：UI 渲染、真实源站网络、JVM / Python 真实调用。

## 已知边界

- 音频源码直通（SPDIF / HDMI 比特流）与超分辨率未实现：libmdk 没有对应接口，不做假开关。
- PUSH 源不支持。
- Web 版仅用于界面预览，播放能力受浏览器编解码与跨域策略限制。
- 端口 9978 被占用时会换端口；壳内生成的地址若硬编码 9978 / `-1`，`SpiderHost` 会统一改写成本 JVM 实际端口。
