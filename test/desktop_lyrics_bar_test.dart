import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/core/localization/localizations_delegate.dart';
import 'package:zeromusic/core/theme/app_theme.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_bar_messenger.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/desktop_lyrics/desktop_lyrics_bar.dart';

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

  testWidgets('TC-20 ✕ 点击触发关闭回调', (tester) async {
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

    expect(closed, isTrue);
  });

  testWidgets('TC-31 ✕ 悬停：透明度提升 + 轻微放大', (tester) async {
    await pumpBar(
      tester,
      state: const LyricBarStateMessage(
        hasTrack: true,
        title: 'Song A',
        artist: 'Artist X',
        currentText: 'First line',
      ),
    );

    // 悬停前：低透明度常显 + 原始大小。
    AnimatedScale animatedScaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    AnimatedOpacity animatedOpacityOf() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedScaleOf().scale, 1.0);
    expect(animatedOpacityOf().opacity, 0.55);

    // 鼠标移入 ✕ → 悬停态（ AnimatedScale / AnimatedOpacity 在条内唯一）。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('desktop_lyrics_close'))),
    );
    await tester.pumpAndSettle();

    expect(animatedScaleOf().scale, 1.15);
    expect(animatedOpacityOf().opacity, 1.0);
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
}
