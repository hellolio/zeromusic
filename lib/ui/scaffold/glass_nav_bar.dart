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
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  /// 胶囊高度（与迷你播放条一致）；圆角取半高 → 左右倒圆角。
  static const double height = AppTokens.mobileBottomControlHeight;

  /// 滑动指示胶囊尺寸。
  static const double _pillWidth = 78;
  static const double _pillHeight = 46;

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: GlassOverlay(
        radius: height / 2,
        blur: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final count = destinations.length;
            final itemWidth = constraints.maxWidth / count;
            return Stack(
              children: [
                // 滑动玻璃指示胶囊：在项间 spring 滑移。
                AnimatedPositioned(
                  duration: AppCurves.standardMotion,
                  curve: AppCurves.spring,
                  left:
                      selectedIndex * itemWidth + (itemWidth - _pillWidth) / 2,
                  top: (height - _pillHeight) / 2,
                  width: _pillWidth,
                  height: _pillHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // 中性白底胶囊：与玻璃背景同色系，不带蓝色色相；
                      // 选中强调色仅由下方图标/文字（accent）承担。
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.12 : 0.45,
                      ),
                      borderRadius: BorderRadius.circular(_pillHeight / 2),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.10 : 0.45,
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
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
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
