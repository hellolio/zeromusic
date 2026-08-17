import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_controller.dart';

/// 睡眠定时：倒计时结束自动暂停播放。
///
/// 状态为 [Duration?]：null 表示未启用；非 null 表示剩余时长。
/// 每秒递减一次并实时更新状态（驱动播放页倒计时 UI），归零时暂停并自动清除。
class SleepTimer extends Notifier<Duration?> {
  Timer? _ticker;

  @override
  Duration? build() {
    ref.onDispose(() => _ticker?.cancel());
    return null;
  }

  /// 以 [duration] 开始倒计时；已启用则重置为新时长。
  void start(Duration duration) {
    _ticker?.cancel();
    if (duration <= Duration.zero) {
      state = null;
      return;
    }
    state = duration;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 立即关闭睡眠定时。
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    state = null;
  }

  void _tick() {
    final left = state;
    if (left == null) return;
    final next = left - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      stop();
      ref.read(audioControllerProvider.notifier).pause();
    } else {
      state = next;
    }
  }
}

/// 全局睡眠定时状态 Provider。
final sleepTimerProvider =
    NotifierProvider<SleepTimer, Duration?>(SleepTimer.new);