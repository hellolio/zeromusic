import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  /// 主窗口引用：Dock reopen 时唤出主窗口（TC-42）。
  /// 歌词条是常驻可见窗口，会使系统 reopen 事件的 hasVisibleWindows
  /// 恒为 true，系统/基类认为「app 已有可见窗口」而不自动唤出主窗口，
  /// 因此需在 AppDelegate 里显式 orderFront（见开发心得坑 15）。
  /// 必须在 awakeFromNib 里赋值：static 属性不会自动连线，漏赋值会让
  /// bringMainToFront 变成空操作（坑 17）。
  static weak var mainInstance: MainFlutterWindow?

  /// 歌词条 NSPanel 强引用：panel 未上屏时 AppKit 不持有它，
  /// 弱引用会被释放（窗口销毁后 FlutterView 无处渲染）。
  static var lyricPanel: NSPanel?

  /// Dock 图标点击（reopen）：把主窗口带到前面并成为 key。
  /// 注意：makeKeyAndOrderFront **不会**解除最小化（坑 17），最小化态
  /// 必须走 deminiaturize（带动画恢复并置前）；其余情况
  /// makeKeyAndOrderFront 即可（被 close 的窗口会重新显示），幂等无害。
  static func bringMainToFront() {
    guard let main = mainInstance else { return }
    if main.isMiniaturized {
      main.deminiaturize(nil)
    } else {
      main.makeKeyAndOrderFront(nil)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    Self.mainInstance = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 桌面歌词：子窗口创建即注册插件并把 FlutterView 迁入真正的 NSPanel
    // （透明无边框置顶不抢焦点，详见《需求文档/08_桌面歌词.md》与开发心得
    //  坑 10 / 14 / 16）。
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
      Self.hostLyricBar(controller: controller)
    }

    super.awakeFromNib()
  }

  /// 把 desktop_multi_window 创建的载体窗口（普通 NSWindow）的
  /// FlutterView 迁入自建 NSPanel（坑 16）。
  ///
  /// `.nonactivatingPanel` 样式位只对 NSPanel（及其子类）生效；
  /// desktop_multi_window 创建的是普通 NSWindow，该位被 AppKit 直接
  /// 忽略 → 点击歌词条会激活 app，激活时整组窗口（含主窗口）被带到
  /// 最前（TC-41 失效根因）。自建真 NSPanel 后：
  /// - window_manager 按 `registrar.view?.window` 每次现算解析窗口，
  ///   子窗口 Dart 侧的所有窗口操作自动落到新 panel，零改动；
  /// - desktop_multi_window 的消息通道是引擎级（按 windowId 路由），
  ///   与视图所在窗口无关，推送/回传不受迁移影响；
  /// - 载体窗口只藏不关：willCloseNotification 会触发插件
  ///   removeWindow，且其 contentViewController 仍持有控制器，
  ///   插件的 occlusion 转发（激活态变更 → 引擎）依赖它。
  private static func hostLyricBar(controller: FlutterViewController) {
    guard let carrier = controller.view.window else { return }
    let panel = NSPanel(
      contentRect: carrier.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    // 把 FlutterView 迁入 panel（contentView 只能属于一个窗口，
    // 赋值即从载体窗口摘除）；随后按载体 frame 复位，防止
    // contentViewController 赋值引发的尺寸自适应闪变。
    panel.contentViewController = controller
    panel.setFrame(carrier.frame, display: false)
    applyLyricBarWindowStyle(panel)
    carrier.orderOut(nil)
    lyricPanel = panel

    // orderFront：显示歌词条但不夺取焦点
    //（window_show / windowManager.show() 都会 NSApp.activate，弃用）。
    let channel = FlutterMethodChannel(
      name: "zeromusic/lyric_window",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "orderFront":
        panel.orderFront(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 歌词条窗口形态：透明、无边框、置顶、不激活 app、不进 Dock、跨 Space。
  /// 前提：panel 必须是真 NSPanel（nonactivatingPanel 对普通 NSWindow
  /// 无效，坑 16），样式位在 NSPanel 构造时给定，此处不再改写。
  private static func applyLyricBarWindowStyle(_ panel: NSPanel) {
    panel.isOpaque = false // 背景完全透明
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating // 始终置顶（NSFloatingWindowLevel）
    // 跨 Space / 全屏应用上方仍显示。
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    // NSPanel 默认 hidesOnDeactivate = true：app 失活时整窗消失，必须关掉。
    panel.hidesOnDeactivate = false
    // 拖动由 Flutter 侧 startDragging 驱动，不依赖背景拖拽。
    panel.isMovableByWindowBackground = false
  }
}
