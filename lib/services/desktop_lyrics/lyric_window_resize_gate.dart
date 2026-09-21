import 'dart:async';

import 'dart:ui' show Size;

/// 窗口 setSize 闸门：把尺寸变更从 Flutter 帧流水线里摘出来（坑 12）。
///
/// 背景：歌词条子窗口曾在 `addPostFrameCallback`（帧回调）里直接调
/// `windowManager.setSize`，平台消息会在帧处理 / ResizeSynchronizer 事务
/// 途中被同步泵入（重入），与 raster 线程竞态导致 Impeller
/// `SetupRenderPass` 空指针崩溃（同族已知 issue：flutter/flutter#183623，
/// 「程序化 resize 风暴 + 活跃渲染」时序竞态）。
///
/// 本闸门三重收敛：
/// 1. **去抖**：[debounce] 窗口期内反复变化只落一次（合并为最新值）；
/// 2. **串行**：同一时刻最多一个 setSize 在途，在途期间新请求排队；
/// 3. **错峰**：实际应用发生在定时器回调（安静的事件循环轮次），
///    不再嵌在任何帧回调 / 平台消息处理栈里。
class LyricWindowResizeGate {
  LyricWindowResizeGate({
    required this._apply,
    this.debounce = const Duration(milliseconds: 150),
  });

  final Future<void> Function(Size size) _apply;

  /// 去抖窗口（默认 150ms：肉眼无感的合并窗 + 足够错开渲染事务）。
  final Duration debounce;

  Timer? _timer;
  bool _inFlight = false;

  /// 最近一次请求（在途/排队中，始终只保留最新值）。
  Size? _pending;

  /// 最近一次成功应用的值（幂等去重基准）。
  Size? _lastApplied;

  /// 请求把窗口调到 [size]；与最近已应用值相同且无在途请求时忽略。
  void schedule(Size size) {
    if (!_inFlight && size == _lastApplied) {
      return;
    }
    _pending = size;
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  /// 忘记「已应用」记忆：窗口被外部改回档位尺寸后（如 reconfigure），
  /// 同值也需要重放时调用。
  void reset() {
    _lastApplied = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void _flush() {
    _timer = null;
    if (_inFlight) {
      // 上一笔未完成：不并发，完成回调里会按 _pending 重排。
      return;
    }
    final size = _pending;
    _pending = null;
    if (size == null || size == _lastApplied) {
      return;
    }
    _inFlight = true;
    unawaited(_run(size));
  }

  Future<void> _run(Size size) async {
    try {
      await _apply(size);
      _lastApplied = size;
    } on Exception catch (_) {
      // 平台通道不可用（窗口销毁 / 测试环境）：忽略，不阻断后续调度。
    }
    _inFlight = false;
    if (_pending != null && _pending != _lastApplied) {
      _timer?.cancel();
      _timer = Timer(debounce, _flush);
    }
  }
}
