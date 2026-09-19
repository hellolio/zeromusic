import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 液体玻璃容器：iOS 风格 BackdropFilter 磨砂 + 水滴玻璃质感（对标 Apple Music 迷你条）。
///
/// 特征克制而精致，边缘呈水滴「凸起」：
/// - **通透磨砂**：`BackdropFilter` 高斯模糊 + 极低透明度中性底色（黑白灰，
///   不带色相），背景清晰透出，水一样通透；
/// - **水滴亮圈（bevel）**：用**渐变描边**勾勒边缘——左上受光最亮、
///   渐暗到右下微暗，形成水滴/玻璃「凸起」的立体轮廓；
/// - **顶部受光**：较明显的白色渐变（仅上部一小段），模拟水滴折射 specular；
/// - **柔和外阴影**：近接触细影 + 环境软影，轻浮起、与背景自然分离；
///   深色下刻意减淡避免黑块感。
///
/// 用于导航栏、迷你播放条、弹窗背景等所有「玻璃面」。
class GlassOverlay extends StatelessWidget {
  const GlassOverlay({
    super.key,
    required this.child,
    this.blur = 12,
    this.radius = AppTokens.radiusL,
    this.tint,
    this.padding = EdgeInsets.zero,
    this.border = true,
    this.shadow = true,
    this.highlight = true,
  });

  final Widget child;
  final double blur;
  final double radius;
  final Color? tint;
  final EdgeInsets padding;

  /// 是否绘制水滴凸起描边（渐变亮圈）。
  final bool border;

  /// 是否绘制外阴影。
  final bool shadow;

  /// 是否绘制顶部受光高光。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 中性透亮底色：仅用黑白灰与透明度表达「水感磨砂」，不带任何色相。
    // 透明度刻意压到极低（浅色 0.09 / 深色 0.07）+ 低模糊，让背后的内容
    // 清晰透出，保证「看见背后元素」的通透感。
    final defaultTint = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.09);
    final bodyBase = tint ?? defaultTint;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                // 近接触细影：贴在下缘 2–3px，营造水滴「坐在」表面上的深度。
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
                // 环境软影：轻浮起、与背景自然分离（深色下明显减淡）。
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // 通透玻璃体：上亮下清（凸起的受光方向），背景透出。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [
                                Colors.white.withValues(alpha: 0.12),
                                bodyBase,
                                Colors.white.withValues(alpha: 0.03),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.15),
                                bodyBase,
                                Colors.white.withValues(alpha: 0.03),
                              ],
                      ),
                    ),
                  ),
                ),
                if (highlight)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.22, 0.55, 1.0],
                            colors: [
                              Colors.white.withValues(
                                alpha: isDark ? 0.13 : 0.16,
                              ),
                              Colors.white.withValues(
                                alpha: isDark ? 0.04 : 0.05,
                              ),
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (border)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DropletRimPainter(
                          isDark: isDark,
                          radius: radius,
                        ),
                      ),
                    ),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 水滴「凸起」边缘：沿圆角外缘画一圈**渐变描边**。
/// 受光高光只集中在上左角并**快速衰减**（避免整条边泛白、无过渡），
/// 右下仅存一丝微暗形成 bevel 立体感；描边极细，克制不抢眼。
class _DropletRimPainter extends CustomPainter {
  const _DropletRimPainter({required this.isDark, required this.radius});

  final bool isDark;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(0, radius - 0.5)),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        // 高光只落在上左角，0.05 内已衰减大半，0.18 处完全透明，
        // 让左/上边缘有「过渡」，而不是一整条白线。
        stops: const [0.0, 0.05, 0.18, 1.0],
        colors: isDark
            ? const [
                Color(0x59FFFFFF), // white@0.35 上左角受光
                Color(0x14FFFFFF), // white@0.08 快速衰减
                Color(0x00FFFFFF), // 透明
                Color(0x2E000000), // black@0.18 右下微暗
              ]
            : const [
                Color(0x8CFFFFFF), // white@0.55 上左角受光
                Color(0x24FFFFFF), // white@0.14 快速衰减
                Color(0x00FFFFFF), // 透明
                Color(0x12000000), // black@0.07 右下微暗
              ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_DropletRimPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.radius != radius;
}
