import 'proxy_config.dart';

/// Web 版占位：浏览器环境已经由系统/浏览器扩展代理，内置代理不生效。
class ProxyRuntime {
  ProxyRuntime._();
  static final ProxyRuntime instance = ProxyRuntime._();

  ProxyConfig config = const ProxyConfig();

  bool get enabled => false;
  int get bridgePort => 0;
  String get summary => config.summary;

  Future<void> apply(ProxyConfig next) async {
    config = next;
  }

  static bool isLocalHost(String host) => false;

  static void installHttpOverrides() {}

  List<String> get jvmProps => const [];
  Map<String, String> get pythonEnv => const {};

  Future<void> shutdown() async {}
}
