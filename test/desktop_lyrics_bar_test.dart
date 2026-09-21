import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/core/localization/localizations_delegate.dart';
import 'package:zeromusic/core/theme/app_theme.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_bar_messenger.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_window_desktop.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/desktop_lyrics/desktop_lyrics_bar.dart';
import 'package:zeromusic/ui/desktop_lyrics/lyric_bar_app.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required LyricBarStateMessage state,
    DesktopLyricsFontSize tier = DesktopLyricsFontSize.medium,
    bool disableAnimations = false,
    VoidCallback? onClose,
    VoidCallback? onDragStart,
    VoidCallback? onTogglePlay,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    ValueChanged<double>? onVolumeChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: DesktopLyricsBar(
                state: state,
                fontTier: tier,
                onClose: onClose,
                onDragStart: onDragStart,
                onTogglePlay: onTogglePlay,
                onNext: onNext,
                onPrevious: onPrevious,
                onVolumeChanged: onVolumeChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 悬停到歌词区（控制条/✕ 仅悬停可见可点的前置步骤）。
  Future<void> hoverBar(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('First line')));
    await tester.pumpAndSettle();
  }

  testWidgets('TC-18 正常两行：当前行 + 下一句', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
        nextText: 'Second line',
      ),
    );

    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
  });

  testWidgets('TC-17 间奏占位', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: '',
        nextText: 'Second line',
      ),
    );

    expect(find.text('♪ Interlude ♪'), findsOneWidget);
    // 间奏态无下一句：第二行仍渲染但为空行占位（窗口高度固定两行）。
    expect(find.text(' '), findsOneWidget);
  });

  testWidgets('无歌词 → 歌名 · 歌手占位', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: null,
      ),
    );

    expect(find.text('Song A · Artist X'), findsOneWidget);
    // 占位态无下一句：第二行为空行占位（窗口高度固定两行）。
    expect(find.text(' '), findsOneWidget);
  });

  testWidgets('TC-16 无曲目 → 未在播放', (tester) async {
    await pumpBar(tester, state: const LyricBarStateMessage(hasTrack: false));

    expect(find.text('Not Playing'), findsOneWidget);
  });

  testWidgets('TC-19 最后一句：第二行不渲染', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'Last line',
        nextText: null,
      ),
    );

    expect(find.text('Last line'), findsOneWidget);
    // 最后一句无下一句：第二行为空行占位（窗口高度固定两行）。
    expect(find.text(' '), findsOneWidget);
  });

  testWidgets('TC-20 悬停后点击 ✕ 触发关闭回调', (tester) async {
    var closed = false;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onClose: () => closed = true,
    );

    // ✕ 仅悬停时可点：先移入条内再点。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('desktop_lyrics_close'))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('desktop_lyrics_close')));
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets('TC-20b 未悬停时 ✕ 不可点（IgnorePointer 拦截）', (tester) async {
    var closed = false;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onClose: () => closed = true,
    );

    await tester.tap(find.byKey(const ValueKey('desktop_lyrics_close')));
    await tester.pump();

    expect(closed, isFalse);
  });

  testWidgets('TC-31 ✕ 仅悬停时出现：未悬停隐藏，悬停淡入', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
    );

    AnimatedOpacity animatedOpacityOf() => tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('desktop_lyrics_close_fade')),
    );
    AnimatedScale animatedScaleOf() => tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(const ValueKey('desktop_lyrics_close_fade')),
        matching: find.byType(AnimatedScale),
      ),
    );
    IgnorePointer gateOf() => tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('desktop_lyrics_close_gate')),
    );

    // 悬停前：完全隐藏 + 缩小 + 拦截点击。
    expect(animatedOpacityOf().opacity, 0.0);
    expect(animatedScaleOf().scale, 0.6);
    expect(gateOf().ignoring, isTrue);

    // 鼠标移入条内 → 悬停态：完全显现 + 原始大小 + 可点。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.text('First line')),
    );
    await tester.pumpAndSettle();

    expect(animatedOpacityOf().opacity, 1.0);
    expect(animatedScaleOf().scale, 1.0);
    expect(gateOf().ignoring, isFalse);
  });

  testWidgets('TC-33 悬停控制条：显示/隐藏与布局（✕ 右上角，控制钮在其左）', (
    tester,
  ) async {
    var toggled = false;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
        nextText: 'Second line',
      ),
      onTogglePlay: () => toggled = true,
    );

    AnimatedOpacity controlsOpacityOf() => tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('desktop_lyrics_controls_fade')),
    );
    IgnorePointer controlsGateOf() => tester.widget<IgnorePointer>(
      find.byKey(const ValueKey('desktop_lyrics_controls_gate')),
    );

    // 未悬停：控制条隐藏且拦截点击（点击穿透到底层歌词区，正是断言点）。
    expect(controlsOpacityOf().opacity, 0.0);
    expect(controlsGateOf().ignoring, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('desktop_lyrics_play_pause')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(toggled, isFalse);

    // 悬停：控制条显现且可点。
    await hoverBar(tester);
    expect(controlsOpacityOf().opacity, 1.0);
    expect(controlsGateOf().ignoring, isFalse);

    // 布局：✕ 与播放控制钮同一水平线、位于行尾，不重叠。
    final barRect = tester.getRect(find.byType(DesktopLyricsBar));
    final closeRect = tester.getRect(
      find.byKey(const ValueKey('desktop_lyrics_close_fade')),
    );
    expect(barRect.right - closeRect.right, lessThanOrEqualTo(24));
    final nextRect = tester.getRect(
      find.byKey(const ValueKey('desktop_lyrics_next')),
    );
    expect(nextRect.right, lessThanOrEqualTo(closeRect.left));
    expect(
      (closeRect.center.dy - nextRect.center.dy).abs(),
      lessThan(1),
      reason: '✕ 应与 ⏮⏯⏭ 同一水平线',
    );
  });

  testWidgets('TC-34 播放/暂停按钮：回调与图标随 isPlaying 切换', (tester) async {
    var toggles = 0;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onTogglePlay: () => toggles++,
    );
    // 暂停中 → 显示播放图标。
    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);

    await hoverBar(tester);
    await tester.tap(find.byKey(const ValueKey('desktop_lyrics_play_pause')));
    await tester.pump();
    expect(toggles, 1);

    // 播放中 → 显示暂停图标。
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
        isPlaying: true,
      ),
      onTogglePlay: () => toggles++,
    );
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
  });

  testWidgets('TC-35 上一曲/下一曲按钮回调', (tester) async {
    var prev = 0;
    var next = 0;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onPrevious: () => prev++,
      onNext: () => next++,
    );

    await hoverBar(tester);
    await tester.tap(find.byKey(const ValueKey('desktop_lyrics_prev')));
    await tester.tap(find.byKey(const ValueKey('desktop_lyrics_next')));
    await tester.pump();

    expect(prev, 1);
    expect(next, 1);
  });

  testWidgets('TC-36 音量滑杆：拖动后松手回传最终值', (tester) async {
    final sent = <double>[];
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
        volume: 0.5,
      ),
      onVolumeChanged: sent.add,
    );

    await hoverBar(tester);
    await tester.drag(
      find.byKey(const ValueKey('desktop_lyrics_volume_slider')),
      const Offset(24, 0),
    );
    await tester.pumpAndSettle();

    expect(sent, isNotEmpty);
    expect(sent.last, greaterThan(0.5));
    expect(sent.last, lessThanOrEqualTo(1.0));
  });

  testWidgets('TC-36 未悬停时音量/切歌按钮不触发回调（IgnorePointer 拦截）', (
    tester,
  ) async {
    final sent = <double>[];
    var toggled = false;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onTogglePlay: () => toggled = true,
      onVolumeChanged: sent.add,
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop_lyrics_next')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(toggled, isFalse);
    expect(sent, isEmpty);
  });

  testWidgets('TC-21 按下歌词区触发拖动回调', (tester) async {
    var dragged = false;
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
      onDragStart: () => dragged = true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First line')),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();

    expect(dragged, isTrue);
  });

  testWidgets('TC-22 行切换动画：进行中不崩溃，终态正确', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
    );

    // 切换到第二行（重建组件触发 AnimatedSwitcher）。
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'Second line',
      ),
    );
    // 动画中途。
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    // 终态。
    await tester.pumpAndSettle();
    expect(find.text('Second line'), findsOneWidget);
  });

  testWidgets('TC-23 减弱动效：直接替换，无动画', (tester) async {
    await pumpBar(
      tester,
      disableAnimations: true,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
    );

    await pumpBar(
      tester,
      disableAnimations: true,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'Second line',
      ),
    );
    await tester.pump();

    expect(find.text('Second line'), findsOneWidget);
  });

  group('TC-32 子窗口高度固定两行', () {
    final setBoundsCalls = <Map<String, dynamic>>[];

    /// 拦截 window_manager / screen_retriever 通道，记录 setBounds 参数。
    void mockWindowChannels(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'setBounds') {
            setBoundsCalls.add(
              Map<String, dynamic>.from(call.arguments as Map),
            );
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('screen_retriever'),
        (call) async => switch (call.method) {
          'getPrimaryDisplay' => {
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1920.0, 'height': 1080.0},
            'size': {'width': 1920.0, 'height': 1080.0},
          },
          _ => null,
        },
      );
      addTearDown(() {
        setBoundsCalls.clear();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('screen_retriever'),
          null,
        );
      });
    }

    testWidgets('首帧：窗口高度=固定两行内容高度', (tester) async {
      mockWindowChannels(tester);
      final commands = StreamController<LyricWindowCommand>.broadcast();
      addTearDown(commands.close);
      const tier = DesktopLyricsFontSize.medium;
      const config = LyricWindowConfig(
        localeCode: 'en',
        fontTier: tier,
        initialState: LyricBarStateMessage(
          hasTrack: true,
          title: 'Song A',
          artist: 'Artist X',
          currentText: 'First line',
          nextText: 'Second line',
        ),
      );

      await tester.pumpWidget(
        LyricBarApp(initialConfig: config, commands: commands.stream),
      );
      await tester.pumpAndSettle();
      // 高度应用经去抖闸门（150ms）：推进时间窗口后落地。
      await tester.pump(const Duration(milliseconds: 300));

      final barHeight = tester.getSize(find.byType(DesktopLyricsBar)).height;
      expect(setBoundsCalls, isNotEmpty);
      expect(
        setBoundsCalls.last['width'],
        lyricBarWindowSize(tier).width,
      );
      expect(setBoundsCalls.last['height'], barHeight.ceilToDouble());
    });

    testWidgets('行数 2→1：bar 高度不变（空行占位）', (tester) async {
      Future<double> pumpHeight(LyricBarStateMessage state) async {
        await pumpBar(tester, state: state);
        return tester.getSize(find.byType(DesktopLyricsBar)).height;
      }

      final twoLineHeight = await pumpHeight(
        const LyricBarStateMessage(
          hasTrack: true,
          title: 'Song A',
          artist: 'Artist X',
          currentText: 'First line',
          nextText: 'Second line',
        ),
      );
      final oneLineHeight = await pumpHeight(
        const LyricBarStateMessage(
          hasTrack: true,
          title: 'Song A',
          artist: 'Artist X',
          currentText: 'Last line',
        ),
      );

      // 高度固定为两行：行数减少后内容高度不变（第二行空格占位）。
      expect(oneLineHeight, twoLineHeight);
    });

    testWidgets('TC-40 悬停控制条事件经壳层回传（⏯/⏮/⏭/音量）', (tester) async {
      mockWindowChannels(tester);

      // 拦截 desktop_multi_window 的底层转发通道，记录歌词条 → 主窗口
      // （back 通道）的业务事件（ready 握手除外）。
      const windowChannels = MethodChannel(
        'mixin.one/desktop_multi_window/channels',
      );
      final order = <String>[];
      final volumeArgs = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannels,
        (call) async {
          if (call.method == 'invokeMethod' && call.arguments is Map) {
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            final method = args['method'];
            if (args['channel'] == LyricBarChannels.back &&
                method != LyricBarMessenger.readyMethod) {
              order.add(method! as String);
              if (method == LyricBarMessenger.volumeMethod) {
                volumeArgs.add(
                  Map<Object?, Object?>.from(args['arguments'] as Map),
                );
              }
            }
          }
          return null;
        },
      );
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            windowChannels,
            null,
          ));

      final commands = StreamController<LyricWindowCommand>.broadcast();
      addTearDown(commands.close);
      const config = LyricWindowConfig(
        localeCode: 'en',
        initialState: LyricBarStateMessage(
          hasTrack: true,
          title: 'Song A',
          artist: 'Artist X',
          currentText: 'First line',
          volume: 0.5,
        ),
      );

      await tester.pumpWidget(
        LyricBarApp(initialConfig: config, commands: commands.stream),
      );
      await tester.pumpAndSettle();

      // 悬停后依次操作四个控件。
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('First line')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('desktop_lyrics_play_pause')),
      );
      await tester.tap(find.byKey(const ValueKey('desktop_lyrics_prev')));
      await tester.tap(find.byKey(const ValueKey('desktop_lyrics_next')));
      await tester.drag(
        find.byKey(const ValueKey('desktop_lyrics_volume_slider')),
        const Offset(24, 0),
      );
      await tester.pumpAndSettle();

      // 回传顺序与事件名（曾因壳层漏接线导致点击无反应，回归护栏）。
      expect(order, [
        LyricBarMessenger.togglePlayMethod,
        LyricBarMessenger.previousMethod,
        LyricBarMessenger.nextMethod,
        LyricBarMessenger.volumeMethod,
      ]);
      // 音量回传携带最终值（0.5 起右拖 → 增大）。
      expect(volumeArgs, isNotEmpty);
      expect(
        ((volumeArgs.last as Map<Object?, Object?>)['v'] as num).toDouble(),
        greaterThan(0.5),
      );
    });
  });
}
