import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';

/// Apple Music 式「下拉收起」容器。
///
/// 包裹子内容：手指向下拖动时内容**1:1 跟手**下移（仅当拉出屏幕高度后才
/// 施加 0.25 阻尼），松手时
/// - 未过阈值/速度不足：弹性回弹复位；
/// - 超过阈值或快速下滑：执行**收起动画**——整页缩放收向 [collapseAlignment]
///   （迷你播放条方向）+ 下移 + 淡出，完成后触发 [onDismiss]（调用方 pop 收起）。
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
    this.collapseAlignment = Alignment.bottomCenter,
    this.collapseEndScale = 0.25,
    this.collapseDuration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final VoidCallback onDismiss;

  /// 收起动画开始时的回调（用于触发迷你条回弹等）。
  final VoidCallback? onDismissStart;

  final bool enabled;

  /// 允许发起下拉手势的屏幕高度比例（0..1，默认 1 = 全屏）。
  /// 低于该比例的底部区域（进度条/控制区等）不响应下拉退出，避免与
  /// 进度条拖动等其它手势冲突。
  final double startAreaFraction;

  /// 收起动画的缩放锚点（迷你条中心，屏幕坐标）。为 null 时回退
  /// [collapseAlignment] 对应的屏幕位置。
  final Offset? collapseAnchor;

  /// 收起动画收敛的锚点（迷你播放条所在方向），仅当 [collapseAnchor] 为 null 时使用。
  final Alignment collapseAlignment;

  /// 收起动画结束时的缩放。
  final double collapseEndScale;

  /// 收起动画时长（收向迷你条，刻意放慢以看清过程）。
  final Duration collapseDuration;

  @override
  State<PullToDismiss> createState() => PullToDismissState();
}

class PullToDismissState extends State<PullToDismiss>
    with TickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _velocityThreshold = 800;

  /// 手指累计下拉距离（原始、未阻尼）。不能直接用显示位移累计，否则
  /// 往回拖动会因重复计算阻尼而无法真正跟手。
  double _raw = 0;

  /// 是否正处于「收起 → 即将 pop」阶段（可被手指接管取消）。
  bool _dismissing = false;

  /// 拖拽位移（跟手 / 回弹）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
    // 位移可达整屏高度，必须放开默认 [0,1] 的上界。
    lowerBound: 0,
    upperBound: double.infinity,
  );

  /// 收起进度（0→1）：驱动 scale / 向下位移 / 淡出。
  late final AnimationController _collapseController = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
  );

  @override
  void initState() {
    super.initState();
    _collapseController.addStatusListener(_onCollapseStatus);
  }

  @override
  void dispose() {
    _collapseController
      ..removeStatusListener(_onCollapseStatus)
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
    _controller.stop();
    _collapseController.stop();
    // 收起被接管：复位缩放/淡出，仅保留纯拖拽位移继续跟手。
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

  /// 开始收起动画：整页围绕迷你条中心缩放收进迷你条（无淡入淡出），
  /// 完成后触发 [PullToDismiss.onDismiss]（调用方执行 pop 收起页面）。
  void _startCollapse(double velocity) {
    _dismissing = true;
    widget.onDismissStart?.call();
    if (MediaQuery.disableAnimationsOf(context)) {
      // 置满触发 completed → onDismiss（单次）。
      _collapseController.value = 1.0;
      return;
    }
    // easeOutBack：非线性的 spring 手感，快速收缩并带微小回弹收进迷你条。
    // 用 forward() + 在 builder 手动套曲线，保留过冲（animateTo 会钳制值）。
    _collapseController
      ..duration = widget.collapseDuration
      ..forward(from: 0);
  }

  void _onCollapseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // 若期间被手指接管（_dismissing == false），则取消退出。
    if (mounted && _dismissing) widget.onDismiss();
  }

  /// 收起时顺势下压的距离（收向底部迷你条）。
  double get _collapseDown => MediaQuery.sizeOf(context).height * 0.15;

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
          // 手动套 easeOutBack：非线性的 spring 手感（保留过冲，收进迷你条带微回弹）。
          final c = Curves.easeOutBack.transform(t);
          // 收起：从 1 缩到 endScale，围绕迷你条中心缩放收进；无淡出。
          final s = 1.0 + (widget.collapseEndScale - 1.0) * c;
          final dy = drag + _collapseDown * c;
          final anchor = _anchor(size);
          return Transform(
            transform: Matrix4.identity()
              ..translateByDouble(0, dy, 0, 1)
              ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
              ..scaleByDouble(s, s, 1, 1)
              ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
