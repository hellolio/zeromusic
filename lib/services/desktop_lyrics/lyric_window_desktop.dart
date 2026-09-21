import 'dart:async';

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../preferences/preferences_controller.dart' show DesktopLyricsFontSize;
import 'lyric_bar_messenger.dart';
import 'lyric_window_api.dart';

/// 桌面歌词条窗口的真实实现（desktop_multi_window + window_manager）。
///
/// 职责边界：
/// - 主窗口侧：创建/复用窗口、推送状态、接收回传事件；
/// - 窗口形态（透明 / 无边框 / 置顶 / 不抢焦点）在平台原生层或子窗口
///   入口（`lyric_bar_app.dart`）完成，本类不负责样式；
/// - 窗口**只建一次**：关闭即隐藏（引擎常驻），重开走 configure + show，
///   避免反复创建引擎造成泄漏。
class LyricWindowDesktop implements LyricWindowApi {
  WindowController? _controller;
  LyricWindowConfig? _lastConfig;
  bool _open = false;

  final _events = StreamController<LyricBarHostEvent>.broadcast();

  /// 单向通道：主窗口 → 歌词条（歌词条侧注册 handler）。
  static const _pushChannel = WindowMethodChannel(
    LyricBarChannels.push,
    mode: ChannelMode.unidirectional,
  );

  /// 单向通道：歌词条 → 主窗口（本类在 open 时注册 handler）。
  static const _backChannel = WindowMethodChannel(
    LyricBarChannels.back,
    mode: ChannelMode.unidirectional,
  );

  @override
  bool get isOpen => _open;

  @override
  Stream<LyricBarHostEvent> get events => _events.stream;

  @override
  bool get stealsFocusOnClick => !Platform.isMacOS;

  @override
  Future<void> open(LyricWindowConfig config) async {
    if (_open) return;
    await _backChannel.setMethodCallHandler(_onLyricWindowCall);
    // 已有隐藏窗口（引擎常驻）→ 直接复用；复用失败（窗口已被销毁）→ 重建。
    if (_controller != null) {
      try {
        await _controller!.invokeMethod(
          LyricBarWindowCommands.configure,
          LyricBarMessenger.encodeConfig(config),
        );
        await _controller!.invokeMethod(LyricBarWindowCommands.show);
        _lastConfig = config;
        _open = true;
        return;
      } on Exception catch (_) {
        _controller = null;
      }
    }
    _lastConfig = config;
    _controller = await WindowController.create(
      WindowConfiguration(
        // 配置随参数进入子窗口；子窗口自行定位后显示，避免错误位置闪现。
        arguments: LyricBarMessenger.encodeConfig(config),
        hiddenAtLaunch: true,
      ),
    );
    _open = true;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _safe(() => _controller?.invokeMethod(LyricBarWindowCommands.hide));
    await _backChannel.setMethodCallHandler(null);
  }

  @override
  Future<void> configure(LyricWindowConfig config) async {
    if (!_open || config == _lastConfig) return;
    _lastConfig = config;
    await _safe(
      () => _controller?.invokeMethod(
        LyricBarWindowCommands.configure,
        LyricBarMessenger.encodeConfig(config),
      ),
    );
  }

  @override
  void pushState(LyricBarStateMessage state) {
    if (!_open) return;
    unawaited(
      _safe(
        () => _pushChannel.invokeMethod(
          LyricBarWindowCommands.state,
          LyricBarMessenger.encodeState(state),
        ),
      ),
    );
  }

  @override
  Future<void> recenter() async {
    if (!_open) return;
    await _safe(
      () => _controller?.invokeMethod(LyricBarWindowCommands.recenter),
    );
  }

  Future<dynamic> _onLyricWindowCall(MethodCall call) async {
    // 引擎就绪：子窗口 push handler 已注册。此刻才 show（hiddenAtLaunch
    // 创建的窗口首次显示的唯一入口），避免未定位/未渲染闪现；并转发
    // ready 事件让控制器立即补推当前态（冷启动窗口期推送曾被丢弃）。
    if (call.method == LyricBarMessenger.readyMethod) {
      if (!_open) return null; // 启动期间已被关：保持隐藏。
      await _safe(
        () => _controller?.invokeMethod(LyricBarWindowCommands.show),
      );
      _events.add(const LyricBarReadyEvent());
      return null;
    }
    final event = LyricBarMessenger.decodeHostEvent(
      call.method,
      call.arguments,
    );
    if (event != null) {
      _events.add(event);
    }
    return null;
  }

  /// 通道失败（窗口已被销毁 / 引擎未就绪）一律静默，禁止 crash。
  Future<void> _safe(Future<Object?>? Function() action) async {
    try {
      await action();
    } on Exception catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

/// 歌词条子窗口支持的指令（经 WindowController 通道下发）。
abstract final class LyricBarWindowCommands {
  static const show = 'show';
  static const hide = 'hide';
  static const configure = 'configure';
  static const recenter = 'recenter';
  static const state = 'state';
}

/// 歌词条窗口尺寸（宽 × 高），随字号档位微调（需求 §2）。
Size lyricBarWindowSize(DesktopLyricsFontSize tier) => switch (tier) {
  DesktopLyricsFontSize.small => const Size(640, 84),
  DesktopLyricsFontSize.medium => const Size(720, 96),
  DesktopLyricsFontSize.large => const Size(800, 112),
};

/// 默认位置：屏幕底部居中偏下（需求 §2）。
Offset defaultLyricBarPosition(Size window, Size screen) {
  const bottomMargin = 96.0;
  return Offset(
    (screen.width - window.width) / 2,
    screen.height - window.height - bottomMargin,
  );
}

/// 把位置钳制回屏幕可见区域（恢复位置时调用，需求 §3.1）。
Offset clampLyricBarPosition(Offset position, Size window, Size screen) {
  final maxX = math.max(0.0, screen.width - window.width);
  final maxY = math.max(0.0, screen.height - window.height);
  return Offset(position.dx.clamp(0.0, maxX), position.dy.clamp(0.0, maxY));
}
