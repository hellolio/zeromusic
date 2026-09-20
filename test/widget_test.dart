import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/ui/mini_player/mini_player.dart';
import 'package:zeromusic/ui/pages/import/import_page.dart';
import 'package:zeromusic/ui/pages/player/player_page.dart';
import 'package:zeromusic/ui/pages/playlist/playlist_page.dart';
import 'package:zeromusic/ui/pages/settings/settings_page.dart';
import 'package:zeromusic/ui/scaffold/adaptive_scaffold.dart';
import 'package:zeromusic/ui/scaffold/app_side_bar.dart';
import 'package:zeromusic/ui/scaffold/glass_nav_bar.dart';

import 'helpers.dart';
import 'support/fake_data_layer.dart';

const _testTrack = Track(id: '1', title: '测试歌曲', artist: '测试歌手');

/// 提供当前曲目的控制器（用于迷你条可见性测试）。
class _TrackedAudioController extends AudioController {
  @override
  PlaybackState build() =>
      const PlaybackState(queue: [_testTrack], currentIndex: 0);
}

/// 空媒体库控制器（验证无曲目时隐藏）。
class _EmptyAudioController extends AudioController {
  @override
  PlaybackState build() => const PlaybackState();
}

final _trackedOverride = [
  audioControllerProvider.overrideWith(_TrackedAudioController.new),
];

final _emptyOverride = [
  audioControllerProvider.overrideWith(_EmptyAudioController.new),
];

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    final layer = FakeDataLayer();
    await tester.pumpWidget(
      wrapApp(overrides: [...fakeDataLayerOverrides(layer), ...overrides]),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('骨架冒烟测试：应用可构建且三个主页面可切换', (tester) async {
    await pumpApp(tester);

    // 默认展示播放列表页。
    expect(find.byType(AdaptiveScaffold), findsOneWidget);
    expect(find.byType(PlaylistPage), findsOneWidget);

    // 底栏三个目的地存在（移动端布局下，液态玻璃胶囊）。
    expect(find.byType(GlassNavBar), findsOneWidget);
    // 未选中的导入页图标存在（当前播放列表选中态显示实心图标）。
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);

    // 切到导入页。
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);

    // 切到设置页。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('迷你条：无当前曲目时彻底隐藏（不占布局空间）', (tester) async {
    await pumpApp(tester, overrides: _emptyOverride);

    // 无播放曲目：迷你条不渲染任何动画/内容，不占位。
    expect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byType(AnimatedOpacity),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('迷你条：有曲目时在所有页面全局显示', (tester) async {
    await pumpApp(tester, overrides: _trackedOverride);

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('测试歌曲'), findsOneWidget);

    // 切到导入页，迷你条依然可见（全局）。
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(find.text('测试歌曲'), findsOneWidget);
  });

  testWidgets('移动端：液态玻璃底栏略高于迷你条、左右留边、含滑动指示', (tester) async {
    await pumpApp(tester, overrides: _trackedOverride);

    final navRect = tester.getRect(find.byType(GlassNavBar));
    final miniRect = tester.getRect(find.byType(MiniPlayer));

    // 底栏略高于迷你条，形成层级区分。
    expect(navRect.height, closeTo(GlassNavBar.height, 1));
    expect(navRect.height, greaterThan(miniRect.height));
    expect(navRect.height - miniRect.height, closeTo(8, 1));

    // 左右不贴屏幕边缘。
    final screenW = tester.view.physicalSize.width;
    expect(navRect.left, greaterThan(0));
    expect(screenW - navRect.right, greaterThan(0));

    // 存在滑动指示胶囊（切换动画）。
    expect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(AnimatedPositioned),
      ),
      findsOneWidget,
    );
  });

  testWidgets('迷你条：点播放/暂停按钮切换 isPlaying', (tester) async {
    await pumpApp(tester, overrides: _trackedOverride);

    // 初始为暂停（play 图标）。
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    // 切换为播放（pause 图标）。
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('移动端：内容铺满整屏，迷你条悬浮其上（背后内容可透出）', (tester) async {
    await pumpApp(tester, overrides: _trackedOverride);

    final miniRect = tester.getRect(find.byType(MiniPlayer));
    // 外层顶级页面 PageView（播放列表内部还有分类 PageView，取 PlaylistPage 的祖先）。
    final pageViewRect = tester.getRect(
      find
          .ancestor(
            of: find.byType(PlaylistPage),
            matching: find.byType(PageView),
          )
          .first,
    );

    // 内容区（PageView）铺满整屏高度，延伸到底部，不被迷你条/底栏截断。
    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(pageViewRect.bottom, closeTo(screenH, 1));

    // 迷你条悬浮于内容区之上（顶部低于内容区底部、位于内容区范围内），
    // 背后的页面内容可透过液态玻璃显示。
    expect(miniRect.top, lessThan(pageViewRect.bottom));
    expect(miniRect.top, greaterThan(pageViewRect.top));
  });

  testWidgets('移动端：底栏页面可滑动切换（导入/设置互切，播放列表经底栏进入）', (tester) async {
    await pumpApp(tester);

    expect(find.byType(PlaylistPage), findsOneWidget);

    // 播放列表页内部自带分类滑动（见 playlist_page_test），
    // 顶级页面切换：先经底栏进入导入页，再左右滑动。
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);

    // 左滑 → 设置页。
    await tester.fling(find.byType(ImportPage), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    // 右滑 → 回到导入页，底栏高亮同步。
    await tester.fling(find.byType(SettingsPage), const Offset(500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);

    // 再经底栏回到播放列表。
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistPage), findsOneWidget);
  });

  testWidgets('桌面布局：AppSideBar 横向导航，播放页时迷你条隐藏', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, overrides: _trackedOverride);

    expect(find.byType(AppSideBar), findsOneWidget);
    expect(find.byType(GlassNavBar), findsNothing);
    expect(find.byType(PlaylistPage), findsOneWidget);
    expect(find.text('测试歌曲'), findsOneWidget);

    // 侧栏固定宽度，足以容纳横向图标 + 文字。
    expect(tester.getSize(find.byType(AppSideBar)).width, AppSideBar.width);

    // 图标在左、文字在右（横向并列且靠左）。
    final playlistIconX = tester
        .getCenter(
          find.descendant(
            of: find.byKey(const ValueKey('sidebar-playlist')),
            matching: find.byType(Icon),
          ),
        )
        .dx;
    final playlistLabelX = tester
        .getCenter(
          find.descendant(
            of: find.byKey(const ValueKey('sidebar-playlist')),
            matching: find.byType(Text),
          ),
        )
        .dx;
    expect(playlistIconX, lessThan(playlistLabelX));

    // 切到设置页，迷你条仍在。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('测试歌曲'), findsOneWidget);

    // 点迷你条推入全屏播放页。路由透明（opaque:false）：迷你条仍在树中、
    // 被全屏播放页的实心背景盖住，命中测试应落在播放页而非迷你条。
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);
    final miniRender = tester.renderObject(find.byType(MiniPlayer));
    final hits = tester
        .hitTestOnBinding(tester.getCenter(find.byType(MiniPlayer)))
        .path;
    expect(hits.any((e) => e.target == miniRender), isFalse);

    // 点收起条返回，迷你条恢复可见可交互。
    await tester.tap(find.byKey(const ValueKey('player-close-bar')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(MiniPlayer), findsOneWidget);
  });

  testWidgets('桌面端：侧栏导航项胶囊占满侧栏宽度，整行可点', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    // 导入行胶囊铺满侧栏宽度（去掉左右 padding 后贴近侧栏边缘）。
    final itemRect = tester.getRect(
      find.byKey(const ValueKey('sidebar-import')),
    );
    expect(itemRect.width, greaterThan(AppSideBar.width * 0.8));

    // 点导入行最右侧（仍在胶囊内，远离图标/文字）仍应切换页面。
    await tester.tapAt(Offset(itemRect.right - 4, itemRect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);
  });
}
