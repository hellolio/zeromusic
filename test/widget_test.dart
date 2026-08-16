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

    // 底栏三个目的地存在（移动端布局下）。
    expect(find.byType(NavigationBar), findsOneWidget);
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

  testWidgets('移动端：底栏页面可滑动切换', (tester) async {
    await pumpApp(tester);

    expect(find.byType(PlaylistPage), findsOneWidget);

    // 左滑 → 导入页。
    await tester.fling(find.byType(PlaylistPage), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);

    // 再左滑 → 设置页。
    await tester.fling(find.byType(ImportPage), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    // 右滑 → 回到导入页，底栏高亮同步。
    await tester.fling(find.byType(SettingsPage), const Offset(500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);
  });

  testWidgets('桌面布局：AppSideBar 横向导航，播放页时迷你条隐藏', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, overrides: _trackedOverride);

    expect(find.byType(AppSideBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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

    // 设置项位于侧栏最底部（与其他项拉开距离）。
    final settingsY =
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-settings'))).dy;
    final playerY =
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-player'))).dy;
    expect(settingsY, greaterThan(playerY));

    // 切到设置页，迷你条仍在。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('测试歌曲'), findsOneWidget);

    // 切到播放页（索引 2），迷你条隐藏。
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    final playerOpacity = tester.widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(playerOpacity.single.opacity, 0);
  });
}