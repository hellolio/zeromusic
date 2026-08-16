import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 毛玻璃容器：iOS 风格 BackdropFilter 封装。
/// 用于导航栏、迷你播放条、弹窗背景。
class GlassOverlay extends StatelessWidget {
  const GlassOverlay({
    super.key,
    required this.child,
    this.blur = 24,
    this.radius = AppTokens.radiusL,
    this.tint,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double blur;
  final double radius;
  final Color? tint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTint = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.65);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: tint ?? defaultTint,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
