import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 迷你播放条回弹触发信号。
///
/// 播放页收起（下拉 / 点顶部收起条）时 [bump] 一次，迷你播放条据此播放一次
/// spring 回弹动画（0.7→1.0 带过冲），形成「播放页收进迷你条、迷你条弹一下」
/// 的 Apple Music 手感。
class MiniPlayerBounceController extends Notifier<int> {
  @override
  int build() => 0;

  /// 触发一次回弹：自增计数，消费者监听变化播放动画。
  void bump() => state = state + 1;
}

/// 全局迷你条回弹信号 Provider。
final miniPlayerBounceProvider =
    NotifierProvider<MiniPlayerBounceController, int>(
      MiniPlayerBounceController.new,
    );

/// 迷你播放条「按压」触发信号。
///
/// 点击迷你条进入播放页时 [press] 一次，迷你条播放一次轻微的按压反馈
/// （1→0.9→1，短促），区别于收起时的 [MiniPlayerBounceController] 大回弹。
class MiniPlayerPressController extends Notifier<int> {
  @override
  int build() => 0;

  /// 触发一次按压反馈：自增计数，消费者监听变化播放动画。
  void press() => state = state + 1;
}

/// 全局迷你条按压信号 Provider。
final miniPlayerPressProvider =
    NotifierProvider<MiniPlayerPressController, int>(
      MiniPlayerPressController.new,
    );
