import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';

/// Apple Music 式「下拉收起」容器。
///
/// 包裹子内容：手指向下拖动时内容**1:1 跟手**下移（仅当拉出屏幕高度后才
/// 施加 0.25 阻尼），松手时
/// - 未过阈值/速度不足：弹性回弹复位；
/// - 超过阈值或快速下滑：执行**收起动画**——整页先下滑、再 spring 回弹，
///   **非等比缩放**（纵向大幅压缩、横向轻微收窄）逼近迷你播放条的胶囊形状，
///   完成后触发 [onDismiss]（调用方 pop 收起）。
///
/// **全程可中断**：收起动画进行中，手指重新按下会停住动画并接管，已触发的
/// 退出随之取消——用户可以在任意时刻反悔。
/// 移动端和桌面端都响应纵向手势；顶部小横条仍可点按（经 [PullToDismissState.collapse]）收起。
/// 通过 [startAreaFraction] 限制可发起下拉的屏幕区域（避免与进度条等冲突）。
class PullToDismiss extends StatefulWidget {
  const PullToDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
    this.enabled = true,
    this.startAreaFraction = 1.0,
    this.onDismissStart,
    this.collapseAnchor,
    this.collapseTargetSize,
    this.collapseAlignment = Alignment.bottomCenter,
    this.collapseEndScale = 0.15,
    this.collapseDuration = const Duration(milliseconds: 300),
  });

  final Widget child;
  final VoidCallback onDismiss;

  /// 收起动画中页面顶部到达迷你条位置时触发（迷你条回弹开始，与后续收起过程
  /// 同步，收起完成时回弹恰好结束）。
  final VoidCallback? onDismissStart;

  final bool enabled;

  /// 允许发起下拉手势的屏幕高度比例（0..1，默认 1 = 全屏）。
  /// 低于该比例的底部区域（进度条/控制区等）不响应下拉退出，避免与
  /// 进度条拖动等其它手势冲突。
  final double startAreaFraction;

  /// 收起动画的缩放锚点（迷你条中心，屏幕坐标）。为 null 时回退
  /// [collapseAlignment] 对应的屏幕位置。
  final Offset? collapseAnchor;

  /// 迷你条尺寸：收起时页面非等比缩放，最终形状 = 该尺寸（宽扁胶囊）。
  /// 为 null 时按 [collapseEndScale] 等比缩放兜底。
  final Size? collapseTargetSize;

  /// 收起动画收敛的锚点（迷你播放条所在方向），仅当 [collapseAnchor] 为 null 时使用。
  final Alignment collapseAlignment;

  /// 兜底（无 [collapseTargetSize]）时缩放结束值。
  final double collapseEndScale;

  /// 收起动画时长。
  final Duration collapseDuration;

  @override
  State<PullToDismiss> createState() => PullToDismissState();
}

class PullToDismissState extends State<PullToDismiss>
    with TickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _velocityThreshold = 800;

  /// 下滑阶段结束时刻（0..1）：页面下滑到迷你条下方、顶部到达迷你条。
  /// 与迷你条回弹（200ms）对齐：收起 300ms × (1 - 1/3) = 200ms，即回弹结束时
  /// 正好 = 收起完成（pop）。
  static const double _peakF = 1.0 / 3.0;

  /// 收起最终高度相对迷你条的比例（高度一半）。
  static const double _targetShrink = 0.5;

  /// 收起最终宽度相对迷你条的比例（比高度收得更窄，避免收完仍显宽）。
  static const double _targetShrinkWidth = 0.35;

  /// 手指累计下拉距离（原始、未阻尼）。不能直接用显示位移累计，否则
  /// 往回拖动会因重复计算阻尼而无法真正跟手。
  double _raw = 0;

  /// 是否正处于「收起 → 即将 pop」阶段（可被手指接管取消）。
  bool _dismissing = false;

  /// 是否已触发过迷你条回弹（页面顶部到达迷你条时只触发一次）。
  bool _bounceTriggered = false;

  /// 拖拽位移（跟手 / 回弹）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
    // 位移可达整屏高度，必须放开默认 [0,1] 的上界。
    lowerBound: 0,
    upperBound: double.infinity,
  );

  /// 收起进度（0→1）：驱动缩放 / 位移。
  late final AnimationController _collapseController = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
  );

  @override
  void initState() {
    super.initState();
    _collapseController.addStatusListener(_onCollapseStatus);
    _collapseController.addListener(_onCollapseTick);
  }

  @override
  void dispose() {
    _collapseController
      ..removeStatusListener(_onCollapseStatus)
      ..removeListener(_onCollapseTick)
      ..dispose();
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
    // 手指重新按下：停住任何进行中的动画（回弹/收起）并从此位置接管，
    // 同时取消已排定的退出动作 —— 动画全程可中断。
    _active = true;
    _dismissing = false;
    _bounceTriggered = false;
    _controller.stop();
    _collapseController.stop();
    // 收起被接管：复位缩放/位移，仅保留纯拖拽位移继续跟手。
    _collapseController.value = 0;
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
      _startCollapse(velocity);
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

  /// 供外部触发收起（顶部收起条点按），与下拉共用同一收起动画。
  void collapse() {
    if (_dismissing) return;
    _startCollapse(0);
  }

  /// 开始收起动画：围绕迷你条中心**连续下滑 + 缩小**收进（无淡入淡出、无分段拐点），
  /// 完成后触发 [PullToDismiss.onDismiss]（调用方执行 pop 收起页面）。
  void _startCollapse(double velocity) {
    _dismissing = true;
    _bounceTriggered = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      // 置满触发 completed → onDismiss（单次）；同时补发回弹信号。
      _collapseController.value = 1.0;
      _onCollapseTick();
      return;
    }
    _collapseController
      ..duration = widget.collapseDuration
      ..forward(from: 0);
  }

  /// 几何触发：页面**顶部**下滑到迷你条位置时触发一次
  /// [PullToDismiss.onDismissStart]（迷你条回弹开始）。
  ///
  /// [_pose] 保证 t = [_peakF] 时顶部 `topY = anchorY*(1-sy) + dy` 恰好 = 锚点 Y
  /// （页面顶部到达迷你条），故在该时刻触发；回弹 200ms 结束时正好 = 收起完成（pop）。
  void _onCollapseTick() {
    if (_bounceTriggered || !_dismissing) return;
    if (_collapseController.value < _peakF) return;
    _bounceTriggered = true;
    widget.onDismissStart?.call();
  }

  void _onCollapseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // 若期间被手指接管（_dismissing == false），则取消退出。
    if (mounted && _dismissing) widget.onDismiss();
  }

  /// 缩放锚点：优先迷你条中心；否则按 [collapseAlignment] 取屏幕对应位置。
  Offset _anchor(Size size) {
    final explicit = widget.collapseAnchor;
    if (explicit != null) return explicit;
    final a = widget.collapseAlignment;
    return Offset(size.width * (a.x + 1) / 2, size.height * (a.y + 1) / 2);
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
        animation: Listenable.merge([_controller, _collapseController]),
        builder: (context, child) {
          final size = MediaQuery.sizeOf(context);
          final t = _collapseController.value;
          final drag = _controller.value;
          final anchor = _anchor(size);
          final (dy, sx, sy) = _pose(t, drag, anchor.dy);
          return Transform(
            transform: Matrix4.identity()
              ..translateByDouble(0, dy, 0, 1)
              ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
              ..scaleByDouble(sx, sy, 1, 1)
              ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }

  /// 收起位姿：页面**先下滑到迷你条**（峰值时刻顶部到达迷你条），再 **回弹
  /// 收回迷你条**，全程**非等比缩小**逼近迷你条胶囊形状（无淡出、无开始急跳）。
  ///
  /// - 缩放：sx 1→迷你条宽×0.35/屏宽、sy 1→迷你条高×0.5/屏高（easeOutCubic
  ///   连续缩小），最终胶囊明显比迷你条窄；
  /// - 位移 dy：t∈[0,_peakF] 从拖拽位下滑到 peakDy（顶部到达迷你条）；
  ///   t∈[_peakF,1] 回收到迷你条中心**稍微偏下**（无向上过冲，不会冲到条上沿）。
  (double, double, double) _pose(double t, double drag, double anchorY) {
    final size = MediaQuery.sizeOf(context);
    final target = widget.collapseTargetSize;
    final sxEnd = target == null
        ? widget.collapseEndScale
        : (target.width * _targetShrinkWidth / size.width).clamp(0.01, 1.0);
    final syEnd = target == null
        ? widget.collapseEndScale
        : (target.height * _targetShrink / size.height).clamp(0.01, 1.0);
    final e = Curves.easeOutCubic.transform(t);
    final sx = 1.0 + (sxEnd - 1.0) * e;
    final sy = 1.0 + (syEnd - 1.0) * e;
    // 峰值时刻页面顶部恰好到达迷你条：topY = anchorY*(1-sy)+dy = anchorY。
    final syPeak = 1.0 + (syEnd - 1.0) * Curves.easeOutCubic.transform(_peakF);
    final peakDy = anchorY * syPeak;
    // 最终停在迷你条中心稍微偏下一点点。
    final settleDy = size.height * 0.015;
    double dy;
    if (t < _peakF) {
      // ① 下滑到迷你条（顶部到达迷你条）。
      final p = (t / _peakF).clamp(0.0, 1.0);
      dy = drag + (peakDy - drag) * Curves.easeOutCubic.transform(p);
    } else {
      // ② 回弹收回迷你条（平滑减速，无向上过冲）。
      final p = ((t - _peakF) / (1 - _peakF)).clamp(0.0, 1.0);
      dy = peakDy + (settleDy - peakDy) * Curves.easeOutCubic.transform(p);
    }
    return (dy, sx, sy);
  }
}
