package com.github.catvod.spider;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * 嗷呜系壳（AowuShinidie / `awenc`）的 MyCrypto **纯 Java 影子类**。
 *
 * 壳的真实实现把 md5 / sha / hmac / AES 等放进了 ARM 库（`assets/awenc-v7.so` /
 * `awenc-v8.so`）。桌面 JVM 是 x64，ARM 库的 JNI_OnLoad 走不通时，所有站点在
 * 静态初始化阶段就会报「载荷桥未就绪或未登记方法」（已登记载荷库为空）。
 *
 * 这里覆盖标准算法（MD5 / SHA-1 / SHA-256 / HMAC / AES-ECB / AES-CBC），
 * 其余专有算法（extDe / MyXo / ngrSign…）仍转给原生桥，只有真的用到它们时才失败。
 *
 * 方法签名必须与壳里的 native 声明**完全一致**（调用方按名称+描述符解析）。
 */
public final class MyCrypto {

    /** 壳的 `AwInit.init` 会读这个静态字段（原类 ConstantValue = 0），缺了会 NoSuchFieldError。 */
    public static final int o0OoO0oO0oOoO0O0oO = 0;

    private MyCrypto() {}

    // ---------------------------------------------------------------- 标准摘要

    public static byte[] md5(byte[] data) {
        return digest("MD5", data);
    }

    public static byte[] sha1(byte[] data) {
        return digest("SHA-1", data);
    }

    public static byte[] sha256(byte[] data) {
        return digest("SHA-256", data);
    }

    private static byte[] digest(String algorithm, byte[] data) {
        try {
            return MessageDigest.getInstance(algorithm).digest(data == null ? new byte[0] : data);
        } catch (Exception e) {
            throw new IllegalStateException("MyCrypto " + algorithm + " 失败: " + e, e);
        }
    }

    public static byte[] hmacSha1(byte[] key, byte[] data) {
        return hmac("HmacSHA1", key, data);
    }

    public static byte[] hmacSha256(byte[] key, byte[] data) {
        return hmac("HmacSHA256", key, data);
    }

    private static byte[] hmac(String algorithm, byte[] key, byte[] data) {
        try {
            Mac mac = Mac.getInstance(algorithm);
            mac.init(new SecretKeySpec(key == null ? new byte[0] : key, algorithm));
            return mac.doFinal(data == null ? new byte[0] : data);
        } catch (Exception e) {
            throw new IllegalStateException("MyCrypto " + algorithm + " 失败: " + e, e);
        }
    }

    // ---------------------------------------------------------------- AES

    public static byte[] aesEcbDecrypt(byte[] data, byte[] key) {
        return cipher("AES/ECB/PKCS5Padding", Cipher.DECRYPT_MODE, key, null, data);
    }

    public static byte[] aesEcbEncrypt(byte[] data, byte[] key) {
        return cipher("AES/ECB/PKCS5Padding", Cipher.ENCRYPT_MODE, key, null, data);
    }

    public static byte[] aesCbcDecrypt(byte[] data, byte[] key, byte[] iv) {
        return cipher("AES/CBC/PKCS5Padding", Cipher.DECRYPT_MODE, key, iv, data);
    }

    public static byte[] aesCbcEncrypt(byte[] data, byte[] key, byte[] iv) {
        return cipher("AES/CBC/PKCS5Padding", Cipher.ENCRYPT_MODE, key, iv, data);
    }

    private static byte[] cipher(String transformation, int mode, byte[] key, byte[] iv, byte[] data) {
        try {
            Cipher cipher = Cipher.getInstance(transformation);
            cipher.init(
                    mode,
                    new SecretKeySpec(key, "AES"),
                    iv == null ? null : new IvParameterSpec(iv));
            return cipher.doFinal(data == null ? new byte[0] : data);
        } catch (Exception e) {
            throw new IllegalStateException("MyCrypto " + transformation + " 失败: " + e, e);
        }
    }

    // ------------------------------------------------ 专有算法（转交原生桥）

    public static byte[] MyXo(byte[] a) {
        return nativeCall("MyXo", "([B)[B", a);
    }

    public static byte[] TSaowu(byte[] a, String b) {
        return nativeCall("TSaowu", "([BLjava/lang/String;)[B", a, b);
    }

    public static byte[] awSign(byte[] a, String b) {
        return nativeCall("awSign", "([BLjava/lang/String;)[B", a, b);
    }

    public static byte[] czlc(byte[] a) {
        return nativeCall("czlc", "([B)[B", a);
    }

    public static byte[] extDe(String a) {
        // 这是嗷呜壳的专有解密（hex → 原生流密码），没有可移植的 Java 实现。
        // 仍转给载荷桥；桌面未装载 awenc 原生库时会给出明确错误（不再报「载荷桥未就绪」）。
        return nativeCall("extDe", "(Ljava/lang/String;)[B", a);
    }

    public static byte[] fsDec(byte[] a, String b, String c) {
        return nativeCall("fsDec", "([BLjava/lang/String;Ljava/lang/String;)[B", a, b, c);
    }

    public static byte[] get(byte[] a) {
        // 载荷里所有 `MyCrypto.get(...)` 的返回值都被直接丢弃（pop），它是原生侧的
        // 「预热/初始化」调用。桌面没有对应原生实现，返回空数组即可，不阻断业务。
        return new byte[0];
    }

    public static byte[] huyaWs(byte[] a, String b) {
        return nativeCall("huyaWs", "([BLjava/lang/String;)[B", a, b);
    }

    public static byte[] huyaWup(byte[] a, String b) {
        return nativeCall("huyaWup", "([BLjava/lang/String;)[B", a, b);
    }

    public static byte[] hxqSign(int a, byte[] b, String c) {
        return nativeCall("hxqSign", "(I[BLjava/lang/String;)[B", a, b, c);
    }

    public static byte[] ngrSign(String a, byte[] b, String c) {
        return nativeCall("ngrSign", "(Ljava/lang/String;[BLjava/lang/String;)[B", a, b, c);
    }

    public static byte[] v7d(byte[] a, byte[] b, String c, String d, String e) {
        return nativeCall("v7d", "([B[BLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)[B", a, b, c, d, e);
    }

    public static byte[] v7e(byte[] a, byte[] b, byte[] c, String d) {
        return nativeCall("v7e", "([B[B[BLjava/lang/String;)[B", a, b, c, d);
    }

    public static void rungo(String a, String b, String c) {
        try {
            nativeInvoke("rungo", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", a, b, c);
        } catch (IllegalStateException e) {
            throw e;
        }
    }

    public static void o0OoO0oO0oOoO0O0oO(String a, String b) {
        nativeInvoke("o0OoO0oO0oOoO0O0oO", "(Ljava/lang/String;Ljava/lang/String;)V", a, b);
    }

    private static byte[] nativeCall(String name, String signature, Object... args) {
        Object r = nativeInvoke(name, signature, args);
        return r instanceof byte[] ? (byte[]) r : null;
    }

    private static Object nativeInvoke(String name, String signature, Object... args) {
        ensureNativeLoaded();
        try {
            Class<?> bridge = Class.forName("com.winbox.nativebridge.NativeBridge");
            Method invoke = bridge.getMethod(
                    "invokePayload",
                    String.class, String.class, String.class, Object[].class);
            return invoke.invoke(null, "com/github/catvod/spider/MyCrypto", name, signature, args);
        } catch (Throwable t) {
            Throwable cause = t;
            while (cause.getCause() != null && cause instanceof java.lang.reflect.InvocationTargetException) {
                cause = cause.getCause();
            }
            throw new IllegalStateException(
                    "MyCrypto." + name + " 需要加固壳原生库（桌面未装载）：" + cause, cause);
        }
    }

    /**
     * 嗷呜的加密实现 `awenc-v7.so` 是 ARM32 ELF，桌面 x64 JVM 不能直接
     * `System.load`；这里在第一次调用专有方法前把它装进 native-bridge 的
     * 32 位载荷 VM，注册 extDe/TSaowu 等 JNI 方法。加载失败仍回落到原来的
     * 明确错误（不会静默返回错数据）。
     */
    private static volatile boolean nativeLoadAttempted;

    private static void ensureNativeLoaded() {
        if (nativeLoadAttempted) return;
        synchronized (MyCrypto.class) {
            if (nativeLoadAttempted) return;
            nativeLoadAttempted = true;
            try {
                List<File> cryptLibs = new ArrayList<File>();
                List<File> shellLibs = new ArrayList<File>();

                // 1) 载荷自带 awenc / awdm（嗷呜主源走这里）。
                File bundledCrypt = extractBundledLib("awenc-v7.so");
                if (bundledCrypt != null) addIfMissing(cryptLibs, bundledCrypt);
                File bundledShell = extractBundledLib("awdm-v7.so");
                if (bundledShell != null) addIfMissing(shellLibs, bundledShell);

                // 2) 旧路径：壳落盘的 woshinidie.jar 里的 awdm。
                File legacyShell = extractShellLib("awdm-v7.so");
                if (legacyShell != null) addIfMissing(shellLibs, legacyShell);

                // 3) 其它嗷呜系订阅接口：载荷不一定带 assets，但壳运行时会把自己的
                //    awenc / awdm 以随机文件名写进 spider cache / native work。
                //    按 ELF 头识别后收进来，复用同一套加载序列。
                collectCachedNativeLibs(cryptLibs, shellLibs);

                if (cryptLibs.isEmpty() && shellLibs.isEmpty()) return;

                List<File> candidates = new ArrayList<File>();
                // 沿用嗷呜验证过的顺序：加密库 → 壳库（壳库点亮 awenc 的环境自检）
                // → 换名重试加密库（避免 loader 复用第一次失败的模块）。
                for (File lib : cryptLibs) candidates.add(lib);
                for (File lib : shellLibs) candidates.add(lib);
                for (File lib : cryptLibs) {
                    File retry = copyForReload(lib);
                    if (retry != null) addIfMissing(candidates, retry);
                }

                Class<?> bridge = Class.forName("com.winbox.nativebridge.NativeBridge");
                Throwable last = null;
                for (File lib : candidates) {
                    try {
                        if (loadCryptoLib(bridge, lib)) {
                            System.err.println("[MisaTV] aowu native loaded: " + lib);
                            return;
                        }
                        last = new IllegalStateException("JNI_OnLoad 未登记该库");
                        System.err.println("[MisaTV] aowu native candidate failed: "
                                + lib + " -> 未登记（库内环境校验可能拒绝装载）");
                    } catch (Throwable t) {
                        Throwable cause = t;
                        while (cause instanceof java.lang.reflect.InvocationTargetException
                                && cause.getCause() != null) {
                            cause = cause.getCause();
                        }
                        last = cause;
                        System.err.println("[MisaTV] aowu native candidate failed: "
                                + lib + " -> " + cause);
                    }
                }
                if (last != null) last.printStackTrace();
            } catch (Throwable t) {
                System.err.println("[MisaTV] aowu native load failed: " + t);
            }
        }
    }

    /**
     * 扫描 spider cache / native work 里壳自己落盘的 32 位 ELF：
     * `.awenso*` 是 awenc 加密库，`.aowu*` 是 awdm 壳库。
     * 这两个前缀来自嗷呜壳的运行时约定，其它嗷呜系订阅接口同样适用。
     */
    private static void collectCachedNativeLibs(List<File> cryptLibs, List<File> shellLibs) {
        List<File> roots = new ArrayList<File>();
        String cache = System.getProperty("tvbox.spiderCacheDir", "");
        if (!cache.isEmpty()) roots.add(new File(cache, "cache"));
        String work = System.getProperty("tvbox.native.work", "");
        if (!work.isEmpty()) roots.add(new File(work));
        for (File root : roots) scanCachedLibs(root, cryptLibs, shellLibs, 0);
    }

    /** 只递归几层；跳过动辄上千文件的点播切片目录，避免拖慢首次 native 调用。 */
    private static void scanCachedLibs(
            File dir, List<File> cryptLibs, List<File> shellLibs, int depth) {
        if (dir == null || depth > 4) return;
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                if ("vod_chunk_session".equals(f.getName())) continue;
                scanCachedLibs(f, cryptLibs, shellLibs, depth + 1);
                continue;
            }
            String name = f.getName();
            if (!name.startsWith(".awenso") && !name.startsWith(".aowu")) continue;
            if (f.length() < 16 * 1024) continue;
            int kind = elf32Kind(f);
            if (kind == 1) {
                addIfMissing(cryptLibs, stageCachedLib(f, "awenc-v7.so"));
            } else if (kind == 2) {
                addIfMissing(shellLibs, stageCachedLib(f, "awdm-v7.so"));
            }
        }
    }

    /** 1 = awenc 加密库，2 = awdm 壳库，0 = 不是 32 位 ARM ELF。 */
    private static int elf32Kind(File file) {
        java.io.RandomAccessFile raf = null;
        try {
            raf = new java.io.RandomAccessFile(file, "r");
            byte[] head = new byte[5];
            raf.readFully(head);
            if (head[0] != 0x7f || head[1] != 'E' || head[2] != 'L' || head[3] != 'F') {
                return 0;
            }
            if (head[4] != 1) return 0;
            String name = file.getName();
            if (name.startsWith(".awenso")) return 1;
            if (name.startsWith(".aowu")) return 2;
            return 0;
        } catch (Throwable t) {
            return 0;
        } finally {
            if (raf != null) {
                try {
                    raf.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    /** 用壳里同样的文件名落一份临时副本，保持和 awenc/awdm 原始模块名一致。 */
    private static File stageCachedLib(File src, String name) {
        try {
            File out = new File(System.getProperty("java.io.tmpdir", "."), "misa-aowu-" + name);
            if (!out.isFile() || out.length() != src.length()) {
                InputStream in = new FileInputStream(src);
                FileOutputStream fos = new FileOutputStream(out);
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) >= 0) {
                    fos.write(buffer, 0, read);
                }
                fos.close();
                in.close();
            }
            return out;
        } catch (Throwable t) {
            System.err.println("[MisaTV] aowu stage " + src + " failed: " + t);
            return src;
        }
    }

    private static void addIfMissing(List<File> list, File file) {
        if (file == null) return;
        String path = file.getAbsolutePath();
        for (File f : list) {
            if (path.equals(f.getAbsolutePath())) return;
        }
        list.add(file);
    }

    /**
     * 载荷 jar 里自带真正的加密原生库（`assets/awenc-v7.so` / `v8.so`）。
     * `tvbox.shellShimClasses` 指向的就是带 assets 的载荷 shim jar；
     * 找不到时再扫 `jvm_cache/payloads` 下的原始 payload jar。
     */
    private static File extractBundledLib(String name) {
        List<File> jars = new ArrayList<File>();
        String spec = System.getProperty("tvbox.shellShimClasses", "");
        for (String part : spec.split(";")) {
            String path = part.trim();
            if (path.isEmpty()) continue;
            File file = new File(path);
            if (file.isFile()) {
                jars.add(file);
            } else if (file.isDirectory()) {
                File direct = new File(file, "assets/" + name);
                if (direct.isFile()) return direct;
            }
        }
        String cache = System.getProperty("tvbox.spiderCacheDir", "");
        if (!cache.isEmpty()) {
            File parent = new File(cache).getParentFile();
            if (parent != null) collectJars(new File(parent, "payloads"), jars, 0);
        }
        for (File jar : jars) {
            File out = extractZipEntry(jar, name);
            if (out != null) return out;
        }
        return null;
    }

    /**
     * 手动把 awenc 装进壳的 32 位载荷 VM。`bridgeLoad` 在 32 位路径下会先
     * `ensureInit`，而壳的 jar 里没有桥自身的 ARM .so；这里直接复用已经建好的
     * payloadVm，loadLibrary 后自己调 JNI_OnLoad，natives 就登记在同一 VM 里，
     * `invokePayload` 能直接命中。
     */
    private static boolean loadCryptoLib(Class<?> bridge, File lib) throws Exception {
        Method ensure = bridge.getDeclaredMethod("ensurePayloadVm");
        ensure.setAccessible(true);
        ensure.invoke(null);
        Field vmField = bridge.getDeclaredField("payloadVm");
        vmField.setAccessible(true);
        Field emulatorField = bridge.getDeclaredField("payloadEmulator");
        emulatorField.setAccessible(true);
        Object vm = vmField.get(null);
        Object emulator = emulatorField.get(null);
        Object dalvikModule = vm.getClass()
                .getMethod("loadLibrary", File.class, boolean.class)
                .invoke(vm, lib, true);
        Class<?> emulatorClass = Class.forName(
                "com.github.unidbg.Emulator", true, bridge.getClassLoader());
        dalvikModule.getClass()
                .getMethod("callJNI_OnLoad", emulatorClass)
                .invoke(dalvikModule, emulator);
        try {
            bridge.getMethod(
                    "invokePayload", String.class, String.class, String.class, Object[].class)
                    .invoke(null, "com/github/catvod/spider/MyCrypto", "md5", "([B)[B",
                            new Object[]{new byte[0]});
            return true;
        } catch (Throwable t) {
            Throwable cause = t;
            while (cause.getCause() != null && cause instanceof java.lang.reflect.InvocationTargetException) {
                cause = cause.getCause();
            }
            System.err.println("[MisaTV] aowu md5 probe failed: " + cause);
            return false;
        }
    }

    /** 从壳落盘的 `woshinidie.jar` 里取出 awdm v7/v8 原生库。 */
    private static File extractShellLib(String name) {
        try {
            String cache = System.getProperty("tvbox.spiderCacheDir", "");
            if (cache.isEmpty()) return null;
            File jar = new File(cache, "files/aowu/woshinidie.jar");
            if (!jar.isFile()) return null;
            return extractZipEntry(jar, name);
        } catch (Throwable t) {
            System.err.println("[MisaTV] aowu extract " + name + " failed: " + t);
            return null;
        }
    }

    /** 复制一份换名的库文件，让 unidbg 重新执行一次 loadLibrary/JNI_OnLoad。 */
    private static File copyForReload(File src) {
        try {
            File out = new File(System.getProperty("java.io.tmpdir", "."),
                    "misa-aowu-reload-" + System.nanoTime() + "-" + src.getName());
            InputStream in = new FileInputStream(src);
            FileOutputStream fos = new FileOutputStream(out);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) >= 0) {
                fos.write(buffer, 0, read);
            }
            fos.close();
            in.close();
            return out;
        } catch (Throwable t) {
            System.err.println("[MisaTV] aowu copy for reload failed: " + t);
            return null;
        }
    }

    private static void collectJars(File dir, List<File> out, int depth) {
        if (dir == null || depth > 3) return;
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                collectJars(f, out, depth + 1);
            } else if (f.getName().endsWith(".jar")) {
                out.add(f);
            }
        }
    }

    private static File extractZipEntry(File jar, String name) {
        try {
            ZipFile zip = new ZipFile(jar);
            try {
                ZipEntry entry = zip.getEntry("assets/" + name);
                if (entry == null) entry = zip.getEntry(name);
                if (entry == null) return null;
                File out = new File(
                        System.getProperty("java.io.tmpdir", "."),
                        "misa-aowu-" + name);
                if (!out.isFile()
                        || (entry.getSize() >= 0 && out.length() != entry.getSize())) {
                    InputStream in = zip.getInputStream(entry);
                    FileOutputStream fos = new FileOutputStream(out);
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = in.read(buffer)) >= 0) {
                        fos.write(buffer, 0, read);
                    }
                    fos.close();
                    in.close();
                }
                return out;
            } finally {
                zip.close();
            }
        } catch (Throwable t) {
            System.err.println("[MisaTV] aowu extract " + jar + "!" + name + " failed: " + t);
            return null;
        }
    }

    // 让 javac 不报未使用告警用的引用
    static {
        if (false) {
            Arrays.hashCode(new byte[0]);
            StandardCharsets.UTF_8.name();
        }
    }
}
