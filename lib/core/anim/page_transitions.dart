import 'package:flutter/material.dart';

import '../anim/app_curves.dart';

/// 统一的页面切换转场：横向滑动 + 淡入 + 微缩放。
/// 用于 TabBar / NavigationRail 之间的页面切换，保证全局一致。
class AppPageTransition extends StatelessWidget {
  const AppPageTransition({super.key, required this.index, required this.child});

  /// 当前页面索引，用于决定滑入方向。
  final int index;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    final dir = index == 0 ? -1.0 : 1.0;
    final offset = isDesktop ? Offset(0, 0.02) : Offset(dir * 0.08, 0);
    return AnimatedSwitcher(
      duration: AppCurves.pageTransition,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.standard,
      transitionBuilder: (child, animation) {
        final slide = SlideTransition(
          position: Tween(begin: offset, end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
        return slide;
      },
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}
