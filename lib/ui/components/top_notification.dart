import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../../core/theme/app_tokens.dart';

/// 顶部下滑通知卡片（toast 样式，类似系统通知）。
///
/// 由 [OverlayEntry] 挂载在应用根 Overlay 顶部：
/// 入场从页面顶部下滑 + 淡入，驻留 [duration] 后上滑淡出并触发 [onDismissed]
/// （用于让调用方移除 OverlayEntry）。遵守「减弱动态效果」设置。
class TopNotification extends StatefulWidget {
  const TopNotification({
    super.key,
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final String message;

  /// 驻留时长（不含进出场动画）。
  final Duration duration;

  /// 通知完全消失后回调（调用方应在此移除 OverlayEntry）。
  final VoidCallback onDismissed;

  @override
  State<TopNotification> createState() => _TopNotificationState();
}

class _TopNotificationState extends State<TopNotification>
    with SingleTickerProviderStateMixin {
  static const Duration _slideIn = Duration(milliseconds: 260);
  static const Duration _slideOut = Duration(milliseconds: 200);

  late final AnimationController _controller;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _slideIn);
    _controller.forward();
    // 停驻时长固定，不随「减弱动效」缩短，保证通知可被感知。
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 开启减弱动效时跳过入场动画，直接呈现。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted || _leaving) return;
    _leaving = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.0;
    } else {
      _controller.duration = _slideOut;
      await _controller.reverse();
    }
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // inverseSurface：浅色主题为深色，深色主题为浅色，文字反向取值。
    final onPill =
        theme.brightness == Brightness.dark ? Colors.black : Colors.white;
    return SlideTransition(
      position: Tween(begin: const Offset(0, -1), end: Offset.zero)
          .animate(CurvedAnimation(parent: _controller, curve: AppCurves.standard)),
      child: FadeTransition(
        opacity: _controller,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceL,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                size: 20,
                color: Color(0xFF30D158),
              ),
              const SizedBox(width: AppTokens.spaceS),
              Text(
                widget.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onPill,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}