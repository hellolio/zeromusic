import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/ui/components/glass_overlay.dart';

import 'helpers.dart';
import 'support/fake_data_layer.dart';

/// 居中弹窗：尺寸钳制（宽 ≤ 80% 屏宽）与转场期背景模糊渐变
/// （弹窗动画过程中模糊即生效，而非完全展开后才突变）。
void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final layer = FakeDataLayer();
    await tester.pumpWidget(wrapApp(overrides: fakeDataLayerOverrides(layer)));
    await tester.pumpAndSettle();
  }

  /// 进入导入页并点「Cloud」卡片打开「即将支持」弹窗（转场推进到中途）。
  Future<void> openComingSoonPopup(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('弹窗宽度不超过屏宽 80%', (tester) async {
    await pumpApp(tester); // 390 宽 → 上限 312。
    await openComingSoonPopup(tester);
    await tester.pumpAndSettle();

    final rect = tester.getRect(
      find.ancestor(
        of: find.text('Coming soon'),
        matching: find.byType(GlassOverlay),
      ),
    );
    expect(rect.width, lessThanOrEqualTo(390 * 0.8 + 0.5));
    // 按钮撑满可用宽度：内容会拉伸到上限宽，而非缩到内容最小宽。
    expect(rect.width, greaterThan(260));
  });

  testWidgets('弹窗转场期间背景模糊即生效（渐变而非突变）', (tester) async {
    await pumpApp(tester);
    await openComingSoonPopup(tester);

    // 转场进行中（未 settle）：背景模糊层已在渲染。
    expect(find.byKey(const ValueKey('popupBackdropBlur')), findsOneWidget);

    // 完全展开后依然存在（保持模糊背景）。
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('popupBackdropBlur')), findsOneWidget);

    // 关闭弹窗后模糊层移除。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('popupBackdropBlur')), findsNothing);
  });
}
