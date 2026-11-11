import 'proxy_config.dart';

/// Web 版占位：浏览器环境已经由系统/浏览器扩展代理，内置代理不生效。
class ProxyRuntime {
  ProxyRuntime._();
  static final ProxyRuntime instance = ProxyRuntime._();

  ProxyConfig config = const ProxyConfig();

  bool get enabled => false;
  int get bridgePort => 0;
  bool get followingSystem => false;
  String get summary => config.summary;

  Future<bool> isReachable(String host, int port) async => false;

  Future<void> apply(ProxyConfig next) async {
    config = next;
  }

  static bool isLocalHost(String host) => false;

  static void installHttpOverrides() {}

  Future<List<String>> diagnose() async => const ['Web 版不支持代理自检'];

  List<String> get jvmProps => const [];
  Map<String, String> get pythonEnv => const {};

  Future<void> shutdown() async {}
}
