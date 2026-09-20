import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../scaffold/sidebar_inset.dart';

/// 弹窗文字提亮：液态玻璃弹窗整体偏暗（背后叠了暗色 barrier），
/// 浅色模式下默认黑字难以看清。弹窗内统一改为白色系——
/// 主文字/图标纯白，次级文字（onSurfaceVariant / onSecondary）提亮为 white70，
/// 保留文字层级的同时保证可读性。强调色（primary）保持不变。
class GlassPopupTextTheme extends StatelessWidget {
  const GlassPopupTextTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        colorScheme: theme.colorScheme.copyWith(
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white70,
          onSecondary: Colors.white70,
        ),
      ),
      child: child,
    );
  }
}

/// 背景模糊目标强度（与玻璃体自身模糊量级一致，避免过糊）。
const double _popupBackdropSigma = 12;

/// 统一的居中弹窗：所有弹窗（选择菜单 / 底部弹层 / 弹框）都从窗口中间弹出，
/// 桌面端与移动端行为一致。
///
/// - 点击弹窗外部（barrier）即可关闭。
/// - 桌面端有左侧栏时，以内容区（不含左侧栏）为水平居中基准（[SidebarInset]）；
///   移动端（无左侧栏）则以整屏居中。
/// - 尺寸自适应内容并钳制上限：宽度不超过屏宽 80%；高度默认不超过
///   移动端屏高 50%（桌面端 80%，可通过 [maxHeight] 覆盖），过长内容
///   由调用方在内容里用 [Flexible]/[ListView] 保证内部滚动。
/// - 弹出动画：带弹性的缩放 + 淡入；**背景模糊随转场渐变生效**——
///   全屏 BackdropFilter 的 sigma 跟随转场 0 → 全值渐变，打开/关闭都
///   平滑过渡。不放进 FadeTransition 内部：部分平台（Impeller）下被
///   透明度包裹的 BackdropFilter 只在完全不透明时才生效，导致模糊
///   「突然出现」；独立渐变层规避该行为，观感自然。
/// - 弹窗内文字统一白色系（[GlassPopupTextTheme]），浅色模式下同样清晰。
Future<T?> showCenterPopup<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 440,
  double? maxHeight,
}) {
  // 桌面端左侧栏宽度；弹窗水平基准 = 内容区中心 = 整屏中心 + 侧栏宽/2。
  // 移动端（无左侧栏）为 0，以此区分两端的高度上限策略。
  final sideInset = SidebarInset.of(context);
  final barrierLabel =
      MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black54,
    transitionDuration: AppCurves.standardMotion,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppCurves.standard);
      // AnimatedBuilder 逐帧重建，保证模糊 sigma 跟随转场进度平滑变化。
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final sigma = _popupBackdropSigma * curved.value;
          return Stack(
            children: [
              // 背景模糊层：不拦截点击，命中全部落入下方 barrier / 弹窗内容。
              if (sigma > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      key: const ValueKey('popupBackdropBlur'),
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(
                    CurvedAnimation(parent: animation, curve: AppCurves.spring),
                  ),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    },
    pageBuilder: (dialogCtx, _, _) {
      final size = MediaQuery.sizeOf(dialogCtx);
      final isMobile = sideInset <= 0;
      return Center(
        child: Transform.translate(
          offset: Offset(sideInset / 2, 0),
          child: GlassPopupTextTheme(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(maxWidth, size.width * 0.8),
                maxHeight: maxHeight ?? size.height * (isMobile ? 0.5 : 0.8),
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
