import 'dart:async';

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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
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
    // 间奏态单行显示：第二行不渲染。
    expect(find.byKey(const ValueKey('next')), findsNothing);
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
    // 占位态没有下一句。
    expect(find.byKey(const ValueKey('next')), findsNothing);
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
    expect(find.byKey(const ValueKey('next')), findsNothing);
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

  group('TC-32 子窗口高度自适应内容', () {
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

    testWidgets('首帧收缩：窗口高度自适应到实测内容高度', (tester) async {
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

      final barHeight = tester.getSize(find.byType(DesktopLyricsBar)).height;
      expect(setBoundsCalls, isNotEmpty);
      expect(
        setBoundsCalls.last['width'],
        lyricBarWindowSize(tier).width,
      );
      expect(setBoundsCalls.last['height'], barHeight.ceilToDouble());
    });

    testWidgets('行数 2→1：再次收缩且高度跟着变', (tester) async {
      mockWindowChannels(tester);
      final commands = StreamController<LyricWindowCommand>.broadcast();
      addTearDown(commands.close);
      const twoLineConfig = LyricWindowConfig(
        localeCode: 'en',
        initialState: LyricBarStateMessage(
          hasTrack: true,
          title: 'Song A',
          artist: 'Artist X',
          currentText: 'First line',
          nextText: 'Second line',
        ),
      );

      await tester.pumpWidget(
        LyricBarApp(initialConfig: twoLineConfig, commands: commands.stream),
      );
      await tester.pumpAndSettle();
      final twoLineHeight = tester
          .getSize(find.byType(DesktopLyricsBar))
          .height;
      final afterTwoLineCalls = setBoundsCalls.length;

      // 最后一句：第二行消失 → 内容变矮 → 窗口再次收缩。
      commands.add(
        const ConfigureCommand(
          LyricWindowConfig(
            localeCode: 'en',
            initialState: LyricBarStateMessage(
              hasTrack: true,
              title: 'Song A',
              artist: 'Artist X',
              currentText: 'Last line',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final oneLineHeight = tester
          .getSize(find.byType(DesktopLyricsBar))
          .height;
      expect(oneLineHeight, lessThan(twoLineHeight));
      expect(setBoundsCalls.length, greaterThan(afterTwoLineCalls));
      expect(setBoundsCalls.last['height'], oneLineHeight.ceilToDouble());
    });
  });
}
