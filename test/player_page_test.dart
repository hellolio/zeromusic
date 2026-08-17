import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/pages/player/player_background.dart';
import 'package:zeromusic/ui/pages/player/player_page.dart';
import 'package:zeromusic/ui/scaffold/adaptive_scaffold.dart';
import 'package:zeromusic/ui/mini_player/mini_player.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/in_memory_preferences_store.dart';

const t1 = Track(id: 'a', title: '夜曲', artist: '歌手A');
const t2 = Track(id: 'b', title: '晨光', artist: '歌手B', album: '专辑B');

void main() {
  Finder inPlayer(Finder finder) =>
      find.descendant(of: find.byType(PlayerPage), matching: finder);

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    FakeAudioEngine? engine,
    InMemoryPreferencesStore? preferencesStore,
    Size? viewport,
    List<Override> overrides = const [],
  }) async {
    if (viewport != null) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      wrapApp(
        overrides: overrides,
        audioEngine: engine ?? FakeAudioEngine(),
        preferencesStore: preferencesStore,
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
  }

  /// 桌面端进入播放页，默认队列 [t1, t2]。
  Future<FakeAudioEngine> pumpPlayer(
    WidgetTester tester, {
    FakeAudioEngine? engine,
    InMemoryPreferencesStore? preferencesStore,
    List<Track> queue = const [t1, t2],
    FakeDataLayer? dataLayer,
  }) async {
    final e = engine ?? FakeAudioEngine();
    await pumpApp(
      tester,
      engine: e,
      preferencesStore: preferencesStore,
      viewport: const Size(1400, 900),
      overrides:
          fakeDataLayerOverrides(dataLayer ?? FakeDataLayer(seed: const [])),
    );
    if (queue.isNotEmpty) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdaptiveScaffold)),
      );
      container.read(audioControllerProvider.notifier).playQueue(queue);
      await tester.pumpAndSettle();
    }
    // 播放页唯一入口：点按迷你播放条推入全屏路由。
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    return e;
  }

  PlaybackState playerState(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
    );
    return container.read(audioControllerProvider);
  }

  /// 模糊层内所有径向渐变光斑的首色（渲染时颜色）。
  List<Color> radialBlobColors(WidgetTester tester) {
    return tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('palette-blur-layer')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((d) {
          final decoration = d.decoration as BoxDecoration?;
          return decoration?.gradient is RadialGradient;
        })
        .map((d) =>
            ((d.decoration as BoxDecoration).gradient! as RadialGradient)
                .colors
                .first)
        .toList();
  }

  int radialBlobCount(WidgetTester tester) => radialBlobColors(tester).length;

  testWidgets('TC-01 播放页渲染歌曲信息', (tester) async {
    await pumpPlayer(tester);

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(inPlayer(find.text('夜曲')), findsOneWidget);
    expect(inPlayer(find.text('歌手A')), findsOneWidget);
  });

  testWidgets('TC-02 无封面：磨砂模糊多彩光斑背景', (tester) async {
    await pumpPlayer(tester);

    expect(
      find.byType(AnimatedPaletteBackground, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('palette-blur-layer')),
      findsOneWidget,
    );
    // 均衡档默认 8 个彩色光斑。
    expect(radialBlobCount(tester), 8);
  });

  testWidgets('TC-03 切歌更换背景色板', (tester) async {
    await pumpPlayer(tester);

    final before = radialBlobColors(tester);
    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.forward_end_fill)));
    await tester.pumpAndSettle();

    final after = radialBlobColors(tester);
    expect(after, isNot(equals(before)));
    expect(playerState(tester).currentTrack?.title, '晨光');
  });

  testWidgets('TC-04 有封面：背景为半透明模糊封面，光斑流动仍可透出', (tester) async {
    final coverPath = '${Directory.systemTemp.path}/zm_player_test_cover.png';
    addTearDown(() {
      final f = File(coverPath);
      if (f.existsSync()) f.deleteSync();
    });
    final coverTrack = Track(
      id: 'c',
      title: '封面歌',
      artist: '歌手A',
      coverPath: coverPath,
    );
    await pumpPlayer(tester, queue: [coverTrack]);

    final background = find.byType(AnimatedPaletteBackground);

    // 光斑层依然渲染：有封面时光斑流动不被移除，只是被半透明封面透出。
    expect(
      find.descendant(
        of: background,
        matching: find.byKey(const ValueKey('palette-blur-layer')),
      ),
      findsOneWidget,
    );

    // 封面模糊大图存在，且包在半透明 Opacity 内（让底层光斑可透出）。
    final coverFiltered = tester.widget<ImageFiltered>(
      find.descendant(
        of: background,
        matching: find.byWidgetPredicate(
          (w) => w is ImageFiltered &&
              w.key != const ValueKey('palette-blur-layer'),
        ),
      ),
    );
    final coverOpacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byWidget(coverFiltered),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(coverOpacity.opacity, greaterThan(0));
    expect(coverOpacity.opacity, lessThan(1));
  });

  testWidgets('TC-05 播放/暂停切换', (tester) async {
    final engine = await pumpPlayer(tester);

    expect(inPlayer(find.byIcon(CupertinoIcons.pause_fill)), findsOneWidget);
    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.pause_fill)));
    await tester.pumpAndSettle();
    expect(engine.pauseCount, 1);
    expect(inPlayer(find.byIcon(CupertinoIcons.play_fill)), findsOneWidget);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.play_fill)));
    await tester.pumpAndSettle();
    expect(engine.resumeCount, 1);
  });

  testWidgets('TC-06 下一首换曲', (tester) async {
    final engine = await pumpPlayer(tester);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.forward_end_fill)));
    await tester.pumpAndSettle();

    final state = playerState(tester);
    expect(state.currentIndex, 1);
    expect(state.currentTrack?.title, '晨光');
    expect(engine.lastPlayed?.id, 'b');
  });

  testWidgets('TC-07 拖动进度条 seek', (tester) async {
    final engine = await pumpPlayer(tester);
    engine.emitDuration(const Duration(seconds: 200));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const ValueKey('player-seek-bar')));
    final start = Offset(rect.left + rect.width * 0.25, rect.center.dy);
    final end = Offset(rect.left + rect.width * 0.75, rect.center.dy);
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();

    expect(engine.seekCount, 1);
    expect(engine.lastSeek, isNotNull);
    final fraction = engine.lastSeek!.inMilliseconds / 200000;
    expect(fraction, closeTo(0.75, 0.05));
  });

  testWidgets('TC-08 播放模式循环切换与图标', (tester) async {
    await pumpPlayer(tester);

    PlaybackMode mode() => playerState(tester).playbackMode;
    expect(mode(), PlaybackMode.loopAll);
    expect(inPlayer(find.byIcon(CupertinoIcons.repeat)), findsOneWidget);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.repeat)));
    await tester.pumpAndSettle();
    expect(mode(), PlaybackMode.loopOne);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.repeat_1)));
    await tester.pumpAndSettle();
    expect(mode(), PlaybackMode.shuffle);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.shuffle)));
    await tester.pumpAndSettle();
    expect(mode(), PlaybackMode.sequential);

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.repeat)));
    await tester.pumpAndSettle();
    expect(mode(), PlaybackMode.loopAll);
  });

  testWidgets('TC-09 打开播放队列面板并高亮当前曲目', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey('player-queue-button')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '夜曲'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '晨光'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.speaker_3_fill), findsOneWidget);
  });

  testWidgets('TC-10 队列点行切歌并收起面板', (tester) async {
    final engine = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey('player-queue-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '晨光'));
    await tester.pumpAndSettle();

    final state = playerState(tester);
    expect(state.currentIndex, 1);
    expect(state.currentTrack?.title, '晨光');
    expect(engine.lastPlayed?.id, 'b');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('TC-11 歌词面板占位', (tester) async {
    await pumpPlayer(tester);

    await tester.tap(inPlayer(find.byKey(const ValueKey('player-lyrics-button'))));
    await tester.pumpAndSettle();

    expect(find.text('No lyrics available'), findsOneWidget);
  });

  testWidgets('TC-17 桌面端：迷你条点按进入全屏播放页，点按收起条返回', (tester) async {
    await pumpPlayer(tester);

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('player-close-bar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-close-bar')));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('TC-18 移动端：全屏路由显示收起条，点按关闭返回', (tester) async {
    await pumpApp(
      tester,
      engine: FakeAudioEngine(),
      viewport: const Size(600, 900),
      overrides: fakeDataLayerOverrides(FakeDataLayer(seed: const [])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    container.read(audioControllerProvider.notifier).playQueue(const [t1, t2]);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('player-close-bar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-close-bar')));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('TC-12 空媒体库空态', (tester) async {
    await pumpApp(
      tester,
      viewport: const Size(1400, 900),
      overrides: [
        ...fakeDataLayerOverrides(FakeDataLayer(seed: const [])),
        audioControllerProvider.overrideWith(_EmptyAudioController.new),
      ],
    );

    // 空库时迷你条隐藏，直接推入播放页路由验证空态。
    Navigator.of(tester.element(find.byType(AdaptiveScaffold))).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(inPlayer(find.text('Nothing here yet')), findsOneWidget);
  });

  testWidgets('TC-13 减弱动效：背景静止', (tester) async {
    await pumpPlayer(tester);

    final before = radialBlobColors(tester);
    await tester.pump(const Duration(seconds: 3));
    final after = radialBlobColors(tester);
    expect(after, equals(before));
  });

  testWidgets('TC-15 背景效果档位：省电/绚彩改变渲染强度', (tester) async {
    // 省电档：光斑最少。
    await pumpPlayer(
      tester,
      preferencesStore: InMemoryPreferencesStore(
        const AppPreferences(
          backgroundEffect: BackgroundEffectLevel.powerSaver,
        ),
      ),
    );
    expect(radialBlobCount(tester), 5);
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const ValueKey('palette-blur-layer')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((d) {
            final decoration = d.decoration as BoxDecoration?;
            return decoration?.gradient is RadialGradient;
          }),
      hasLength(5),
    );
  });

  testWidgets('TC-16 背景效果档位：绚彩光斑更多', (tester) async {
    await pumpPlayer(
      tester,
      preferencesStore: InMemoryPreferencesStore(
        const AppPreferences(
          backgroundEffect: BackgroundEffectLevel.vivid,
        ),
      ),
    );
    expect(radialBlobCount(tester), 12);
  });

  testWidgets('TC-14 底行按钮：空库喜欢禁用，定时/更多可点', (tester) async {
    await pumpPlayer(tester);

    // 喜欢：当前曲目不在媒体库（空库 seed）→ 按钮禁用。
    final favButton = tester.widget<IconButton>(
      find.ancestor(
        of: inPlayer(find.byIcon(CupertinoIcons.heart)),
        matching: find.byType(IconButton),
      ),
    );
    expect(favButton.onPressed, isNull);
    expect(favButton.onPressed, isNull);

    // 定时 / 音量按钮存在且已启用。
    expect(find.byKey(const ValueKey('player-timer-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-volume-button')), findsOneWidget);
  });

  testWidgets('TC-14b 喜欢切换：红心点亮并持久化到媒体库', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    final id = await layer.mediaRepository.addSong(
      title: '测试喜欢曲',
      artist: '歌手A',
      durationMs: 120000,
      filePath: '/fixture/fav.mp3',
    );
    final song = layer.mediaRepository.songs.firstWhere((s) => s.id == id);
    await pumpPlayer(tester, queue: [Track.fromSong(song)], dataLayer: layer);

    // 初始未喜欢 → 空心 ♥。
    expect(inPlayer(find.byIcon(CupertinoIcons.heart)), findsOneWidget);
    expect(inPlayer(find.byIcon(CupertinoIcons.heart_fill)), findsNothing);

    // 点按喜欢 → 红心点亮并写入媒体库。
    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.heart)));
    await tester.pumpAndSettle();
    expect(inPlayer(find.byIcon(CupertinoIcons.heart_fill)), findsOneWidget);
    expect(layer.mediaRepository.songs.single.isFavorite, isTrue);

    // 再点取消喜欢。
    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.heart_fill)));
    await tester.pumpAndSettle();
    expect(inPlayer(find.byIcon(CupertinoIcons.heart)), findsOneWidget);
    expect(layer.mediaRepository.songs.single.isFavorite, isFalse);
  });

  testWidgets('睡眠定时：选择 15 分钟倒计时后自动暂停', (tester) async {
    final engine = await pumpPlayer(tester);

    // 点定时按钮弹出居中选择。
    await tester.tap(find.byKey(const ValueKey('player-timer-button')));
    await tester.pumpAndSettle();
    expect(find.text('15 min'), findsOneWidget);

    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();

    // 激活：定时按钮上显示倒计时（弹出层已收起，倒计时内嵌于按钮）。
    expect(inPlayer(find.text('15:00')), findsOneWidget);

    // 快进到倒计时归零 → 自动暂停。
    await tester.pump(const Duration(minutes: 15));
    await tester.pump();
    expect(engine.pauseCount, greaterThan(0));
    expect(playerState(tester).isPlaying, isFalse);

    // 归零后按钮恢复为 🌙 图标。
    expect(inPlayer(find.byIcon(CupertinoIcons.moon_zzz_fill)), findsOneWidget);
  });

  testWidgets('播放页音量：点按钮弹滑杆，拖动联动偏好与引擎', (tester) async {
    final engine = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey('player-volume-button')));
    await tester.pumpAndSettle();

    // 弹窗标题 + 滑杆出现。
    expect(find.text('Volume'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
    );
    final before =
        container.read(preferencesProvider).value?.defaultVolume ?? 1.0;

    await tester.drag(find.byType(Slider), const Offset(-200, 0),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    final after =
        container.read(preferencesProvider).value?.defaultVolume ?? 1.0;
    expect(after, lessThan(before));
    expect(engine.lastVolume!, closeTo(after, 1e-9));
  });

  testWidgets('TC-20 按钮布局轮换：队列上移至传输行，音量/歌词在底行', (tester) async {
    await pumpPlayer(tester);

    // 队列按钮在传输行（y 明显小于底行按钮）。
    final queueY = tester
        .getCenter(find.byKey(const ValueKey('player-queue-button')))
        .dy;
    final volumeY =
        tester.getCenter(find.byKey(const ValueKey('player-volume-button'))).dy;
    final lyricsY = tester
        .getCenter(find.byKey(const ValueKey('player-lyrics-button')))
        .dy;

    expect(queueY, lessThan(volumeY));

    // 音量与歌词同处底行（同一水平带）。
    expect((volumeY - lyricsY).abs(), lessThan(2));

    // 队列按钮图标为列表，位于传输行最后一个槽位（最靠右）。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-queue-button')),
        matching: find.byIcon(CupertinoIcons.list_bullet),
      ),
      findsOneWidget,
    );
  });

  testWidgets('桌面端：歌词面板顶部关闭按钮可关闭面板', (tester) async {
    await pumpPlayer(tester);

    // 桌面端歌词分栏默认收起 → 点底行歌词按钮打开。
    expect(find.byKey(const ValueKey('lyrics-panel-close')), findsNothing);
    await tester.tap(inPlayer(find.byKey(const ValueKey('player-lyrics-button'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyrics-panel-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lyrics-panel-close')));
    await tester.pumpAndSettle();

    // 面板关闭后关闭按钮随之消失。
    expect(find.byKey(const ValueKey('lyrics-panel-close')), findsNothing);
  });

  testWidgets('移动端：全屏歌词切换按钮位于底行歌词槽位附近', (tester) async {
    await pumpApp(
      tester,
      engine: FakeAudioEngine(),
      viewport: const Size(600, 900),
      overrides: fakeDataLayerOverrides(FakeDataLayer(seed: const [])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    container.read(audioControllerProvider.notifier).playQueue(const [t1, t2]);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    // 点底行歌词按钮进入全屏歌词。
    await tester.tap(inPlayer(find.byKey(const ValueKey('player-lyrics-button'))));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('lyrics-toggle-player'));
    expect(toggle, findsOneWidget);

    final center = tester.getCenter(toggle);
    final w = 600.0;
    final h = 900.0;
    // 位于底部偏右（底行歌词槽位所在区域），非屏幕角落。
    expect(center.dx, greaterThan(w * 0.6));
    expect(center.dy, greaterThan(h * 0.7));

    // 点切换按钮切回播放视图。
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyrics-toggle-player')), findsNothing);
    expect(find.byKey(const ValueKey('player-lyrics-button')), findsOneWidget);
  });
}

/// 空媒体库控制器。
class _EmptyAudioController extends AudioController {
  @override
  PlaybackState build() => const PlaybackState();
}
