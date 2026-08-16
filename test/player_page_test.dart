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
  }) async {
    final e = engine ?? FakeAudioEngine();
    await pumpApp(
      tester,
      engine: e,
      preferencesStore: preferencesStore,
      viewport: const Size(1400, 900),
      overrides: fakeDataLayerOverrides(FakeDataLayer(seed: const [])),
    );
    if (queue.isNotEmpty) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdaptiveScaffold)),
      );
      container.read(audioControllerProvider.notifier).playQueue(queue);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byIcon(Icons.play_circle_outline));
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

    await tester.tap(inPlayer(find.byIcon(CupertinoIcons.mic_fill)));
    await tester.pumpAndSettle();

    expect(find.text('No lyrics available'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.play_circle_outline));
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

  testWidgets('TC-14 占位按钮为禁用态', (tester) async {
    await pumpPlayer(tester);

    IconButton button(IconData icon) => tester.widget<IconButton>(
          find.ancestor(
            of: inPlayer(find.byIcon(icon)),
            matching: find.byType(IconButton),
          ),
        );
    expect(button(CupertinoIcons.heart).onPressed, isNull);
    expect(button(CupertinoIcons.ellipsis).onPressed, isNull);
    expect(button(CupertinoIcons.moon_zzz_fill).onPressed, isNull);
  });
}

/// 空媒体库控制器。
class _EmptyAudioController extends AudioController {
  @override
  PlaybackState build() => const PlaybackState();
}
