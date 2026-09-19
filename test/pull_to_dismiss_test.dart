import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/ui/pages/player/pull_to_dismiss.dart';

/// PullToDismiss 直接组件测试（不包 _NoAnimations，动画默认开启），
/// 覆盖「跟手」「回弹」「飞出退出」「飞出中接管取消」四类行为。
void main() {
  Future<void> pumpPtd(
    WidgetTester tester, {
    required VoidCallback onDismiss,
    double startAreaFraction = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToDismiss(
            onDismiss: onDismiss,
            startAreaFraction: startAreaFraction,
            child: const SizedBox.expand(
              child: ColoredBox(
                key: ValueKey('ptd-child'),
                color: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double contentTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('ptd-child'))).dy;

  testWidgets('拖动跟手：内容 1:1 跟随手指', (tester) async {
    await pumpPtd(tester, onDismiss: () {});
    expect(contentTop(tester), 0);

    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 30)); // 越过触摸 slop 建立手势
    await tester.pump();
    final before = contentTop(tester);
    expect(before, greaterThan(0)); // 已开始跟手

    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    // 后续增量 1:1 跟手，无阻尼、无延迟。
    expect(contentTop(tester) - before, closeTo(40, 2));

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('下拉未过阈值：弹性回弹，不触发退出', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    await tester.timedDrag(
      find.byType(PullToDismiss),
      const Offset(0, 80),
      const Duration(milliseconds: 300),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(dismissed, isFalse);
    // 回弹复位到原始位置。
    expect(contentTop(tester), closeTo(0, 1));
  });

  testWidgets('下拉中途反向拖回：取消退出并回弹', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 150)); // 越过阈值
    await tester.pump();
    expect(contentTop(tester), greaterThan(0));

    await g.moveBy(const Offset(0, -150)); // 反悔拖回
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(dismissed, isFalse);
    expect(contentTop(tester), closeTo(0, 1));
  });

  testWidgets('下拉快速甩动：飞出屏幕后触发退出', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    await tester.fling(
      find.byType(PullToDismiss),
      const Offset(0, 300),
      1200,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('飞出动画中再次按下：接管并取消退出', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    // 下拉越过阈值后松手 → 进入飞出阶段（动画进行中，尚未触发退出）。
    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 160));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 40));
    expect(dismissed, isFalse); // 飞出动画未完成，仍未退出

    // 手指再次按下：停住飞出动画并从当前位置接管，反悔拖回。
    final g2 = await tester.startGesture(const Offset(200, 420));
    await g2.moveBy(const Offset(0, -200));
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();

    // 已排定的退出被取消。
    expect(dismissed, isFalse);
    expect(contentTop(tester), closeTo(0, 1));
  });

  testWidgets('飞出动画线性匀速：位移随帧均匀推进（无起始停顿）', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 200)); // 越过阈值
    await tester.pump();
    await g.up();
    await tester.pump();

    // 按固定时间片采样飞出位移；线性曲线相邻位移差应接近相等，
    // easeIn 起始近似停顿（首个差值明显偏小）。
    final positions = <double>[];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      positions.add(contentTop(tester));
    }
    final d1 = positions[1] - positions[0];
    final d2 = positions[2] - positions[1];
    final d3 = positions[3] - positions[2];
    expect(d1, closeTo(d2, d1 * 0.5));
    expect(d2, closeTo(d3, d2 * 0.5));

    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('起始点在允许区域外（底部 40%）：不响应下拉退出', (tester) async {
    var dismissed = false;
    // 只允许屏幕上方 50% 发起下拉。
    await pumpPtd(tester, onDismiss: () => dismissed = true, startAreaFraction: 0.5);

    // 起点在 70% 高度（区域外），快速下滑不应触发退出。
    await tester.flingFrom(
      const Offset(200, 420),
      const Offset(0, 300),
      1200,
    );
    await tester.pumpAndSettle();
    expect(dismissed, isFalse);
    expect(contentTop(tester), closeTo(0, 1));

    // 起点在 30% 高度（区域内），快速下滑触发退出。
    await tester.flingFrom(
      const Offset(200, 180),
      const Offset(0, 300),
      1200,
    );
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
