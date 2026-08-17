import 'package:flutter/widgets.dart';

/// 记录当前左侧栏宽度（像素），供居中弹窗等定位逻辑忽略左侧栏。
///
/// - 桌面端：左侧 [AppSideBar] 占位宽度。
/// - 移动端：无左侧栏，inset 为 0。
///
/// 由 [AdaptiveScaffold] 在根部提供；弹窗在其子树的 context 下读取。
/// 用 `getInheritedWidgetOfExactType` 读取，不注册依赖，可在事件回调中安全调用。
class SidebarInset extends InheritedWidget {
  const SidebarInset({
    super.key,
    required this.inset,
    required super.child,
  });

  /// 左侧栏宽度；无左侧栏时为 0。
  final double inset;

  /// 读取左侧栏宽度；子树外（如移动端全屏播放页等非 Scaffold 后代）返回 0。
  static double of(BuildContext context) {
    return context
            .getInheritedWidgetOfExactType<SidebarInset>()
            ?.inset ??
        0;
  }

  @override
  bool updateShouldNotify(SidebarInset oldWidget) =>
      oldWidget.inset != inset;
}
