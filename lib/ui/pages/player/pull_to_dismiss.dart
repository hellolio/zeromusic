import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';

/// Apple Music 式「下拉收起」容器。
///
/// 包裹子内容：手指向下拖动时内容跟随下移（带阻尼），松手时
/// - 未过阈值/速度不足：弹性回弹复位；
/// - 超过阈值或快速下滑：触发 [onDismiss]（调用方执行 pop 收起页面）。
///
/// 仅对 [enabled]（移动端）响应纵向手势；桌面端以点按顶部小横条收起。
class PullToDismiss extends StatefulWidget {
  const PullToDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final bool enabled;

  @override
  State<PullToDismiss> createState() => _PullToDismissState();
}

class _PullToDismissState extends State<PullToDismiss>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 120;
  static const double _velocityThreshold = 800;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.standardMotion,
    value: 0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails _) {
    if (widget.enabled) _controller.stop();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    var next = _controller.value + d.delta.dy;
    // 阻尼：拉得越远增长越慢，避免拖出屏幕。
    if (next > 100) {
      next = 100 + (next - 100) * 0.3;
    }
    _controller.value = next.clamp(0.0, double.infinity);
  }

  void _onEnd(DragEndDetails d) {
    if (!widget.enabled) return;
    final velocity = d.primaryVelocity ?? 0;
    final shouldDismiss =
        _controller.value > _dismissThreshold || velocity > _velocityThreshold;
    if (shouldDismiss) {
      widget.onDismiss();
    } else {
      _controller.animateBack(
        0,
        duration: AppCurves.standardMotion,
        curve: AppCurves.spring,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
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