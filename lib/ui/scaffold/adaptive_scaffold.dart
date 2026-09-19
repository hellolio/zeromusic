import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anim/app_curves.dart';
import '../../core/anim/page_transitions.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/device_type.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/audio/audio_controller.dart';
import '../mini_player/mini_player.dart';
import '../pages/import/import_page.dart';
import 'app_side_bar.dart';
import 'content_bottom_inset.dart';
import 'glass_nav_bar.dart';
import 'sidebar_inset.dart';
import '../pages/player/player_page.dart';
import '../pages/playlist/playlist_page.dart';
import '../pages/settings/settings_page.dart';

/// 自适应骨架：统一处理导航布局与全局迷你播放条。
/// - 移动端：底部 TabBar（播放列表 / 导入 / 设置）+ 迷你条（底栏上方）。
/// - 桌面端：左侧 [AppSideBar]（播放列表 / 导入，设置贴底）+ 迷你条（右下角）。
/// - 播放页为全屏路由（两端一致），唯一入口是迷你播放条。
/// 页面切换使用统一的 AppPageTransition 动画。
class AdaptiveScaffold extends ConsumerStatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  ConsumerState<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends ConsumerState<AdaptiveScaffold> {
  int _index = 0;
  final PageController _pageController = PageController();

  /// 桌面端迷你条悬浮于右下角，给页面内容留出的底部空隙（迷你条高约 70px + 偏移 + 间距）。
  static const double _miniPlayerClearance = 96;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  late final List<Widget> _mobilePages = [
    PlaylistPage(onSwipeNext: _advanceFromPlaylist),
    const ImportPage(),
    const SettingsPage(),
  ];

  late final List<Widget> _desktopPages = const [
    PlaylistPage(),
    ImportPage(),
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

  /// 播放列表「最近播放」页继续左滑 → 交棒进入导入页（仅当正处于播放列表且未在滚动）。
  void _advanceFromPlaylist() {
    if (_index != 0) return;
    if (!_pageController.hasClients) return;
    if (_pageController.position.isScrollingNotifier.value) return;
    setState(() => _index = 1);
    _pageController.animateToPage(
      1,
      duration: AppCurves.pageTransition,
      curve: AppCurves.standard,
    );
  }

  /// 移动端：手势滑动切页 → 同步底栏高亮。
  void _onPageChanged(int i) {
    setState(() => _index = i);
  }

  /// 推入全屏播放页（上滑式转场）。移动端与桌面端共用：覆盖整窗（含侧栏），
  /// 收起由播放页顶部小横条负责（点按/下拉 → 弹路由回上一页）。
  void _pushPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const PlayerPage(),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppCurves.standard,
          );
          return SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
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
        // 提供左侧栏宽度，供居中弹窗等忽略左侧栏做水平居中。
        final inset = device == DeviceType.desktop ? AppSideBar.width : 0.0;
        return SidebarInset(
          inset: inset,
          child: device == DeviceType.desktop
              ? _buildDesktop(context, constraints)
              : _buildMobile(context, constraints),
        );
      },
    );
  }

  Widget _buildMobile(BuildContext context, BoxConstraints constraints) {
    final strings = context.strings;
    final hasTrack = ref.watch(audioControllerProvider).hasTrack;
    // 底部悬浮玻璃占用的高度（迷你条 + 间隙 + 底栏），供页面滚动内容预留。
    final overlayHeight = AppTokens.spaceS +
        AppTokens.mobileMiniPlayerHeight +
        AppTokens.spaceS +
        AppTokens.mobileBottomControlHeight;
    return Scaffold(
      body: SafeArea(
        top: false,
        child: ContentBottomInset(
          // 有迷你条时为整段悬浮高度，仅底栏时只预留底栏高度，再加底部呼吸。
          inset: (hasTrack ? overlayHeight : AppTokens.spaceS +
                  AppTokens.mobileBottomControlHeight) +
              AppTokens.spaceM,
          child: Stack(
            children: [
              // 内容区：铺满整屏，滚动到迷你条/底栏之后，让液态玻璃透出背后的内容。
              Positioned.fill(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  children: _mobilePages,
                ),
              ),
              // 底部悬浮控件：迷你播放条 + 液态玻璃底栏（覆盖在内容之上）。
              // 左右留边距，胶囊不接触屏幕边缘。
              Positioned(
                left: AppTokens.spaceM,
                right: AppTokens.spaceM,
                bottom: AppTokens.spaceS,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MiniPlayer(
                      deviceType: DeviceType.mobile,
                      onTap: _pushPlayer,
                      onTogglePlay: () => ref
                          .read(audioControllerProvider.notifier)
                          .togglePlay(),
                      onNext: () =>
                          ref.read(audioControllerProvider.notifier).next(),
                      onPrev: () =>
                          ref.read(audioControllerProvider.notifier).previous(),
                    ),
                    const SizedBox(height: AppTokens.spaceS),
                    GlassNavBar(
                      selectedIndex: _index,
                      onSelected: _onNavSelected,
                      destinations: [
                        GlassNavDestination(
                          icon: Icons.library_music_outlined,
                          selectedIcon: Icons.library_music,
                          label: strings.navPlaylist,
                        ),
                        GlassNavDestination(
                          icon: Icons.download_outlined,
                          selectedIcon: Icons.download,
                          label: strings.navImport,
                        ),
                        GlassNavDestination(
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          label: strings.navSettings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, BoxConstraints constraints) {
    // 迷你条可见（有当前曲目）时，为内容区底部预留空间，
    // 让播放列表/导入/设置等滚动页面的最后一条不会被迷你条遮挡。
    final hasTrack = ref.watch(audioControllerProvider).hasTrack;
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
                  child: AnimatedPadding(
                    duration: AppCurves.miniPlayerMotion,
                    curve: AppCurves.standard,
                    padding: EdgeInsets.only(
                      bottom: hasTrack ? _miniPlayerClearance : 0,
                    ),
                    child: AppPageTransition(
                      index: _index,
                      child: _desktopPages[_index],
                    ),
                  ),
                ),
                // 桌面端迷你条固定右下角，悬浮于内容之上；点按推入全屏播放页路由。
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: MiniPlayer(
                    deviceType: DeviceType.desktop,
                    onTap: _pushPlayer,
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
