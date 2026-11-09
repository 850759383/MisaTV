package com.github.catvod.spider;

import dalvik.system.DexClassLoader;

import java.io.File;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * DexNative 的**纯 Java 影子类**（方案 A）。
 *
 * 用法：把它编成 `shell-shim.jar`，放在 SpiderRunner 的 classpath **最前面**，
 * 靠类加载顺序**覆盖**加固壳 jar 里那个 native 版本的 `DexNative`。
 * 于是壳的这座桥：
 *
 * ```
 * Init.init(ctx)      → DexNative.getLoader(ctx)            → Init 的 loader 字段
 * BaseSpiderGuard.<init> → Init.getSpider(name)
 *                          → DexNative.getSpider(loader,name) → 真实 Spider 实例
 * 之后所有 homeContent/categoryContent/... 都是纯 Java 委托
 * ```
 *
 * 就在**没有任何 native 代码**的情况下整条打通 —— 不再需要 `System.load(ARM.so)`。
 *
 * ── 为什么这个方案成立（都是实测结论，不是推测）──
 * 1. `BaseSpiderGuard` 是**纯委托**：反编译显示其全部方法体只有
 *    "取私有字段 + invokevirtual"（12 条 invokevirtual、0 条 ldc/getstatic/new），
 *    业务逻辑一行都不在里面。所以只要把"真实 Spider"给它，壳就活了。
 * 2. 壳里每个具体源（`NewDouBanGuard` 等）也都是空壳：
 *    `class XxxGuard extends BaseSpiderGuard { public XxxGuard(); }` —— 只有构造函数。
 * 3. 因此**唯一缺的东西**就是"真实 Spider 从哪来"。壳原本靠 native 解密
 *    `assets/*.guard` 再用 DexClassLoader 加载；本影子类改为**用给定的 jar / 目录**加载。
 *
 * ── ★ 本方案的前提（务必先确认）──
 * 需要一份**含真实 Spider 实现**的 jar（或 classes 目录）作为 `shimClasses`。
 * 对 `wexguard/shinidie` 这类**把代码加密**的壳，这份东西**不在 jar 里**：
 * 实测 `assets/wexshinidie.guard`（930,055 B）零明文（`com/github/catvod`、
 * `Lcom/`、`catvod`、`dex\n035`、`PK\x03\x04` 全部搜不到），也不是 zlib/gzip
 * （三种 wbits 全部 `incorrect header check`）。**它只能由 ARM native 解密。**
 * 所以本影子类的正确用法是：
 *   · 对**明文实现**的加固 jar（壳只是包装、真实类在 jar 内或随包提供）→ 直接可用；
 *   · 对**代码加密**的壳 → 先用别的手段（ARM 环境一次性取证 / 逆向）拿到解密后的 jar，
 *     再喂给本类。**拿到之后，剩下的全部工作就是本类这点代码。**
 *
 * 配置来源（按优先级）：
 *  1. 系统属性 `tvbox.shellShimClasses`（分号分隔的 jar/目录）
 *  2. 环境变量 `TVBOX_SHELL_SHIM_CLASSES`
 */
public class DexNative {

    /** 与壳里的字段同名同义：DexClassLoader */
    private static ClassLoader loader;

    private static final Map<String, Object> CACHE = new ConcurrentHashMap<>();

    /** 正在构造中的类（每个线程一份），用于打断壳的"自我委托"递归 */
    private static final ThreadLocal<java.util.Set<String>> CONSTRUCTING =
            ThreadLocal.withInitial(java.util.HashSet::new);

    /** 日志开关：`-Dtvbox.shellShim.debug=true` */
    private static boolean debug() {
        return "true".equalsIgnoreCase(System.getProperty("tvbox.shellShim.debug", "false"));
    }

    private static void log(String msg) {
        if (debug()) System.err.println("[ShellShim] " + msg);
    }

    /**
     * 壳的 `Init.init(ctx)` 会调它，返回的 loader 被存进 `Init.loader()`，
     * 之后 `getSpider` 再拿它去 `loadClass`。
     */
    public static synchronized Object getLoader(Object context) {
        if (loader == null) {
            loader = buildLoader();
        }
        // 壳的 Init 自己持有一份 Application（AppSx 等直接用 Init.context() 取
        // SharedPreferences）；它由蜘蛛 jar 的类加载器加载，不是本影子类的 loader。
        // 进入本方法时线程上下文加载器通常正是 SpiderRunner 的 jar 加载器，先记下来。
        ClassLoader callerCl = Thread.currentThread().getContextClassLoader();
        if (context instanceof android.content.Context) {
            ((android.content.Context) context).setClassLoader(loader);
        }
        Thread.currentThread().setContextClassLoader(loader);
        if (!originInitialized) {
            originInitialized = true;
            initProxyOrigin(loader);
            // ★ 真实实现（如 fty）有自己的 Context 单例 InitOrigin，必须用宿主上下文初始化，
            //   否则真实蜘蛛里 InitOrigin.context().getFilesDir()/getSharedPreferences() 会 NPE。
            initOrigin(context);
            // ★ 壳自己的 Init.context() 也要填：真实实现（AppSx / AppTT）会直接用它
            //   取 SharedPreferences，漏掉时 init() 报 getSharedPreferences 接收者为 null。
            initShellInit(context, callerCl);
            // ★ 嗷呜系真实实现（woshinidie）用的是 AwInit.context()（不是 InitOrigin）：
            //   漏掉这一步时所有网盘初始化和蜘蛛 init 都会 NPE「AwInit.context() 为 null」。
            initAwInit(context);
            forceHideUtils();
            log("getLoader -> " + loader);
        }
        return loader;
    }

    /** 把宿主 Application 写进壳的 `com.github.catvod.spider.Init`（AppSx 等的上下文来源）。 */
    private static void initShellInit(Object context, ClassLoader callerCl) {
        if (context == null) return;
        // 可能同时存在两份 Init：蜘蛛 jar 里的壳 Init（BaseSpiderGuard 用），
        // 以及真实实现 jar（foni/fty）里的 Init（AppSx 用）。两份都要初始化。
        ClassLoader[] candidates = new ClassLoader[] {
                loader,
                callerCl,
                context instanceof android.content.Context
                        ? ((android.content.Context) context).getClassLoader()
                        : null,
        };
        java.util.Set<Class<?>> seen = new java.util.HashSet<>();
        for (ClassLoader cl : candidates) {
            if (cl == null || cl == DexNative.class.getClassLoader()) continue;
            Class<?> init;
            try {
                init = Class.forName("com.github.catvod.spider.Init", true, cl);
            } catch (ClassNotFoundException ignored) {
                continue;
            } catch (Throwable t) {
                log("Init 加载失败: " + t);
                continue;
            }
            if (!seen.add(init)) continue;
            try {
                init.getMethod("init", android.content.Context.class).invoke(null, context);
                log("Init.init OK（壳上下文已写入）: " + init.getClassLoader());
                continue;
            } catch (Throwable t) {
                log("Init.init 失败: " + t);
            }
            // init 内部可能依赖额外私有类；按类型直接填 Application 静态字段。
            try {
                for (java.lang.reflect.Field f : init.getDeclaredFields()) {
                    if (java.lang.reflect.Modifier.isStatic(f.getModifiers())
                            && f.getType() == android.app.Application.class) {
                        f.setAccessible(true);
                        f.set(null, context);
                        log("Init.context 已直接注入: " + f.getName());
                    }
                }
            } catch (Throwable ig) {
                log("Init.context 注入失败: " + ig);
            }
        }
    }

    private static boolean originInitialized;

    /** 把真实实现的 ProxyOrigin 绑定到宿主代理的实际端口（没有该类时静默跳过）。 */
    private static void initProxyOrigin(ClassLoader l) {
        try {
            Class<?> c = Class.forName("com.github.catvod.spider.ProxyOrigin", true, l);
            c.getMethod("init").invoke(null);
            log("ProxyOrigin.init OK");
        } catch (ClassNotFoundException ignored) {
            // 该载荷没有 ProxyOrigin（普通 jar / 自带 Proxy）
        } catch (Throwable t) {
            log("ProxyOrigin.init 失败: " + t);
        }
    }

    /** 初始化真实实现的 InitOrigin（若有），把宿主 Application 塞进去。 */
    private static void initOrigin(Object context) {
        if (context == null) return;
        Class<?> io;
        try {
            io = Class.forName("com.github.catvod.spider.InitOrigin", true, loader);
        } catch (ClassNotFoundException ignored) {
            // 该壳没有 InitOrigin（其它壳 / 普通 jar），无影响
            return;
        } catch (Throwable t) {
            log("InitOrigin 加载失败: " + t);
            return;
        }
        try {
            io.getMethod("init", android.content.Context.class).invoke(null, context);
            log("InitOrigin.init OK");
        } catch (Throwable t) {
            Throwable cause = t;
            if (t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null) {
                cause = t.getCause();
            }
            log("InitOrigin.init 失败: " + cause);
            // 签名不匹配 = 随包的真实实现与订阅里的壳版本不是同一代。
            // 继续跑只会得到空内容/难懂的 NPE（饭太硬 AppSx 实测），
            // 抛带 ShellShim 的明确错误，让宿主改用解包 payload 路径。
            if (cause instanceof NoSuchMethodError || cause instanceof NoSuchFieldError) {
                throw new IllegalStateException(
                        "ShellShim 真实实现与壳版本不兼容（InitOrigin 签名不匹配）: " + cause);
            }

            // 真实实现的 init 会顺带做 Rc 解密（依赖宿主私有类），桌面缺这一类必抛；
            // 但绝大多数蜘蛛只需要 InitOrigin.context() 非空 —— 直接把存放 Application 的
            // 静态字段塞进去。字段名在不同构建里是混淆过的，按**类型**找，不按名字。
            try {
                for (java.lang.reflect.Field f : io.getDeclaredFields()) {
                    if (java.lang.reflect.Modifier.isStatic(f.getModifiers())
                            && (f.getType() == android.app.Application.class
                                    || f.getType() == android.content.Context.class)) {
                        f.setAccessible(true);
                        f.set(null, context);
                        log("InitOrigin.context 已直接注入: " + f.getName());
                    }
                }
            } catch (Throwable ig) {
                log("InitOrigin.context 注入失败: " + ig);
            }
            // 有的构建把 Application 放在 InitOrigin 单例的实例字段上（init 内部才赋值）。
            try {
                Object inst = io.getMethod("get").invoke(null);
                if (inst != null) {
                    for (java.lang.reflect.Field f : io.getDeclaredFields()) {
                        if (!java.lang.reflect.Modifier.isStatic(f.getModifiers())
                                && (f.getType() == android.app.Application.class
                                        || f.getType() == android.content.Context.class)) {
                            f.setAccessible(true);
                            f.set(inst, context);
                            log("InitOrigin 实例 context 已注入: " + f.getName());
                        } else if (!java.lang.reflect.Modifier.isStatic(f.getModifiers())
                                && f.getType() == android.app.Activity.class) {
                            // 桌面上没有真实 Activity；部分源（AppSx 系）会拿它取
                            // SharedPreferences，给一个空壳 Activity 让链路走下去。
                            try {
                                Object activity = f.get(inst);
                                if (activity == null) {
                                    f.setAccessible(true);
                                    f.set(inst, android.app.Activity.class.getDeclaredConstructor().newInstance());
                                    log("InitOrigin 实例 activity 已占位: " + f.getName());
                                }
                            } catch (Throwable ig) {
                                log("InitOrigin activity 注入失败: " + ig);
                            }
                        }
                    }
                }
            } catch (Throwable ig) {
                log("InitOrigin 实例注入失败: " + ig);
            }
            try {
                Object got = io.getMethod("context").invoke(null);
                log("InitOrigin.context() 当前值: " + got);
            } catch (Throwable ig) {
                log("InitOrigin.context() 读取失败: " + ig);
            }
        }
    }

    /**
     * 嗷呜系真实实现（woshinidie）的宿主上下文单例是 `AwInit`：
     * 壳解密出来的类全部通过 `AwInit.context()` 取 Application（网盘登录态恢复、
     * 蜘蛛 init、缓存目录）。桌面 shell-shim 直接加载载荷时必须同样调用一次，
     * 否则每个站点都在 init() 里报「AwInit.context() 为 null」。
     */
    private static void initAwInit(Object context) {
        if (context == null) return;
        Class<?> aw;
        try {
            aw = Class.forName("com.github.catvod.spider.AwInit", true, loader);
        } catch (ClassNotFoundException ignored) {
            // 该载荷没有 AwInit（其它壳 / 普通 jar），无影响
            return;
        } catch (Throwable t) {
            log("AwInit 加载失败: " + t);
            return;
        }
        try {
            aw.getMethod("init", android.content.Context.class).invoke(null, context);
            log("AwInit.init OK");
        } catch (Throwable t) {
            Throwable cause = t;
            if (t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null) {
                cause = t.getCause();
            }
            log("AwInit.init 失败: " + cause);
            // init 内部可能依赖 Activity / 权限；按字段类型兜底注入 Application。
            try {
                Object inst = aw.getMethod("get").invoke(null);
                if (inst != null) {
                    for (java.lang.reflect.Field f : aw.getDeclaredFields()) {
                        if (!java.lang.reflect.Modifier.isStatic(f.getModifiers())
                                && f.getType() == android.app.Application.class) {
                            f.setAccessible(true);
                            f.set(inst, context);
                            log("AwInit.context 已直接注入: " + f.getName());
                        }
                    }
                }
            } catch (Throwable ig) {
                log("AwInit.context 注入失败: " + ig);
            }
        }
    }

    /**
     * 桌面侧兜底：真实实现的 Rc 加密（B/Gc/KJ/n）默认走 InitOrigin.i 反射分支，
     * 而 InitOrigin.i 是饭太硬主程序注入的私有类、桌面版无法提供 → 恒 NPE 返回空串。
     * 这里把 merge.cn.yq 置为 true，让 Rc 改走 HideUtils 分支（我们 stub 里的占位实现）。
     *
     * ★ 2026-09-18 默认启用（对照实验：yq=true 后全部 InitOrigin.i NPE 消失，
     *   瓜子 homeVideoContent 回退链正常出内容、荐片分类正常；与 release53 经验
     *   「yq=true 使 Rc 依赖的 fty 源不更差且多数恢复」一致）。
     *   显式设 -Dtvbox.shellShim.forceHideUtils=false 可关闭（对照实验用）。
     *   占位 HideUtils（原串/标准 MD5）未必等价饭太硬私有算法，但至少比 NPE 空串更接近。
     */
    private static void forceHideUtils() {
        if ("false".equalsIgnoreCase(System.getProperty("tvbox.shellShim.forceHideUtils", "true"))) return;
        try {
            Class<?> cn = Class.forName("com.github.catvod.spider.merge.cn", true, loader);
            java.lang.reflect.Field f = cn.getField("yq");
            f.setBoolean(null, true);
            log("已强制 merge.cn.yq=true（走 HideUtils 分支，默认启用）");
        } catch (Throwable t) {
            log("强制 cn.yq 失败: " + t);
        }
    }

    /**
     * 壳的 `Init.getSpider(name)` 会调它。
     * name 形如 `com.github.catvod.spider.NewDouBanGuard`。
     *
     * ★ 关键：请求的类名是 **Guard 壳类**，而真实 Spider 在 shim 包里对应同一个类名。
     *   所以这里先试"从 shimClasses 用同名类加载"；
     *   加载不到再退回"实例化传入的那个 name"。
     */
    @SuppressWarnings("unchecked")
    public static Object getSpider(Object loaderObj, String name) {
        if (name == null) return null;
        Object cached = CACHE.get(name);
        if (cached != null) return cached;

        // ★★ 环检测（本方案最容易踩的坑，实测踩到过）★★
        //   壳的委托链会请求**正在构造中**的那个类：
        //       new NewDouBanGuard() → BaseSpiderGuard.<init> → Init.getSpider("NewDouBanGuard")
        //       → 这里 → new NewDouBanGuard() → ... 无限递归 → StackOverflowError
        //   对"壳类本身"必须直接返回 null：壳的字段留 null 是**合法状态**
        //   （真实实现不在 jar 里时才如此；若 shimClasses 提供了同名真实类，
        //     下面那条 Class.forName 会先命中，根本不会走到这里）。
        String dotted = name.replace('/', '.');
        if (CONSTRUCTING.get().contains(dotted)) {
            log("getSpider(" + dotted + ") 命中环检测 → 返回 null（避免自递归）");
            return null;
        }
        ClassLoader l = loaderObj instanceof ClassLoader ? (ClassLoader) loaderObj : null;
        if (l == null) l = loader;
        if (l == null) l = buildLoader();

        // ★ 先按原类名找**真实实现**；找不到再试"剥掉 Guard 后缀"的名字
        //   （对齐 PlayHub 的 buildClassNameCandidates：`XxxGuard` → `Xxx`）。
        //   真实实现存在于 shimClasses 时这一步就命中，桥就是通的；
        //   全都不命中说明 shimClasses 没提供实现（见错因日志）。
        java.util.List<String> fails = new java.util.ArrayList<>();
        for (String candidate : candidates(dotted)) {
            try {
                Class<?> c = Class.forName(candidate, true, l);
                CONSTRUCTING.get().add(candidate);
                Object spider;
                try {
                    spider = c.getDeclaredConstructor().newInstance();
                } finally {
                    CONSTRUCTING.get().remove(candidate);
                }
                log("getSpider(" + dotted + ") -> " + candidate + " = " + spider);
                CACHE.put(name, spider);
                return spider;
            } catch (Throwable t) {
                log("getSpider 候选 " + candidate + " 未命中: " + t);
                fails.add(candidate + " → " + t);
            }
        }

        // ★★ 2026-09-29：**这一行必须无条件打印**（`[ShellShim]` 前缀会被 App 的
        //   `extractBridgeNotes` 收集上屏）。此前它只在 -Dtvbox.shellShim.debug=true 时打印，
        //   于是设备上「守卫内层蜘蛛为空 → BaseSpiderGuard NPE」时日志里没有任何线索。
        StringBuilder sb = new StringBuilder("getSpider(").append(dotted)
                .append(") 无真实实现可加载 → 返回 null（壳侧守卫字段将留空 → 首个 init() 必 NPE）")
                .append("；shimClasses=").append(System.getProperty("tvbox.shellShimClasses", ""));
        for (String f : fails) sb.append("；候选 ").append(f);
        System.err.println("[ShellShim] " + sb);
        return null;
    }

    /** 候选类名：去壳后缀的真实名 → 首字母小写变体 → 原名（回退） */
    private static java.util.List<String> candidates(String dotted) {
        java.util.List<String> out = new java.util.ArrayList<>();
        int dot = dotted.lastIndexOf('.');
        String pkg = dot < 0 ? "" : dotted.substring(0, dot + 1);
        String simple = dot < 0 ? dotted : dotted.substring(dot + 1);
        String stripped = "";
        if (simple.endsWith("Guard")) {
            stripped = simple.substring(0, simple.length() - "Guard".length());
        } else if (simple.endsWith("Amns")) {
            // 嗷呜系壳（AowuShinidie）：外层类名 `AAConfigAmns`，真实实现是 `AAConfig`。
            stripped = simple.substring(0, simple.length() - "Amns".length());
        } else if (simple.endsWith("DexNative")) {
            stripped = simple.substring(0, simple.length() - "DexNative".length());
        }
        if (!stripped.isEmpty()) {
            // ★ 真实实现在解出来的 jar 里常叫 Xxx（不带 Guard/Amns），而壳 jar 里只放
            //   XxxGuard/XxxAmns 的空壳。父委托会把壳类解析到壳 jar → 拿到空壳，
            //   所以把「去壳后缀的真实名」排在前面，优先命中真实实现。
            out.add(pkg + stripped);
            out.add(pkg + Character.toLowerCase(stripped.charAt(0)) + stripped.substring(1));
        }
        out.add(dotted);
        return out;
    }

    /**
     * 嗷呜系壳（aowu）使用另一套 DexNative 签名：`getLoader(Object, InputStream)`。
     * 桌面只需返回由 shimClasses 构建的加载器；输入流是壳自己解密 lib 用的，忽略。
     */
    public static Object getLoader(Object context, java.io.InputStream in) {
        log("getLoader(context, stream) -> 使用 shimClasses，忽略输入流");
        return getLoader(context);
    }

    /** 嗷呜系壳的弹幕入口（四个参数），桌面不做弹幕：空实现。 */
    public static void getDanmu(Object a, String b, String c, String d) {
        log("getDanmu 桌面空实现");
    }

    /**
     * 代理转发（真实 DexNative 的签名是 `proxyInvoke(Object loader, Object params)`）。
     *
     * 壳的 `com.github.catvod.spider.Proxy.proxy(Map)` 会走
     * `Init.proxyInvoke(Map)` → 本方法；第一个参数是真实实现所在 loader
     * （DexClassLoader），第二个是查询参数。
     * 真实实现里通常有两种处理器，按顺序反射调用：
     *   · `com.github.catvod.spider.Proxy.proxy(Map)`（普通 jar）；
     *   · `com.github.catvod.spider.ProxyOrigin.proxy(Map)`（wex 系壳的 do=hxq / do=pan 等）。
     * 返回值约定 `{status, contentType, InputStream}`。
     */
    @SuppressWarnings("unchecked")
    public static Object[] proxyInvoke(Object loaderObj, Object paramsObj) {
        Map<String, String> params =
                paramsObj instanceof Map ? (Map<String, String>) paramsObj : new java.util.LinkedHashMap<>();
        ClassLoader cl = loaderObj instanceof ClassLoader ? (ClassLoader) loaderObj : loader;
        Throwable last = null;
        for (String name : new String[] {
                "com.github.catvod.spider.Proxy",
                "com.github.catvod.spider.ProxyOrigin"
        }) {
            try {
                Class<?> c = Class.forName(name, true, cl);
                Method m = c.getMethod("proxy", Map.class);
                Object r = m.invoke(null, params);
                if (r instanceof Object[]) return (Object[]) r;
            } catch (Throwable t) {
                last = t;
            }
        }
        String msg = "proxy handler failed: " + (last == null ? "no handler" : String.valueOf(last));
        log(msg);
        return new Object[] { 500, "text/plain; charset=utf-8",
                new java.io.ByteArrayInputStream(msg.getBytes(java.nio.charset.StandardCharsets.UTF_8)) };
    }

    /** 兼容单参数旧签名（部分壳会直接调）。 */
    public static Object[] proxyInvoke(Map<String, String> params) {
        return proxyInvoke(loader, params);
    }

    /**
     * ★ 弹幕启动（真实实现 DexNative 有 danmuStart()/danmuStart(boolean) 两个重载）。
     *   桌面板不做弹幕，但 fty 系网盘蜘蛛的 playerContent 会调用它（加载播放器弹幕），
     *   影子类缺此方法时会抛 NoSuchMethodError 导致 playerContent 整体失败。
     *   给出空实现即可（弹幕关闭，不影响取播放地址）。
     */
    public static void danmuStart() {
        log("danmuStart() 桌面无弹幕，空实现");
    }

    public static void danmuStart(boolean enable) {
        log("danmuStart(" + enable + ") 桌面无弹幕，空实现");
    }

    // ------------------------------------------------------------------

    private static ClassLoader buildLoader() {
        try {
            String spec = System.getProperty("tvbox.shellShimClasses");
            if (spec == null || spec.isBlank()) spec = System.getenv("TVBOX_SHELL_SHIM_CLASSES");
            java.util.List<URL> urls = new java.util.ArrayList<>();
            StringBuilder paths = new StringBuilder();
            if (spec != null && !spec.isBlank()) {
                for (String p : spec.split(";")) {
                    if (p.isBlank()) continue;
                    urls.add(new File(p.trim()).toURI().toURL());
                    if (paths.length() > 0) paths.append(File.pathSeparator);
                    paths.append(p.trim());
                }
            }
            log("shellShimClasses = " + urls);
            // ★ 壳的 `Init.init` 里是 `(DexClassLoader) DexNative.getLoader(ctx)`，
            //   返回**普通 URLClassLoader 会 ClassCastException** —— 必须返回
            //   `dalvik.system.DexClassLoader`（我们 stub 里那个 extends URLClassLoader 的类）。
            URL[] arr = urls.toArray(new URL[0]);
            ClassLoader parent = DexNative.class.getClassLoader();
            try {
                Class<?> dcl = Class.forName("dalvik.system.DexClassLoader", true, parent);
                return (ClassLoader) dcl.getConstructor(String.class, String.class, String.class, ClassLoader.class)
                        .newInstance(paths.toString(), null, null, parent);
            } catch (Throwable t) {
                log("构造 DexClassLoader 失败，回退 URLClassLoader: " + t);
                return new URLClassLoader(arr, parent);
            }
        } catch (Throwable t) {
            log("构建 loader 失败: " + t);
            // ★ 2026-09-29：加载器建不起来 → 真实蜘蛛一个都拿不到 → 守卫字段留空 → NPE。
            //   这条无条件上屏（`[ShellShim]` 前缀会被 App 收集），避免设备侧再次「静默空」。
            System.err.println("[ShellShim] 构建真实实现加载器失败（Guard 内层蜘蛛将不可用）: " + t);
            return new URLClassLoader(new URL[0], DexNative.class.getClassLoader());
        }
    }

    /** 便于诊断：把一个类从 shim loader 里找出来（不实例化） */
    public static Class<?> peek(String name) throws ClassNotFoundException {
        return Class.forName(name, false, loader != null ? loader : buildLoader());
    }

    static {
        log("DexNative 影子类已加载（纯 Java，无 native）");
    }

    // 让 javac 不报未使用告警用的引用（DexClassLoader 是壳的签名类型，保留说明用）
    static {
        if (false) {
            DexClassLoader ignore = null;
            Constructor<?> c = null;
            Method m = null;
        }
    }
}
