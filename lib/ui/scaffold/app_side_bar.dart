import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/theme/app_tokens.dart';

/// 桌面端左侧边栏（Apple Music 风格）。
///
/// - 每个导航项：图标在左、标题在右，横向并列且整体靠左。
/// - 「播放列表 / 导入 / 播放」位于上方，「设置」被 [Spacer] 推至窗口最底部。
/// - 选中项以 primary 前景 + 浅色圆角 pill 背景高亮。
class AppSideBar extends StatelessWidget {
  const AppSideBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// 侧栏固定宽度：容纳横向图标 + 文字。
  static const double width = 224;

  // ---- 导航项索引（与桌面页面数组顺序一一对应） ----
  static const int playlistIndex = 0;
  static const int importIndex = 1;
  static const int playerIndex = 2;
  static const int settingsIndex = 3;

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = context.strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          // 侧栏底色：纵向微渐变，营造柔和纵深而非平板一块。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surfaceContainerLow,
                    scheme.surfaceContainerHigh,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceL,
                    AppTokens.spaceM,
                    AppTokens.spaceL,
                    AppTokens.spaceXl,
                  ),
                  child: Icon(
                    CupertinoIcons.music_note,
                    size: 28,
                    color: scheme.primary,
                  ),
                ),
                _SideBarItem(
                  itemKey: const ValueKey('sidebar-playlist'),
                  icon: Icons.library_music_outlined,
                  selectedIcon: Icons.library_music,
                  label: strings.navPlaylist,
                  selected: selectedIndex == playlistIndex,
                  onTap: () => onSelected(playlistIndex),
                ),
                _SideBarItem(
                  itemKey: const ValueKey('sidebar-import'),
                  icon: Icons.download_outlined,
                  selectedIcon: Icons.download,
                  label: strings.navImport,
                  selected: selectedIndex == importIndex,
                  onTap: () => onSelected(importIndex),
                ),
                _SideBarItem(
                  itemKey: const ValueKey('sidebar-player'),
                  icon: Icons.play_circle_outline,
                  selectedIcon: Icons.play_circle,
                  label: strings.navPlayer,
                  selected: selectedIndex == playerIndex,
                  onTap: () => onSelected(playerIndex),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.spaceM),
                  child: _SideBarItem(
                    itemKey: const ValueKey('sidebar-settings'),
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: strings.navSettings,
                    selected: selectedIndex == settingsIndex,
                    onTap: () => onSelected(settingsIndex),
                  ),
                ),
              ],
            ),
          ),
          // 右侧软边缘：内阴影式渐变，替代硬分隔线，与主区自然过渡。
          IgnorePointer(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: isDark
                          ? [
                              Colors.white.withValues(alpha: 0.06),
                              Colors.transparent,
                            ]
                          : [
                              Colors.black.withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个侧栏导航项：图标在左、文字在右，内容靠左。
class _SideBarItem extends StatelessWidget {
  const _SideBarItem({
    required this.itemKey,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceM,
        vertical: AppTokens.spaceXs,
      ),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: InkWell(
          key: itemKey,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceM,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: fg,
                ),
                const SizedBox(width: AppTokens.spaceM),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: AppTokens.fontSizeBody,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
