import 'dart:async';

import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/localization/localizations_delegate.dart';
import '../../core/theme/app_theme.dart';
import '../../services/desktop_lyrics/lyric_bar_messenger.dart';
import '../../services/desktop_lyrics/lyric_window_desktop.dart';
import 'desktop_lyrics_bar.dart';

/// 主窗口 → 歌词条子窗口的指令（经 WindowController 通道转发）。
@immutable
sealed class LyricWindowCommand {
  const LyricWindowCommand();
}

class ShowCommand extends LyricWindowCommand {
  const ShowCommand();
}

class HideCommand extends LyricWindowCommand {
  const HideCommand();
}

class RecenterCommand extends LyricWindowCommand {
  const RecenterCommand();
}

class ConfigureCommand extends LyricWindowCommand {
  const ConfigureCommand(this.config);

  final LyricWindowConfig config;
}

/// 歌词条子窗口入口：由 main.dart 在 multi_window 模式下调用（独立引擎）。
///
/// 职责：解码创建参数 → 配置窗口形态/位置 → 注册指令 handler → 渲染。
/// 零业务：歌词状态只来自主窗口推送；✕/拖动经回调回传主窗口。
Future<void> runLyricBarWindow() async {
  final controller = await WindowController.fromCurrentEngine();
  final config = LyricBarMessenger.decodeConfig(controller.arguments);
  final commands = StreamController<LyricWindowCommand>.broadcast();

  await configureLyricBarWindow(config);
  await controller.setWindowMethodHandler((call) async {
    switch (call.method) {
      case LyricBarWindowCommands.show:
        await showLyricBarWindow();
      case LyricBarWindowCommands.hide:
        await windowManager.hide();
      case LyricBarWindowCommands.recenter:
        commands.add(const RecenterCommand());
      case LyricBarWindowCommands.configure:
        commands.add(
          ConfigureCommand(
            LyricBarMessenger.decodeConfig(call.arguments as String? ?? ''),
          ),
        );
    }
    return null;
  });

  runApp(LyricBarApp(initialConfig: config, commands: commands.stream));
}

/// 应用歌词条窗口的尺寸、位置与平台窗口属性（幂等，可反复调用）。
Future<void> configureLyricBarWindow(LyricWindowConfig config) async {
  await windowManager.ensureInitialized();
  final size = lyricBarWindowSize(config.fontTier);
  await windowManager.setSize(size);
  final display = await screenRetriever.getPrimaryDisplay();
  // visibleSize 在个别平台为 null（不报告任务栏/DOCK 区域），退回整屏尺寸。
  final screen = display.visibleSize ?? display.size;
  final target = config.offset != null
      ? clampLyricBarPosition(config.offset!, size, screen)
      : defaultLyricBarPosition(size, screen);
  await windowManager.setPosition(target);
  if (!Platform.isMacOS) {
    // macOS 的透明/无边框/置顶/不抢焦点在 MainFlutterWindow 原生完成；
    // 这里只处理走 window_manager 路线的平台（Win/Linux）。
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
  }
}

/// 显示歌词条：macOS 走原生 orderFront（不激活应用），其余平台 windowManager。
Future<void> showLyricBarWindow() async {
  if (Platform.isMacOS) {
    // 原生 handler 由 MainFlutterWindow 的 setOnWindowCreatedCallback 注册。
    unawaited(
      const MethodChannel(LyricBarChannels.native)
          .invokeMethod<void>('orderFront'),
    );
  } else {
    await windowManager.show();
  }
}

/// 歌词条子窗口的轻量 App：独立于主窗口的主题/语言/渲染。
class LyricBarApp extends StatefulWidget {
  const LyricBarApp({
    super.key,
    required this.initialConfig,
    required this.commands,
  });

  final LyricWindowConfig initialConfig;
  final Stream<LyricWindowCommand> commands;

  @override
  State<LyricBarApp> createState() => _LyricBarAppState();
}

class _LyricBarAppState extends State<LyricBarApp> {
  late LyricWindowConfig _config;
  StreamSubscription<LyricWindowCommand>? _sub;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _sub = widget.commands.listen(_onCommand);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _onCommand(LyricWindowCommand command) async {
    switch (command) {
      case ConfigureCommand(:final config):
        setState(() => _config = config);
        await configureLyricBarWindow(config);
      case RecenterCommand():
        // 清掉自定义偏移，按当前字号回默认位置（不回写主窗口偏好）。
        await configureLyricBarWindow(
          LyricWindowConfig(
            localeCode: _config.localeCode,
            dark: _config.dark,
            fontTier: _config.fontTier,
            offset: null,
            initialState: _config.initialState,
          ),
        );
      case ShowCommand():
        await showLyricBarWindow();
      case HideCommand():
        await windowManager.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: config.dark ? ThemeMode.dark : ThemeMode.light,
      // 空字符串 = 跟随系统 locale。
      locale: config.localeCode.isEmpty ? null : Locale(config.localeCode),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en'), Locale('ja')],
      localizationsDelegates: appLocalizationsDelegates,
      home: _LyricBarWindowPage(config: config),
    );
  }
}

class _LyricBarWindowPage extends StatefulWidget {
  const _LyricBarWindowPage({required this.config});

  final LyricWindowConfig config;

  @override
  State<_LyricBarWindowPage> createState() => _LyricBarWindowPageState();
}

class _LyricBarWindowPageState extends State<_LyricBarWindowPage> {
  LyricBarStateMessage _state = const LyricBarStateMessage(hasTrack: false);

  /// 最近一次实测的内容高度（由 [_ContentHeightReporter] 上报）。
  double? _lastContentHeight;

  /// 最近一次应用到窗口的尺寸（避免重复平台调用）。
  double _lastAppliedHeight = -1;
  double _lastAppliedWidth = -1;

  /// 单向通道：主窗口 → 歌词条 的状态推送。
  static const _pushChannel = WindowMethodChannel(
    LyricBarChannels.push,
    mode: ChannelMode.unidirectional,
  );

  /// 单向通道：歌词条 → 主窗口 的回传（✕ / 拖动位置）。
  static const _backChannel = WindowMethodChannel(
    LyricBarChannels.back,
    mode: ChannelMode.unidirectional,
  );

  @override
  void didUpdateWidget(covariant _LyricBarWindowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 复用路径（重开/字号切换/主题语言变更）：窗口隐藏期间的推送被
    // 抑制，最新展示态随配置下发，避免展示关闭前的陈旧行。
    if (widget.config != oldWidget.config &&
        _state != widget.config.initialState) {
      _state = widget.config.initialState;
    }
    // 复用路径的 reconfigure 会把窗口重置回默认档位尺寸：本帧渲染后
    // 重新应用内容高度，消除多余留白（含字号档位变化的宽度跟随）。
    if (widget.config != oldWidget.config && _lastContentHeight != null) {
      _lastAppliedHeight = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_applyWindowHeight());
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _state = widget.config.initialState;
    unawaited(_bootstrap());
  }

  /// 引导：注册推送 handler → 回发 ready。
  ///
  /// 顺序保证：主窗口收到 ready 时状态推送必然可达（先注册后通知），
  /// 主窗口随即 show（hiddenAtLaunch 创建的窗口首次显示的唯一入口）
  /// 并首推当前状态，覆盖冷启动窗口期被丢弃的推送。
  Future<void> _bootstrap() async {
    await _pushChannel.setMethodCallHandler((call) async {
      if (call.method == LyricBarWindowCommands.state) {
        if (!mounted) return null;
        setState(
          () => _state = LyricBarMessenger.decodeState(call.arguments),
        );
      }
      return null;
    });
    if (!mounted) return;
    try {
      await _backChannel
          .invokeMethod(LyricBarMessenger.readyMethod)
          .timeout(const Duration(seconds: 2));
    } on Exception catch (_) {
      // 主窗口通道不可达（启动期间开关已被关 / 主窗口退出）——
      // 保持 hiddenAtLaunch 的隐藏态即可，不自行 show。
    }
  }

  @override
  void dispose() {
    unawaited(_pushChannel.setMethodCallHandler(null));
    super.dispose();
  }

  Future<void> _onClose() async {
    // ✕ → 通知主窗口置关（窗口由主窗口 hide，本端兜底自隐藏防残留）。
    try {
      await _backChannel
          .invokeMethod(LyricBarMessenger.closedMethod)
          .timeout(const Duration(seconds: 2));
    } on Exception catch (_) {
      // 主窗口通道不可达（如主窗口已退出）——忽略。
    }
    await windowManager.hide();
  }

  Future<void> _onDragStart() async {
    // 原生拖拽：进入模态循环，返回即拖动结束，此刻位置已定。
    await windowManager.startDragging();
    // 等原生窗口位置稳定后再读（个别平台 wm 内部异步落位）。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      final position = await windowManager.getPosition();
      await _backChannel.invokeMethod(
        LyricBarMessenger.positionMethod,
        LyricBarMessenger.encodePosition(position),
      );
    } on Exception catch (_) {
      // 位置读取失败不致命：下次拖动再保存。
    }
  }

  /// 内容高度实测回调：把窗口高度自适应到正好包住内容。
  ///
  /// window_manager 的 setSize 语义是「顶边固定」（见原生 setBounds：
  /// origin.y += 旧高 - 新高），行数 2↔1 切换时当前行位置不跳动；
  /// 首帧收缩发生在 show 之前，肉眼无感。
  void _onContentHeightChanged(double height) {
    _lastContentHeight = height;
    unawaited(_applyWindowHeight());
  }

  Future<void> _applyWindowHeight() async {
    final contentHeight = _lastContentHeight;
    if (contentHeight == null || !mounted) {
      return;
    }
    final width = lyricBarWindowSize(widget.config.fontTier).width;
    final target = contentHeight.ceilToDouble();
    if ((target - _lastAppliedHeight).abs() < 0.5 &&
        width == _lastAppliedWidth) {
      return;
    }
    _lastAppliedHeight = target;
    _lastAppliedWidth = width;
    try {
      await windowManager.setSize(Size(width, target));
    } on Exception catch (_) {
      // 平台通道不可用（如测试环境）不影响渲染。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _ContentHeightReporter(
        onHeightChanged: _onContentHeightChanged,
        child: DesktopLyricsBar(
          state: _state,
          fontTier: widget.config.fontTier,
          onClose: _onClose,
          onDragStart: _onDragStart,
        ),
      ),
    );
  }
}

/// 实测子内容渲染高度，变化时回调（供窗口高度自适应）。
class _ContentHeightReporter extends SingleChildRenderObjectWidget {
  const _ContentHeightReporter({required this.onHeightChanged, super.child});

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderContentHeightReporter(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderContentHeightReporter renderObject,
  ) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderContentHeightReporter extends RenderProxyBox {
  _RenderContentHeightReporter(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;

  double? _lastReported;

  @override
  void performLayout() {
    super.performLayout();
    final child = this.child;
    if (child == null) {
      return;
    }
    final height = child.size.height;
    if (_lastReported != null && (height - _lastReported!).abs() <= 0.5) {
      return;
    }
    _lastReported = height;
    // 布局中不得触发平台调用：推迟到帧末。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onHeightChanged(height);
    });
  }
}
