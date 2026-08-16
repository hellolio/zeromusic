import 'package:flutter/animation.dart';

/// 统一动效曲线与时长。所有动画必须使用这些常量，保证全局手感一致。
abstract final class AppCurves {
  /// 标准进出手感。
  static const Curve standard = Curves.easeOutCubic;

  /// 微交互（按钮、图标切换）。
  static const Curve quick = Curves.easeOut;

  /// 手势回弹。
  static const Curve spring = Curves.easeOutBack;

  // ---- 时长 ----
  static const Duration pageTransition = Duration(milliseconds: 300);
  static const Duration quickMotion = Duration(milliseconds: 150);
  static const Duration standardMotion = Duration(milliseconds: 250);
  static const Duration miniPlayerMotion = Duration(milliseconds: 250);
}
