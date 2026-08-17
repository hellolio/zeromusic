import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../scaffold/sidebar_inset.dart';

/// 统一的居中弹窗：所有弹窗（选择菜单 / 底部弹层 / 弹框）都从窗口中间弹出，
/// 桌面端与移动端行为一致。
///
/// - 点击弹窗外部（barrier）即可关闭。
/// - 桌面端有左侧栏时，以内容区（不含左侧栏）为水平居中基准（[SidebarInset]）；
///   移动端（无左侧栏）则以整屏居中。
/// - 尺寸随内容自适应：默认最大宽 440、最大高为屏高 80%（过长时由调用方在
///   内容里用 [Flexible]/[ListView] 保证内部滚动），短内容则收缩到内容大小。
/// - 使用带弹性的缩放 + 淡入作为弹出动画。
Future<T?> showCenterPopup<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 440,
  double? maxHeight,
}) {
  // 桌面端左侧栏宽度；弹窗水平基准 = 内容区中心 = 整屏中心 + 侧栏宽/2。
  final sideInset = SidebarInset.of(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: AppCurves.standardMotion,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppCurves.standard);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(
            CurvedAnimation(parent: animation, curve: AppCurves.spring),
          ),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogCtx, _, _) => Center(
      child: Transform.translate(
        offset: Offset(sideInset / 2, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight ?? MediaQuery.sizeOf(dialogCtx).height * 0.8,
          ),
          child: child,
        ),
      ),
    ),
  );
}
