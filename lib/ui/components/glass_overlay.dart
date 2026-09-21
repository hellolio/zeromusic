import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// 液体玻璃容器：iOS 风格 BackdropFilter 磨砂 + 水滴玻璃质感（对标 Apple Music 迷你条）。
///
/// 「水」的表达全在光学，不在亮度：
/// - **灰雾体**：`BackdropFilter` 高斯模糊 + 中性灰雾（[AppTokens.glassFog]），
///   把背后的内容**压缩向灰**——亮处压暗、暗处提亮，像隔着水看东西，
///   通透且不发白；
/// - **水滴亮圈（bevel）**：边缘渐变描边——左上受光亮线、快速衰减，
///   右下先有一段「厚度暗环」再接一丝**底部焦散亮线**（光穿过水滴
///   聚焦在下缘），这是水滴最典型的轮廓特征；
/// - **窄幅 specular**：仅顶部一小段的高光渐变，克制不糊成白雾；
/// - **柔和外阴影**：近接触细影 + 环境软影，水滴「坐」在表面上。
///
/// **浅色/深色共用一套代码**：所有视觉量集中在 [_GlassSpec] 一张参数表里，
/// 浅色为基准；深色只调「灰雾略浓、暗环略重」两组值。雾基色两模式共用，
/// 亮度由透明度合成自然得出，不存在「深色提亮」的分支逻辑。
///
/// 用于导航栏、迷你播放条、弹窗背景等所有「玻璃面」。
class GlassOverlay extends StatelessWidget {
  const GlassOverlay({
    super.key,
    required this.child,
    this.blur = 12,
    this.radius = AppTokens.radiusL,
    this.tint,
    this.fogColor,
    this.padding = EdgeInsets.zero,
    this.border = true,
    this.shadow = true,
    this.highlight = true,
  });

  final Widget child;
  final double blur;
  final double radius;
  final Color? tint;

  /// 雾基色替换：不传时用默认灰雾 [AppTokens.glassFog]；传入时上/中/下三段
  /// 雾全部改用该基色（仅替换基色，透明度仍由 [_GlassSpec] 标定）。
  /// 用于需要「更白/更黑」玻璃底的场景（底栏、迷你条），避免灰雾压灰文字。
  final Color? fogColor;
  final EdgeInsets padding;

  /// 是否绘制水滴凸起描边（渐变亮圈）。
  final bool border;

  /// 是否绘制外阴影。
  final bool shadow;

  /// 是否绘制顶部受光高光。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final spec = Theme.of(context).brightness == Brightness.dark
        ? _GlassSpec.dark
        : _GlassSpec.light;
    // 雾基色：[fogColor] 优先，否则用默认灰雾；[tint] 仅替换中段（如选中态、
    // 播放页的强调底），上下两段仍走同一基色，保持「水」的统一材质感。
    final fogBase = fogColor ?? AppTokens.glassFog;
    final fogMid = tint ?? fogBase.withValues(alpha: spec.fogMid);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                // 近接触细影：贴在下缘 2–3px，营造水滴「坐在」表面上的深度。
                BoxShadow(
                  color: Colors.black.withValues(alpha: spec.shadowNear),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
                // 环境软影：轻浮起、与背景自然分离。
                BoxShadow(
                  color: Colors.black.withValues(alpha: spec.shadowAmbient),
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
                // 灰雾玻璃体：上略浓下沉（水滴受光方向），背景被压缩向灰透出。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          fogBase.withValues(alpha: spec.fogTop),
                          fogMid,
                          fogBase.withValues(alpha: spec.fogBottom),
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
                            // 窄幅 specular：只在水滴上缘一小段受光，0.14 内
                            // 衰减殆尽，不形成整面白雾。
                            stops: const [0.0, 0.14, 0.4, 1.0],
                            colors: [
                              Colors.white.withValues(alpha: spec.specularTop),
                              Colors.white.withValues(alpha: spec.specularFade),
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
                        painter: _DropletRimPainter(spec: spec, radius: radius),
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

/// 「水感」参数表：浅色/深色共用同一组件、同一组字段，只在此处各标定一份值。
/// 取值原则：**灰靠雾基色（中性灰）而非白雾提亮**——雾把背景压缩向灰；
/// **水滴感靠边缘光学**——受光亮圈、厚度暗环、底部焦散线都收在 rim 五段
/// 渐变里，克制不抢内容。
class _GlassSpec {
  const _GlassSpec({
    required this.fogTop,
    required this.fogMid,
    required this.fogBottom,
    required this.specularTop,
    required this.specularFade,
    required this.rim,
    required this.shadowNear,
    required this.shadowAmbient,
  });

  /// 灰雾玻璃体（上→中→下）：雾基色 [AppTokens.glassFog] 的透明度。
  final double fogTop;
  final double fogMid;
  final double fogBottom;

  /// 顶部窄幅 specular 高光（stops 0 / 0.14，随后完全透明）。
  final double specularTop;
  final double specularFade;

  /// 水滴亮圈五段渐变（沿左上→右下）：上左受光亮线 → 快速衰减 → 透明
  /// → 厚度暗环 → 底部焦散亮线。
  final List<Color> rim;

  /// 外阴影：近接触细影 / 环境软影的黑度。
  final double shadowNear;
  final double shadowAmbient;

  /// 浅色（基准标定）：白底上灰雾合成出 ~#E1 浅灰玻璃。
  static const light = _GlassSpec(
    fogTop: 0.28,
    fogMid: 0.26,
    fogBottom: 0.22,
    specularTop: 0.15,
    specularFade: 0.04,
    rim: [
      Color(0x8CFFFFFF), // white@0.55 上左角受光亮线
      Color(0x24FFFFFF), // white@0.14 快速衰减
      Color(0x00FFFFFF), // 透明
      Color(0x14000000), // black@0.08 厚度暗环
      Color(0x33FFFFFF), // white@0.20 底部焦散亮线
    ],
    shadowNear: 0.10,
    shadowAmbient: 0.06,
  );

  /// 深色：灰雾略浓（黑底上合成 ~#2D 柔灰，不提白），暗环略重衬托
  /// 焦散线；阴影收敛，避免黑块感。
  static const dark = _GlassSpec(
    fogTop: 0.36,
    fogMid: 0.32,
    fogBottom: 0.26,
    specularTop: 0.12,
    specularFade: 0.03,
    rim: [
      Color(0x66FFFFFF), // white@0.40 上左角受光亮线
      Color(0x1AFFFFFF), // white@0.10 快速衰减
      Color(0x00FFFFFF), // 透明
      Color(0x24000000), // black@0.14 厚度暗环
      Color(0x29FFFFFF), // white@0.16 底部焦散亮线
    ],
    shadowNear: 0.16,
    shadowAmbient: 0.10,
  );
}

/// 水滴「凸起」边缘：沿圆角外缘画一圈**五段渐变描边**。
/// 高光只落在上左角并**快速衰减**；右下先压一段厚度暗环、再以一丝亮线
/// 收尾（光穿过水滴聚焦在下缘的焦散），立体轮廓一眼是「水滴」。
class _DropletRimPainter extends CustomPainter {
  const _DropletRimPainter({required this.spec, required this.radius});

  final _GlassSpec spec;
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
        stops: const [0.0, 0.06, 0.55, 0.9, 1.0],
        colors: spec.rim,
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_DropletRimPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.radius != radius;
}
