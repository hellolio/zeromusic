import 'package:flutter/widgets.dart';

/// 记录底部悬浮玻璃控件（迷你播放条 + 液态玻璃底栏）占用的高度。
///
/// 移动端内容区（PageView）铺满整屏、滚动到玻璃之后透出，因此页面内的
/// 滚动视图需要用该 inset 预留底部间隙，保证列表最后一项能滚到玻璃之上。
/// 桌面端为 0（内容区已由 AnimatedPadding 预留，无需额外处理）。
///
/// 由 [AdaptiveScaffold] 提供；页面在其子树的 context 下读取。
/// 用 `getInheritedWidgetOfExactType` 读取，不注册依赖，可在事件回调中安全调用。
class ContentBottomInset extends InheritedWidget {
  const ContentBottomInset({
    super.key,
    required this.inset,
    required super.child,
  });

  /// 底部悬浮控件高度；无悬浮控件时为 0。
  final double inset;

  /// 读取底部预留高度；子树外（未提供时）返回 0。
  static double of(BuildContext context) {
    return context
            .getInheritedWidgetOfExactType<ContentBottomInset>()
            ?.inset ??
        0;
  }

  @override
  bool updateShouldNotify(ContentBottomInset oldWidget) =>
      oldWidget.inset != inset;
}
