/// Web 预览版无法控制系统休眠：全部空实现。
class SleepInhibitor {
  SleepInhibitor._();

  static void acquire() {}

  static void release() {}

  static void releaseAll() {}
}
