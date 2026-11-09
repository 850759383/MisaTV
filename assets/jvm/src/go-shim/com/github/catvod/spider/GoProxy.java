package com.github.catvod.spider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * 桌面端的 GoProxy 影子类。
 *
 * 加固壳的 Go 代理是 Android ARM .so（多线程取流），桌面 unidbg 明确跳过，
 * 但壳的初始化会阻塞等待它的 /health。这里用纯 Java 起一个同端口的小服务：
 *   · /health 返回 {"state":"ok"}，让壳的 startBlockingForInit 通过；
 *   · 其余请求按标准 HTTP 代理 / 绝对地址 / url= 参数转发，能取数据就取。
 * 只影响壳的 Go 代理，真实蜘蛛的数据请求本身走 okhttp。
 */
public final class GoProxy {

    private static boolean loaded;
    private static final Object LOCK = new Object();
    private static ServerSocket server;
    private static int serverPort;

    private GoProxy() {
    }

    public static boolean a(File file, String name) {
        return file != null;
    }

    private static void deleteTempFiles(File dir) {
        // 桌面不落临时 so，无需清理
    }

    public static void load(File file) {
        loaded = true;
        System.err.println("[go-shim] load " + (file == null ? "null" : file.getAbsolutePath()));
    }

    public static void startServer(String a, String b, String c, boolean d,
                                   String e, String f, String g) {
        int port = parsePort(b);
        if (port <= 0) port = parsePort(g);
        if (port <= 0) port = parsePort(f);
        if (port <= 0) port = parsePort(e);
        System.err.println("[go-shim] startServer port=" + port
                + " dns=" + e + " gateway=" + f);
        start(port);
    }

    private static int parsePort(String value) {
        if (value == null) return 0;
        String s = value.trim();
        if (s.isEmpty()) return 0;
        try {
            int port = Integer.parseInt(s);
            return port > 0 && port < 65536 ? port : 0;
        } catch (Throwable ignored) {
            return 0;
        }
    }

    private static void start(int port) {
        if (port <= 0) {
            System.err.println("[go-shim] no usable port");
            return;
        }
        synchronized (LOCK) {
            if (server != null && !server.isClosed() && serverPort == port) return;
            if (server != null) {
                try {
                    server.close();
                } catch (Throwable ignored) {
                }
                server = null;
            }
            try {
                ServerSocket ss = new ServerSocket();
                ss.setReuseAddress(true);
                ss.bind(new InetSocketAddress("127.0.0.1", port), 64);
                server = ss;
                serverPort = port;
                Thread t = new Thread(new Runnable() {
                    @Override
                    public void run() {
                        acceptLoop();
                    }
                }, "go-shim");
                t.setDaemon(true);
                t.start();
                System.err.println("[go-shim] listening 127.0.0.1:" + port);
            } catch (Throwable t) {
                System.err.println("[go-shim] bind failed: " + t);
            }
        }
    }

    private static void acceptLoop() {
        while (true) {
            ServerSocket current = server;
            if (current == null || current.isClosed()) return;
            try {
                final Socket client = current.accept();
                client.setSoTimeout(20000);
                Thread t = new Thread(new Runnable() {
                    @Override
                    public void run() {
                        handle(client);
                    }
                }, "go-shim-client");
                t.setDaemon(true);
                t.start();
            } catch (Throwable t) {
                if (server == null || server.isClosed()) return;
            }
        }
    }

    private static void handle(Socket client) {
        Socket upstream = null;
        try {
            InputStream in = client.getInputStream();
            OutputStream out = client.getOutputStream();
            String requestLine = readLine(in);
            if (requestLine == null || requestLine.trim().isEmpty()) return;
            String[] parts = requestLine.split(" ");
            if (parts.length < 2) return;
            String method = parts[0];
            String target = parts[1];
            List<String[]> headers = new ArrayList<String[]>();
            String line;
            while ((line = readLine(in)) != null && !line.isEmpty()) {
                int colon = line.indexOf(':');
                if (colon <= 0) continue;
                headers.add(new String[]{
                        line.substring(0, colon).trim(),
                        line.substring(colon + 1).trim()
                });
            }

            if ("CONNECT".equalsIgnoreCase(method)) {
                tunnel(client, target);
                return;
            }

            String url = targetUrl(target);
            if (url == null) {
                writeHealth(out);
                return;
            }

            int contentLength = headerInt(headers, "Content-Length");
            boolean chunked = isChunked(headers);
            URL parsed = new URL(url);
            String protocol = parsed.getProtocol().toLowerCase();
            if (!"http".equals(protocol) && !"https".equals(protocol)) {
                writeHealth(out);
                return;
            }
            String host = parsed.getHost();
            int port = parsed.getPort() > 0
                    ? parsed.getPort()
                    : ("https".equals(protocol) ? 443 : 80);
            if ("https".equals(protocol)) {
                SSLSocket ssl = (SSLSocket) SSLSocketFactory.getDefault()
                        .createSocket();
                ssl.connect(new InetSocketAddress(host, port), 15000);
                ssl.startHandshake();
                upstream = ssl;
            } else {
                upstream = new Socket();
                upstream.connect(new InetSocketAddress(host, port), 15000);
            }
            upstream.setSoTimeout(30000);

            StringBuilder request = new StringBuilder();
            request.append(method).append(' ')
                    .append(pathOf(parsed)).append(" HTTP/1.1\r\n");
            boolean hostHeader = false;
            for (String[] h : headers) {
                String name = h[0];
                if (name.equalsIgnoreCase("Proxy-Connection")
                        || name.equalsIgnoreCase("Proxy-Authorization")
                        || name.equalsIgnoreCase("Connection")) {
                    continue;
                }
                if (name.equalsIgnoreCase("Host")) hostHeader = true;
                request.append(name).append(": ").append(h[1]).append("\r\n");
            }
            if (!hostHeader) request.append("Host: ").append(host).append("\r\n");
            request.append("Connection: close\r\n\r\n");

            OutputStream upOut = upstream.getOutputStream();
            upOut.write(request.toString().getBytes(StandardCharsets.UTF_8));
            copyBody(in, upOut, contentLength, chunked);
            upOut.flush();

            InputStream upIn = upstream.getInputStream();
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = upIn.read(chunk)) > 0) {
                buffer.write(chunk, 0, n);
                if (buffer.size() > 32 * 1024 * 1024) break;
            }
            out.write(buffer.toByteArray());
            out.flush();
        } catch (Throwable t) {
            try {
                OutputStream out = client.getOutputStream();
                writeError(out, t);
            } catch (Throwable ignored) {
            }
        } finally {
            closeQuietly(upstream);
            closeQuietly(client);
        }
    }

    /** 返回真正要转发的 URL；不是代理请求则返回 null（走 /health）。 */
    private static String targetUrl(String target) {
        if (target == null) return null;
        String t = target.trim();
        if (t.startsWith("http://") || t.startsWith("https://")) {
            int q = t.indexOf('?');
            return q >= 0 ? t.substring(0, q) : t;
        }
        if (t.startsWith("/")) {
            int q = t.indexOf('?');
            if (q < 0) return null;
            String query = t.substring(q + 1);
            for (String pair : query.split("&")) {
                int eq = pair.indexOf('=');
                if (eq <= 0) continue;
                String key = pair.substring(0, eq).trim().toLowerCase();
                if (!"url".equals(key) && !"u".equals(key)
                        && !"target".equals(key) && !"link".equals(key)) {
                    continue;
                }
                try {
                    String value = URLDecoder.decode(
                            pair.substring(eq + 1), "UTF-8");
                    if (value.startsWith("http://") || value.startsWith("https://")) {
                        return value;
                    }
                } catch (Throwable ignored) {
                }
            }
        }
        return null;
    }

    private static String pathOf(URL url) {
        String file = url.getFile();
        if (file == null || file.isEmpty()) file = "/";
        return file;
    }

    private static void copyBody(InputStream in, OutputStream out,
                                 int contentLength, boolean chunked)
            throws Exception {
        if (contentLength > 0) {
            byte[] data = new byte[contentLength];
            int offset = 0;
            while (offset < contentLength) {
                int n = in.read(data, offset, contentLength - offset);
                if (n <= 0) break;
                offset += n;
            }
            out.write(data, 0, offset);
            return;
        }
        if (!chunked) return;
        // chunked：原样搬运到结尾的 0 块
        while (true) {
            String sizeLine = readLine(in);
            if (sizeLine == null) return;
            out.write((sizeLine + "\r\n").getBytes(StandardCharsets.UTF_8));
            int semi = sizeLine.indexOf(';');
            String hex = (semi >= 0 ? sizeLine.substring(0, semi) : sizeLine).trim();
            int size;
            try {
                size = Integer.parseInt(hex, 16);
            } catch (Throwable t) {
                return;
            }
            if (size <= 0) {
                String trailer;
                while ((trailer = readLine(in)) != null) {
                    out.write((trailer + "\r\n").getBytes(StandardCharsets.UTF_8));
                    if (trailer.isEmpty()) break;
                }
                return;
            }
            byte[] data = new byte[size];
            int offset = 0;
            while (offset < size) {
                int n = in.read(data, offset, size - offset);
                if (n <= 0) return;
                offset += n;
            }
            out.write(data, 0, size);
            String end = readLine(in);
            if (end != null) out.write((end + "\r\n").getBytes(StandardCharsets.UTF_8));
        }
    }

    private static void tunnel(Socket client, String hostPort) throws Exception {
        int colon = hostPort.lastIndexOf(':');
        if (colon <= 0) return;
        String host = hostPort.substring(0, colon);
        int port = Integer.parseInt(hostPort.substring(colon + 1));
        final Socket upstream = new Socket();
        upstream.connect(new InetSocketAddress(host, port), 15000);
        upstream.setSoTimeout(0);
        OutputStream out = client.getOutputStream();
        out.write("HTTP/1.1 200 Connection Established\r\n\r\n".getBytes(StandardCharsets.UTF_8));
        out.flush();
        pump(client, upstream);
        pump(upstream, client);
    }

    private static void pump(final Socket from, final Socket to) {
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    InputStream in = from.getInputStream();
                    OutputStream out = to.getOutputStream();
                    byte[] data = new byte[8192];
                    int n;
                    while ((n = in.read(data)) > 0) {
                        out.write(data, 0, n);
                        out.flush();
                    }
                } catch (Throwable ignored) {
                } finally {
                    closeQuietly(from);
                    closeQuietly(to);
                }
            }
        }, "go-shim-tunnel");
        t.setDaemon(true);
        t.start();
    }

    private static void writeHealth(OutputStream out) throws Exception {
        String body = "{\"state\":\"ok\",\"ok\":true,\"Code\":0,\"code\":0,\"port\":"
                + serverPort + "}";
        byte[] data = body.getBytes(StandardCharsets.UTF_8);
        String head = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Content-Length: " + data.length + "\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.UTF_8));
        out.write(data);
        out.flush();
    }

    private static void writeError(OutputStream out, Throwable t) throws Exception {
        String body = "{\"state\":\"error\",\"message\":\""
                + escape(String.valueOf(t)) + "\"}";
        byte[] data = body.getBytes(StandardCharsets.UTF_8);
        String head = "HTTP/1.1 502 Bad Gateway\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Content-Length: " + data.length + "\r\n"
                + "Connection: close\r\n\r\n";
        out.write(head.getBytes(StandardCharsets.UTF_8));
        out.write(data);
        out.flush();
    }

    private static String escape(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\r", " ").replace("\n", " ");
    }

    private static int headerInt(List<String[]> headers, String name) {
        for (String[] h : headers) {
            if (h[0].equalsIgnoreCase(name)) {
                try {
                    return Integer.parseInt(h[1].trim());
                } catch (Throwable ignored) {
                    return 0;
                }
            }
        }
        return 0;
    }

    private static boolean isChunked(List<String[]> headers) {
        for (String[] h : headers) {
            if (h[0].equalsIgnoreCase("Transfer-Encoding")
                    && h[1].toLowerCase().contains("chunked")) {
                return true;
            }
        }
        return false;
    }

    /** 逐字节读一行，避免 BufferedReader 预读把请求体吃掉。 */
    private static String readLine(InputStream in) throws Exception {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        while (true) {
            int c = in.read();
            if (c < 0) return buffer.size() == 0 ? null : buffer.toString("UTF-8");
            if (c == '\n') break;
            if (c == '\r') continue;
            buffer.write(c);
        }
        return buffer.toString("UTF-8");
    }

    private static void closeQuietly(Socket socket) {
        if (socket == null) return;
        try {
            socket.close();
        } catch (Throwable ignored) {
        }
    }
}
