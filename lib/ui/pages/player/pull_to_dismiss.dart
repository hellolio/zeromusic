import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';

/// Apple Music 式「下拉收起」容器。
///
/// 包裹子内容：手指向下拖动时内容**1:1 跟手**下移（仅当拉出屏幕高度后才
/// 施加 0.25 阻尼），松手时
/// - 未过阈值/速度不足：弹性回弹复位；
/// - 超过阈值或快速下滑：按松手速度**飞出手感**的滑出动画，滑出屏幕后
///   再触发 [onDismiss]（调用方执行 pop 收起页面）。
///
/// **全程可中断**：回弹/飞出动画进行中，手指重新按下会停住动画并接管，
/// 已触发的退出随之取消——用户可以在任意时刻反悔。
/// 移动端和桌面端都响应纵向手势；顶部小横条仍可点按收起。
/// 通过 [startAreaFraction] 限制可发起下拉的屏幕区域（避免与进度条等冲突）。
class PullToDismiss extends StatefulWidget {
  const PullToDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
    this.enabled = true,
    this.startAreaFraction = 1.0,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final bool enabled;

  /// 允许发起下拉手势的屏幕高度比例（0..1，默认 1 = 全屏）。
  /// 低于该比例的底部区域（进度条/控制区等）不响应下拉退出，避免与
  /// 进度条拖动等其它手势冲突。
  final double startAreaFraction;

  @override
  State<PullToDismiss> createState() => _PullToDismissState();
}

class _PullToDismissState extends State<PullToDismiss>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _velocityThreshold = 800;

  /// 手指累计下拉距离（原始、未阻尼）。不能直接用显示位移累计，否则
  /// 往回拖动会因重复计算阻尼而无法真正跟手。
  double _raw = 0;

  /// 是否正处于「滑出屏幕 → 即将 pop」的飞出阶段（可被手指接管取消）。
  bool _dismissing = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
    // 位移可达整屏高度，必须放开默认 [0,1] 的上界。
    lowerBound: 0,
    upperBound: double.infinity,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 原始距离 → 显示位移：1:1 跟手，超过屏幕高度后才有轻微阻尼。
  double _display(double raw) {
    final h = MediaQuery.sizeOf(context).height;
    if (raw <= h) return raw;
    return h + (raw - h) * 0.25;
  }

  /// 显示位移 → 原始距离（_display 的逆运算，用于接管动画中途值）。
  double _rawOf(double display) {
    final h = MediaQuery.sizeOf(context).height;
    if (display <= h) return display;
    return h + (display - h) / 0.25;
  }

  /// 当前手势是否有效（仅当起始点在允许区域内才跟踪）。
  bool _active = false;

  void _onStart(DragStartDetails d) {
    if (!widget.enabled) return;
    final limit = MediaQuery.sizeOf(context).height * widget.startAreaFraction;
    if (d.globalPosition.dy > limit) {
      // 起始点位于允许区域之外（进度条/底部控制区）：不接管、不跟踪，
      // 让位给进度条等其它手势。
      _active = false;
      return;
    }
    // 手指重新按下：停住任何进行中的动画（回弹/飞出）并从此位置接管，
    // 同时取消已排定的退出动作 —— 动画全程可中断。
    _active = true;
    _dismissing = false;
    _controller.stop();
    _raw = _rawOf(_controller.value).clamp(0.0, double.infinity);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled || !_active) return;
    _raw = (_raw + d.delta.dy).clamp(0.0, double.infinity);
    _controller.value = _display(_raw);
  }

  void _onEnd(DragEndDetails d) {
    if (!widget.enabled || !_active) return;
    _active = false;
    final velocity = d.primaryVelocity ?? 0;
    final value = _controller.value;
    if (value > _dismissThreshold || velocity > _velocityThreshold) {
      _flyOut(value, velocity);
    } else {
      _springBack();
    }
  }

  void _onCancel() {
    _active = false;
    if (widget.enabled) _springBack();
  }

  void _springBack() {
    if (_controller.value == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
      _raw = 0;
      return;
    }
    _dismissing = false;
    _controller.animateBack(
      0,
      duration: AppCurves.standardMotion,
      curve: AppCurves.spring,
    );
  }

  /// 滑出屏幕底部（带松手速度的飞出手感），完成后才触发 [PullToDismiss.onDismiss]。
  void _flyOut(double value, double velocity) {
    final target = MediaQuery.sizeOf(context).height;
    _dismissing = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
      widget.onDismiss();
      return;
    }
    // 松手速度越快、剩余距离越短 → 动画越短（0.4–0.6s），线性匀速
    // 飞出，便于看清播放页下滑退出的过程。
    final speed = velocity.abs().clamp(1200.0, 4000.0);
    final remaining = (target - value).clamp(80.0, double.infinity);
    final ms = (remaining / speed * 1000).round().clamp(400, 600);
    _controller
        .animateTo(
          target,
          duration: Duration(milliseconds: ms),
          // 线性匀速飞出：避免 easeIn 起始近似停顿；跟手/取消逻辑不受影响。
          curve: Curves.linear,
        )
        .then((_) {
      // 若期间被手指接管（_dismissing == false），则取消退出。
      if (mounted && _dismissing) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      onVerticalDragCancel: _onCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _controller.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
