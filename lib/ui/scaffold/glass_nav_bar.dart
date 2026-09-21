import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../../core/theme/app_tokens.dart';
import '../components/glass_overlay.dart';

/// 底栏导航目的地描述。
class GlassNavDestination {
  const GlassNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 移动端液态玻璃底栏：悬浮胶囊（左右留边距、左右端圆角 = 半高），
/// 高度与迷你播放条一致；选中项背后的玻璃指示胶囊随切换 spring 滑动，
/// 图标与文字颜色同步过渡（对标 Apple Music 的切换动效）。
///
/// 两种切换方式：
/// - 点按导航项；
/// - **横向拖拽底栏**：水滴指示胶囊作为「聚焦把手」跟手滑移（底栏本身不动），
///   并做液体拉伸形变（拖得越远拉得越长）；页面经 [onScrub] 实时跟随滑块
///   位置预览。手指离开后，滑块 spring 吸附到最近的选项，页面切换到该页；
///   快拂则带速度滑向速度方向的下一个档位（至少移动一项）。
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.onScrub,
  });

  /// 胶囊高度（与迷你播放条一致）；圆角取半高 → 左右倒圆角。
  static const double height = AppTokens.mobileBottomControlHeight;

  /// 滑动指示胶囊尺寸。
  static const double _pillWidth = 78;
  static const double _pillHeight = 46;

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavDestination> destinations;

  /// 拖动中的分数页码回调；不传则仅底栏内部动画，不联动页面。
  final ValueChanged<double>? onScrub;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  /// 快拂判定速度阈值（逻辑像素/秒）：超过则沿方向至少翻一页。
  static const double _flingSpeed = 500;

  /// 液体形变最大水平拉伸量（垂直按比例压扁）。
  static const double _maxStretch = 0.22;

  /// 按住放大倍率：任意按下时滑块放大成「水滴」，松手 spring 回弹。
  static const double _pressScale = 1.12;

  /// 是否按住（按下底栏任意位置即为 true）。
  bool _pressed = false;

  /// 拖动中的分数下标（越界部分已做橡皮筋阻尼）；null = 未拖动。
  double? _scrub;

  /// 拖动期间指示胶囊的拉伸目标（0.._maxStretch），松手回弹为 0。
  double _stretchTarget = 0;

  int get _highlightIndex {
    final scrub = _scrub;
    if (scrub == null) return widget.selectedIndex;
    return scrub.round().clamp(0, widget.destinations.length - 1);
  }

  /// 越界拖动施加橡皮筋阻尼：只跟随越界量的 18%。
  double _rubberband(double value) {
    final max = widget.destinations.length - 1;
    if (value < 0) return value * 0.18;
    if (value > max) return max + (value - max) * 0.18;
    return value;
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _scrub = widget.selectedIndex.toDouble();
      _stretchTarget = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double itemWidth) {
    final scrub = _scrub;
    if (scrub == null) return;
    // 滑块作为「聚焦把手」跟手：手指向哪滑，滑块就滑向哪
    //（dx > 0 → 滑块右移 → 指向更大下标）。底栏本身保持不动。
    final next = _rubberband(scrub + details.delta.dx / itemWidth);
    setState(() {
      _scrub = next;
      // 拉伸量随离开当前项的距离增大，形成「拉果冻」的液态手感。
      final travel = (next - widget.selectedIndex).abs().clamp(0.0, 1.0);
      _stretchTarget = _maxStretch * travel;
    });
    widget.onScrub?.call(next.clamp(0.0, (widget.destinations.length - 1).toDouble()));
  }

  void _onDragEnd(DragEndDetails details) {
    final scrub = _scrub;
    if (scrub == null) return;
    final velocity = details.primaryVelocity ?? 0;
    final count = widget.destinations.length;
    int target;
    if (velocity.abs() > _flingSpeed) {
      // 快拂：滑块带速度滑向速度方向的下一个档位（至少移动一项；
      // 已越过更远项时不回跳）。
      target = (velocity > 0 ? scrub.ceil() : scrub.floor())
          .clamp(0, count - 1);
    } else {
      // 慢拖松手：吸附到最近项。
      target = scrub.round().clamp(0, count - 1);
    }
    setState(() {
      _scrub = null;
      _stretchTarget = 0;
    });
    widget.onSelected(target);
  }

  void _onDragCancel() {
    if (_scrub == null) return;
    setState(() {
      _scrub = null;
      _stretchTarget = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 雾基色分模式：浅色用白基雾（更白）、深色用黑基雾（更黑），
    // 避免默认灰雾把未选中文字呵得发灰不清。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: GlassNavBar.height,
      child: GlassOverlay(
        radius: GlassNavBar.height / 2,
        blur: 10,
        fogColor: isDark ? Colors.black : Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = widget.destinations.length;
            final itemWidth = constraints.maxWidth / count;
            final scrub = _scrub;
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            // 按住放大目标：减弱动效时跳过动画、瞬时到达目标（静态状态
            // 变化不算动效，保留按压反馈）。
            final pressTarget = _pressed ? _pressScale : 1.0;
            // 指示胶囊位置：拖动时跟手（分数下标），静止时吸附选中项。
            final pillLeft =
                (scrub ?? widget.selectedIndex) * itemWidth +
                    (itemWidth - GlassNavBar._pillWidth) / 2;
            return Listener(
              // 任意按下：滑块 spring 放大成「水滴」，抬起/取消回弹。
              onPointerDown: (_) => _setPressed(true),
              onPointerUp: (_) => _setPressed(false),
              onPointerCancel: (_) => _setPressed(false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, itemWidth),
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: Stack(
                  children: [
                    // 滑动玻璃指示胶囊：拖动中零时长直跟手，松手 spring 吸附。
                    AnimatedPositioned(
                      duration: scrub != null ? Duration.zero : AppCurves.standardMotion,
                      curve: AppCurves.spring,
                      left: pillLeft,
                      top: (GlassNavBar.height - GlassNavBar._pillHeight) / 2,
                      width: GlassNavBar._pillWidth,
                      height: GlassNavBar._pillHeight,
                      child: TweenAnimationBuilder<double>(
                        // 按住放大：与拖拽液态拉伸叠加。
                        tween: Tween(end: pressTarget),
                        duration:
                            reduceMotion ? Duration.zero : AppCurves.quickMotion,
                        curve: AppCurves.spring,
                        builder: (context, pressScale, pill) =>
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: _stretchTarget),
                              duration: AppCurves.quickMotion,
                              curve: AppCurves.quick,
                              builder: (context, stretch, child) => Transform(
                                key: const ValueKey('nav-bar-pill-transform'),
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scaleByDouble(
                                    (1.0 + stretch) * pressScale,
                                    (1.0 - stretch * 0.35) * pressScale,
                                    1,
                                    1,
                                  ),
                                child: child,
                              ),
                              child: pill,
                            ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // 中性白底胶囊：与玻璃背景同色系，不带蓝色色相；
                            // 选中强调色仅由下方图标/文字（accent）承担。
                            color: Colors.white.withValues(
                              alpha: isDark ? 0.12 : 0.45,
                            ),
                            borderRadius: BorderRadius.circular(
                              GlassNavBar._pillHeight / 2,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: isDark ? 0.10 : 0.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _NavItem(
                              destination: widget.destinations[i],
                              selected: i == _highlightIndex,
                              onTap: () => widget.onSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 单个底栏导航项：图标 + 文字，颜色随选中状态平滑过渡。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fg = selected ? accent : theme.colorScheme.onSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: fg),
            duration: AppCurves.standardMotion,
            curve: AppCurves.standard,
            builder: (_, color, _) => Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 24,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: AppCurves.standardMotion,
            curve: AppCurves.standard,
            style:
                theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ) ??
                TextStyle(color: fg, fontSize: AppTokens.fontSizeCaption),
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
