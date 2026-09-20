import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/ui/pages/player/pull_to_dismiss.dart';

/// PullToDismiss 直接组件测试（不包 _NoAnimations，动画默认开启），
/// 覆盖「跟手」「回弹」「收起退出」「收起中接管取消」四类行为。
void main() {
  Future<void> pumpPtd(
    WidgetTester tester, {
    required VoidCallback onDismiss,
    VoidCallback? onDismissStart,
    double startAreaFraction = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToDismiss(
            onDismiss: onDismiss,
            onDismissStart: onDismissStart,
            startAreaFraction: startAreaFraction,
            child: const SizedBox.expand(
              child: ColoredBox(key: ValueKey('ptd-child'), color: Colors.red),
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

  testWidgets('下拉快速甩动：收起后触发退出', (tester) async {
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

  testWidgets('页面到达迷你条时触发 onDismissStart，完成后才触发 onDismiss', (tester) async {
    var dismissed = false;
    var startCount = 0;
    await pumpPtd(
      tester,
      onDismiss: () => dismissed = true,
      onDismissStart: () => startCount++,
    );

    // 下拉越过阈值后松手 → 进入收起阶段。
    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 160));
    await tester.pump();
    await g.up();
    await tester.pump(); // 启动收起动画（ticker 从下一帧开始计时）
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 已越过「页面顶部到达迷你条」触发点（收起 300ms×(1/3)=100ms）：回弹已触发，尚未 dismiss。
    expect(startCount, 1);
    expect(dismissed, isFalse);

    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('收起动画中再次按下：接管并取消退出', (tester) async {
    var dismissed = false;
    await pumpPtd(tester, onDismiss: () => dismissed = true);

    // 下拉越过阈值后松手 → 进入收起阶段（动画进行中，尚未触发退出）。
    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 160));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 40));
    expect(dismissed, isFalse); // 收起动画未完成，仍未退出

    // 手指再次按下：停住收起动画并从当前位置接管，反悔拖回。
    final g2 = await tester.startGesture(const Offset(200, 420));
    await g2.moveBy(const Offset(0, -200));
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();

    // 已排定的退出被取消。
    expect(dismissed, isFalse);
    expect(contentTop(tester), closeTo(0, 1));
  });

  testWidgets('collapse()：点收起条路径同样收起并触发退出', (tester) async {
    var dismissed = false;
    var startCount = 0;
    final key = GlobalKey<PullToDismissState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToDismiss(
            key: key,
            onDismiss: () => dismissed = true,
            onDismissStart: () => startCount++,
            child: const SizedBox.expand(
              child: ColoredBox(key: ValueKey('ptd-child'), color: Colors.red),
            ),
          ),
        ),
      ),
    );

    key.currentState?.collapse();
    await tester.pump(); // 启动收起动画
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(startCount, 1);
    expect(dismissed, isFalse);

    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('起始点在允许区域外（底部 40%）：不响应下拉退出', (tester) async {
    var dismissed = false;
    // 只允许屏幕上方 50% 发起下拉。
    await pumpPtd(
      tester,
      onDismiss: () => dismissed = true,
      startAreaFraction: 0.5,
    );

    // 起点在 70% 高度（区域外），快速下滑不应触发退出。
    await tester.flingFrom(const Offset(200, 420), const Offset(0, 300), 1200);
    await tester.pumpAndSettle();
    expect(dismissed, isFalse);
    expect(contentTop(tester), closeTo(0, 1));

    // 起点在 30% 高度（区域内），快速下滑触发退出。
    await tester.flingFrom(const Offset(200, 180), const Offset(0, 300), 1200);
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
