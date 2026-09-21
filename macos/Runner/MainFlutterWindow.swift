import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  /// 主窗口引用：Dock reopen 时唤出主窗口（TC-42）。
  /// 歌词条是常驻可见窗口，会使系统 reopen 事件的 hasVisibleWindows
  /// 恒为 true，系统/基类认为「app 已有可见窗口」而不自动唤出主窗口，
  /// 因此需在 AppDelegate 里显式 orderFront（见开发心得坑 15）。
  static weak var mainInstance: MainFlutterWindow?

  /// Dock 图标点击（reopen）：把主窗口带到前面并成为 key。
  /// makeKeyAndOrderFront 对最小化窗口会先解除最小化，对被 close 的
  /// 窗口会重新显示，均符合「唤出主窗口」的预期；幂等无害。
  static func bringMainToFront() {
    mainInstance?.makeKeyAndOrderFront(nil)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 桌面歌词：子窗口创建即注册插件并套用歌词条窗口形态。
    // （desktop_multi_window 官方示例模式 + 置顶透明无焦点条定制，
    //  详见《需求文档/08_桌面歌词.md》与开发方案。）
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // FlutterView 实例化时自绘黑色背景，只把窗口设 clear 不够——
      // 必须同时清掉控制器背景，窗口级透明才真正生效（见开发心得坑 10）。
      controller.backgroundColor = .clear
      // 悬停事件：FlutterViewController 默认 mouseTrackingMode 为
      // InActiveApp，hover 事件只在 app 激活时投递 —— 而歌词条为
      // nonactivating 窗口，app 永远 inactive，导致悬停完全不生效
      // （点击因 mouseDown 不受过滤仍会到达，framework 收到 PointerAdd
      // 触发 onEnter 后丢失 onExit，表现为「点击后卡住不消失」）。
      // 设为 always 使 hover 不依赖窗口/app 焦点（需求 §3.4，TC-43；
      // 见开发心得坑 14，上游 flutter/flutter#165073、#185426）。
      controller.mouseTrackingMode = .always
      RegisterGeneratedPlugins(registry: controller)
      // FlutterViewController 是 NSViewController：窗口须经 view.window 获取
      // （此刻 contentViewController 已挂载，view 必在窗口层级内）。
      guard let window = controller.view.window else { return }
      Self.applyLyricBarWindowStyle(window)

      // orderFront：显示歌词条但不夺取焦点
      //（window_show / windowManager.show() 都会 NSApp.activate，弃用）。
      let channel = FlutterMethodChannel(
        name: "zeromusic/lyric_window",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "orderFront":
          window.orderFront(nil)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.awakeFromNib()
  }

  /// 歌词条窗口形态：透明、无边框、置顶、不激活 app、不进 Dock、跨 Space。
  private static func applyLyricBarWindowStyle(_ window: NSWindow) {
    // borderless 默认不可成为 key 窗口；.nonactivatingPanel 让点击歌词条
    // 不激活整个 app —— 否则 AppKit 激活后 arrangeInFront 会把主窗口也
    // 带到最前，破坏「歌词条置顶与主窗口置顶完全独立」的需求（TC-41）。
    window.styleMask = [.borderless, .nonactivatingPanel]
    window.isOpaque = false // 背景完全透明
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .floating // 始终置顶（NSFloatingWindowLevel）
    // 跨 Space / 全屏应用上方仍显示。
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    // 主窗口失活时歌词条不隐藏。
    window.hidesOnDeactivate = false
    // 拖动由 Flutter 侧 startDragging 驱动，不依赖背景拖拽。
    window.isMovableByWindowBackground = false
  }
}
