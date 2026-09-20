import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/main.dart';
import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/audio_engine_provider.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/mini_player/mini_player.dart';
import 'package:zeromusic/ui/scaffold/adaptive_scaffold.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/in_memory_preferences_store.dart';

const t1 = Track(id: 'a', title: '夜曲', artist: '歌手A');
const t2 = Track(id: 'b', title: '晨光', artist: '歌手B');

/// 动画开启（不加 _NoAnimations）的手势专项：验证「滑完必然回弹复位、可打断、
/// 不残留卡死」——这是真实设备路径，`wrapApp`（减弱动效）覆盖不到。
void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final layer = FakeDataLayer(seed: const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          preferencesStoreProvider.overrideWithValue(
            InMemoryPreferencesStore(),
          ),
          ...fakeDataLayerOverrides(layer),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
  }

  Future<void> pumpWithQueue(WidgetTester tester) async {
    final container = await pumpApp(tester);
    final audio = container.read(audioControllerProvider.notifier);
    audio.play(t1);
    audio.enqueue(t2);
    await tester.pumpAndSettle();
  }

  double contentX(WidgetTester tester, String text) =>
      tester.getCenter(find.text(text)).dx;

  testWidgets('小幅拖动后松手：内容回弹到初始位置', (tester) async {
    await pumpWithQueue(tester);

    final beforeX = contentX(tester, '夜曲');
    final g = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g.moveBy(const Offset(-40, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    final afterX = contentX(tester, '夜曲');
    expect(
      (afterX - beforeX).abs(),
      lessThan(1),
      reason: '小幅拖动松手后应回弹，实际偏移 ${afterX - beforeX}',
    );
  });

  testWidgets('左滑切歌后内容回到初始位置', (tester) async {
    await pumpWithQueue(tester);

    final beforeX = contentX(tester, '夜曲');
    await tester.fling(find.byType(MiniPlayer), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('晨光'), findsOneWidget);
    final afterX = contentX(tester, '晨光');
    expect(
      (afterX - beforeX).abs(),
      lessThan(1),
      reason: '切歌后内容应回到初始位置，实际偏移 ${afterX - beforeX}',
    );
  });

  testWidgets('连续多次滑动后仍可正常滑动且回弹', (tester) async {
    await pumpWithQueue(tester);

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(MiniPlayer), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
    }
    expect(find.text('晨光'), findsOneWidget);

    final beforeX = contentX(tester, '晨光');
    final g = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    final afterX = contentX(tester, '晨光');
    expect(
      (afterX - beforeX).abs(),
      lessThan(1),
      reason: '连续滑动后小幅拖动仍应回弹，实际偏移 ${afterX - beforeX}',
    );
  });

  testWidgets('换歌动画中重新按下：打断接管，松手后复位不卡死', (tester) async {
    await pumpWithQueue(tester);

    // 快速左滑触发换歌动画（约 450ms），动画未结束时立刻再按下滑动。
    final g1 = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g1.moveBy(const Offset(-260, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 60)); // 仍在 out/slideIn 中

    final g2 = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g2.moveBy(const Offset(40, 0));
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();

    // 打断后最终收敛：不残留卡住，且后续仍可正常滑动。
    final beforeX = contentX(tester, '晨光');
    final g3 = await tester.startGesture(
      tester.getCenter(find.byType(MiniPlayer)),
    );
    await g3.moveBy(const Offset(-30, 0));
    await tester.pump();
    await g3.up();
    await tester.pumpAndSettle();
    expect(
      (contentX(tester, '晨光') - beforeX).abs(),
      lessThan(1),
      reason: '打断后应复位且仍可滑动，实际偏移 ${contentX(tester, "晨光") - beforeX}',
    );
  });
}
