import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Dock 图标点击（reopen）：显式唤出主窗口（TC-42）。
  ///
  /// 歌词条开着时它就是常驻可见窗口，hasVisibleWindows 恒为 true，
  /// 系统/基类认为「app 已有可见窗口」而不把主窗口带到前面，表现
  /// 为「点 Dock 无反应」（见开发心得坑 15）。该方法在 engine 的
  /// FlutterAppDelegate 生命周期协议中已声明，Swift 需 override 覆盖；
  /// 返回 true 走系统默认后续处理。
  @objc(applicationShouldHandleReopen:hasVisibleWindows:)
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    MainFlutterWindow.bringMainToFront()
    return true
  }
}
