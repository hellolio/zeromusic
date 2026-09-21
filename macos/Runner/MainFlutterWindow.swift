import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
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
      RegisterGeneratedPlugins(registry: controller)
      guard let window = controller.window else { return }
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

  /// 歌词条窗口形态：透明、无边框、置顶、不抳焦点、不进 Dock、跨 Space。
  private static func applyLyricBarWindowStyle(_ window: NSWindow) {
    // borderless 默认不可成为 key 窗口 → 点击歌词条不抳焦点。
    window.styleMask = [.borderless]
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
