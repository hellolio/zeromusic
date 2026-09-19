import 'dart:convert' show base64Decode;
import 'dart:io' show Directory, File;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/ui/mini_player/mini_player.dart';
import 'package:zeromusic/ui/pages/player/player_page.dart';
import 'package:zeromusic/ui/scaffold/adaptive_scaffold.dart';
import 'package:zeromusic/ui/components/glass_overlay.dart';
import 'package:zeromusic/core/theme/app_tokens.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';

const t1 = Track(id: 'a', title: '夜曲', artist: '歌手A');
const t2 = Track(id: 'b', title: '晨光', artist: '歌手B');

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    FakeAudioEngine? engine,
    Size? viewport,
  }) async {
    if (viewport != null) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final layer = FakeDataLayer(seed: const []);
    await tester.pumpWidget(
      wrapApp(
        overrides: fakeDataLayerOverrides(layer),
        audioEngine: engine ?? FakeAudioEngine(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
  }

  /// 让迷你条出现并内置两首队列（当前 = t1）。
  Future<FakeAudioEngine> pumpWithQueue(
    WidgetTester tester, {
    Size? viewport,
  }) async {
    final engine = FakeAudioEngine();
    final container = await pumpApp(tester, engine: engine, viewport: viewport);
    final audio = container.read(audioControllerProvider.notifier);
    audio.play(t1);
    audio.enqueue(t2);
    await tester.pumpAndSettle();
    return engine;
  }

  testWidgets('移动端：左滑切换到下一首', (tester) async {
    await pumpWithQueue(tester);

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('夜曲'), findsOneWidget);

    await tester.fling(find.byType(MiniPlayer), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('晨光'), findsOneWidget);
    expect(find.text('夜曲'), findsNothing);
  });

  testWidgets('移动端：右滑切换到上一首', (tester) async {
    await pumpWithQueue(tester);

    // 先切到下一首，再右滑回上一首。
    final engine = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    final audio = engine.read(audioControllerProvider.notifier);
    audio.next();
    await tester.pumpAndSettle();
    expect(find.text('晨光'), findsOneWidget);

    await tester.fling(find.byType(MiniPlayer), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('晨光'), findsNothing);
  });

  testWidgets('移动端：小幅拖动未过阈值则回弹，曲目不切换', (tester) async {
    await pumpWithQueue(tester);

    await tester.drag(find.byType(MiniPlayer), const Offset(22, 0));
    await tester.pumpAndSettle();

    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('晨光'), findsNothing);
  });

  testWidgets('移动端：胶囊固定不动，仅内容跟手滑动并回弹', (tester) async {
    await pumpWithQueue(tester);

    final glassRect = tester.getRect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byType(GlassOverlay),
      ),
    );
    final beforeX = tester.getCenter(find.text('夜曲')).dx;

    final g = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g.moveBy(const Offset(-30, 0));
    await tester.pump();

    // 玻璃胶囊本体不动。
    final glassDuring = tester.getRect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byType(GlassOverlay),
      ),
    );
    expect(glassDuring.left, glassRect.left);
    expect(glassDuring.right, glassRect.right);
    // 内容跟随手指。
    final duringX = tester.getCenter(find.text('夜曲')).dx;
    expect(duringX - beforeX, lessThan(-20));

    await g.up();
    await tester.pumpAndSettle();
    // 松手后内容回到原位，不会停留在半途。
    final afterX = tester.getCenter(find.text('夜曲')).dx;
    expect((afterX - beforeX).abs(), lessThan(1));
  });

  testWidgets('移动端：上滑进入完整播放页', (tester) async {
    await pumpWithQueue(tester);

    await tester.fling(find.byType(MiniPlayer), const Offset(0, -300), 1200);
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('移动端：封面缺失时展示音符占位', (tester) async {
    await pumpWithQueue(tester);

    expect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byIcon(CupertinoIcons.music_note),
      ),
      findsWidgets,
    );
  });

  testWidgets('封面文件存在时渲染本地封面图', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );
    final file = File(
      '${Directory.systemTemp.path}/zeromusic_cover_test_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await tester.runAsync(() => file.writeAsBytes(bytes, flush: true));
    addTearDown(() {
      try {
        file.deleteSync();
      } catch (_) {}
    });

    final layer = FakeDataLayer(seed: const []);
    await tester.pumpWidget(
      wrapApp(
        overrides: fakeDataLayerOverrides(layer),
        audioEngine: FakeAudioEngine(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    container
        .read(audioControllerProvider.notifier)
        .play(
          Track(
            id: 'cover',
            title: '有封面',
            filePath: '/tmp/foo.mp3',
            coverPath: file.path,
          ),
        );
    await tester.pump();

    // 封面路径已接入：渲染 FileImage，且不展示兜底音符。
    final imageFinder = find.descendant(
      of: find.byType(MiniPlayer),
      matching: find.byType(Image),
    );
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(image.image, isA<FileImage>());
    expect((image.image as FileImage).file.path, file.path);
    expect(
      find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.byIcon(CupertinoIcons.music_note),
      ),
      findsNothing,
    );
  });

  testWidgets('移动端：迷你条不显示底部进度线', (tester) async {
    await pumpWithQueue(tester);

    expect(find.byKey(const ValueKey('mini-player-progress')), findsNothing);
  });

  testWidgets('移动端：点下一曲按钮切到下一首，滑动切歌仍可用', (tester) async {
    await pumpWithQueue(tester);

    expect(find.byKey(const ValueKey('mini-player-next')), findsOneWidget);
    expect(find.text('夜曲'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mini-player-next')));
    await tester.pumpAndSettle();
    expect(find.text('晨光'), findsOneWidget);
    expect(find.text('夜曲'), findsNothing);

    // 按钮存在不破坏左右滑动切歌。
    await tester.fling(find.byType(MiniPlayer), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('夜曲'), findsOneWidget);
  });

  testWidgets('移动端：迷你条左右与屏幕边缘留有间距', (tester) async {
    await pumpWithQueue(tester);

    final rect = tester.getRect(find.byType(MiniPlayer));
    final screenW = tester.view.physicalSize.width;
    expect(rect.left, greaterThan(0));
    expect(screenW - rect.right, greaterThan(0));
  });

  testWidgets('移动端：迷你条为全胶囊圆角（半径=条高一半）', (tester) async {
    await pumpWithQueue(tester);

    final glass = tester.widget<GlassOverlay>(
      find
          .ancestor(of: find.text('夜曲'), matching: find.byType(GlassOverlay))
          .first,
    );
    expect(glass.radius, AppTokens.radiusPill);
  });

  testWidgets('桌面端：显示上一首/下一首按钮并可切歌', (tester) async {
    await pumpWithQueue(tester, viewport: const Size(1400, 900));

    expect(find.byIcon(CupertinoIcons.forward_end_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.backward_end_fill), findsOneWidget);
    expect(find.text('夜曲'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.forward_end_fill));
    await tester.pumpAndSettle();
    expect(find.text('晨光'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.backward_end_fill));
    await tester.pumpAndSettle();
    expect(find.text('夜曲'), findsOneWidget);
  });

  testWidgets('桌面端：滚轮向下切到下一首、向上切到上一首', (tester) async {
    await pumpWithQueue(tester, viewport: const Size(1400, 900));

    expect(find.text('夜曲'), findsOneWidget);

    final center = tester.getCenter(find.byType(MiniPlayer));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('晨光'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -10)),
    );
    await tester.pumpAndSettle();
    expect(find.text('夜曲'), findsOneWidget);
  });

  testWidgets('桌面端：迷你条为全胶囊圆角（半径=条高一半）', (tester) async {
    await pumpWithQueue(tester, viewport: const Size(1400, 900));

    final glass = tester.widget<GlassOverlay>(
      find
          .ancestor(of: find.text('夜曲'), matching: find.byType(GlassOverlay))
          .first,
    );
    expect(glass.radius, AppTokens.radiusPill);
  });

  testWidgets('桌面端：迷你条不显示底部进度线', (tester) async {
    await pumpWithQueue(tester, viewport: const Size(1400, 900));

    expect(find.byKey(const ValueKey('mini-player-progress')), findsNothing);
  });
}
