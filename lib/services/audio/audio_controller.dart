import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'track.dart';

/// 播放引擎占位状态。
/// 具体播放方案待定，这里先定义状态外壳，供迷你条、播放页与列表接入。
@immutable
class PlaybackState {
  const PlaybackState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
  });

  /// 播放队列（内存态）。
  final List<Track> queue;

  /// 当前播放曲目在队列中的下标；-1 表示未选中。
  final int currentIndex;

  final bool isPlaying;

  /// 当前播放/选中的曲目；为 null 表示媒体库为空或未播放。
  Track? get currentTrack =>
      (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;

  bool get hasTrack => currentTrack != null;

  PlaybackState copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
  }) {
    return PlaybackState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

/// 全局播放状态（占位实现，后续由真实 AudioService 替换）。
class AudioController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  /// 点按歌曲：替换队列为该曲目并立即播放。
  void play(Track track) {
    state = PlaybackState(queue: [track], currentIndex: 0, isPlaying: true);
  }

  /// 加入播放队列：追加到队尾，不打断当前播放。
  void enqueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
  }

  /// 切换播放/暂停（占位，仅驱动 UI 状态）。
  void togglePlay() {
    if (!state.hasTrack) return;
    state = state.copyWith(isPlaying: !state.isPlaying);
  }
}

/// 全局播放状态 Provider。
final audioControllerProvider =
    NotifierProvider<AudioController, PlaybackState>(AudioController.new);