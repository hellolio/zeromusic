import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anim/app_curves.dart';
import '../../core/anim/page_transitions.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/device_type.dart';
import '../../services/audio/audio_controller.dart';
import '../mini_player/mini_player.dart';
import '../pages/import/import_page.dart';
import 'app_side_bar.dart';
import '../pages/player/player_page.dart';
import '../pages/playlist/playlist_page.dart';
import '../pages/settings/settings_page.dart';

/// 自适应骨架：统一处理导航布局与全局迷你播放条。
/// - 移动端：底部 TabBar（播放列表 / 导入 / 设置）+ 迷你条（底栏上方）。
/// - 桌面端：左侧 [AppSideBar]（播放列表 / 导入 / 播放，设置贴底）+ 迷你条（右下角）。
/// 页面切换使用统一的 AppPageTransition 动画。
class AdaptiveScaffold extends ConsumerStatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  ConsumerState<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends ConsumerState<AdaptiveScaffold> {
  int _index = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  late final List<Widget> _mobilePages = const [
    PlaylistPage(),
    ImportPage(),
    SettingsPage(),
  ];

  late final List<Widget> _desktopPages = const [
    PlaylistPage(),
    ImportPage(),
    PlayerPage(),
    SettingsPage(),
  ];

  /// 移动端：底栏导航选中 → 同步滑动到对应页面。
  void _onNavSelected(int i) {
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: AppCurves.pageTransition,
      curve: AppCurves.standard,
    );
  }

  /// 移动端：手势滑动切页 → 同步底栏高亮。
  void _onPageChanged(int i) {
    setState(() => _index = i);
  }

  /// 移动端：推入全屏播放页（上滑式转场）。
  void _pushPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const PlayerPage(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: AppCurves.standard);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
        transitionDuration: AppCurves.pageTransition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final device = deviceTypeOf(constraints);
        return device == DeviceType.desktop
            ? _buildDesktop(context, constraints)
            : _buildMobile(context, constraints);
      },
    );
  }

  Widget _buildMobile(BuildContext context, BoxConstraints constraints) {
    final strings = context.strings;
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: _mobilePages,
              ),
            ),
            // 移动端：点按迷你条推入全屏播放页（进入后迷你条随路由覆盖而隐藏）。
            MiniPlayer(
              deviceType: DeviceType.mobile,
              onTap: _pushPlayer,
              onTogglePlay: () =>
                  ref.read(audioControllerProvider.notifier).togglePlay(),
              onNext: () =>
                  ref.read(audioControllerProvider.notifier).next(),
              onPrev: () =>
                  ref.read(audioControllerProvider.notifier).previous(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onNavSelected,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.library_music_outlined), selectedIcon: const Icon(Icons.library_music), label: strings.navPlaylist),
          NavigationDestination(icon: const Icon(Icons.download_outlined), selectedIcon: const Icon(Icons.download), label: strings.navImport),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: strings.navSettings),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, BoxConstraints constraints) {
    return Scaffold(
      body: Row(
        children: [
          AppSideBar(
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AppPageTransition(index: _index, child: _desktopPages[_index]),
                ),
                // 桌面端迷你条固定右下角，悬浮于内容之上。
                // 当前在播放页（索引 2）时隐藏。
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: MiniPlayer(
                    deviceType: DeviceType.desktop,
                    hidden: _index == AppSideBar.playerIndex,
                    onTap: () => setState(() => _index = AppSideBar.playerIndex),
                    onTogglePlay: () =>
                        ref.read(audioControllerProvider.notifier).togglePlay(),
                    onNext: () =>
                        ref.read(audioControllerProvider.notifier).next(),
                    onPrev: () =>
                        ref.read(audioControllerProvider.notifier).previous(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
