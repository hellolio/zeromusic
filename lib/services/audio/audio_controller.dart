import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preferences_controller.dart';
import 'audio_engine.dart';
import 'audio_engine_provider.dart';
import 'track.dart';

/// 播放模式。
///
/// 顺序：播到队尾后停止；
/// 循环（默认）：到队尾环绕继续；
/// 单曲循环：播放完成重播本曲（手动上一首/下一首仍前进）；
/// 随机：每次切换随机选曲。
enum PlaybackMode { sequential, loopAll, loopOne, shuffle }

/// 全局播放状态。
///
/// [queue]/[currentIndex]/[isPlaying] 由控制器编排维护；
/// [position]/[duration] 由播放引擎实时流镜像，驱动迷你条进度条等 UI。
@immutable
class PlaybackState {
  const PlaybackState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playbackMode = PlaybackMode.loopAll,
  });

  /// 播放队列（内存态）。
  final List<Track> queue;

  /// 当前播放曲目在队列中的下标；-1 表示未选中。
  final int currentIndex;

  final bool isPlaying;

  /// 当前播放进度（引擎实时镜像）。
  final Duration position;

  /// 当前资源总时长（引擎加载后更新；未知时为零）。
  final Duration duration;

  /// 播放模式（顺序/循环/单曲循环/随机）。
  final PlaybackMode playbackMode;

  /// 当前播放/选中的曲目；为 null 表示媒体库为空或未播放。
  Track? get currentTrack =>
      (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;

  bool get hasTrack => currentTrack != null;

  /// 队列中是否存在可切换的下一首（环绕队列始终为 true；空/未选中为 false）。
  bool get hasNext => queue.isNotEmpty && currentIndex >= 0;

  PlaybackState copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    PlaybackMode? playbackMode,
  }) {
    return PlaybackState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playbackMode: playbackMode ?? this.playbackMode,
    );
  }
}

/// 全局播放控制器：编排播放队列，并通过 [AudioEngine] 抽象真正驱动声音。
///
/// 业务层绝不直接触达具体引擎实现，仅依赖 [audioEngineProvider] 注入的 [AudioEngine]。
class AudioController extends Notifier<PlaybackState> {
  AudioController({Random? random}) : _random = random ?? Random();

  final Random _random;

  AudioEngine get _engine => ref.read(audioEngineProvider);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<Object?>? _errorSub;

  @override
  PlaybackState build() {
    _listenEngine();
    // 播放流只依赖引擎，缓存实例供监听回调使用（回调内禁止 Ref.read）。
    final engine = ref.read(audioEngineProvider);
    // 偏好（默认音量）变化时同步到引擎；加载完成/后续修改都会触发。
    ref.listen(preferencesProvider, (previous, next) {
      if (next.hasValue) {
        _applyVolume(engine, next.value!.defaultVolume);
      }
    });
    // 兜底：启动/重建时应用当前默认音量（覆盖已完成加载等监听未触发的场景）。
    _applyVolume(engine, _currentVolume());
    return const PlaybackState();
  }

  double _currentVolume() =>
      ref.read(preferencesProvider).value?.defaultVolume ?? 1.0;

  /// 把音量应用到引擎；失败静默降级（不阻塞播放）。
  void _applyVolume(AudioEngine engine, double volume) {
    unawaited(engine.setVolume(volume.clamp(0.0, 1.0)).catchError((_) {}));
  }

  /// 订阅引擎状态流：进度/时长/播放态实时镜像进 [PlaybackState]；
  /// 播放完成自动切歌；解码失败优雅回退为暂停。
  void _listenEngine() {
    final engine = _engine;
    _positionSub = engine.positionStream.listen((d) {
      state = state.copyWith(position: d);
    });
    _durationSub = engine.durationStream.listen((d) {
      state = state.copyWith(duration: d);
    });
    _playingSub = engine.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _completedSub = engine.completedStream.listen((_) => _onComplete());
    _errorSub = engine.errorStream.listen((_) {
      state = state.copyWith(isPlaying: false);
    });

    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _completedSub?.cancel();
      _errorSub?.cancel();
    });
  }

  /// 点按歌曲：替换队列为该曲目并立即播放。
  void play(Track track) => playQueue([track]);

  /// 以指定顺序建立播放队列，并从 [startIndex] 处开始播放。
  /// 供播放列表「点一首即按当前筛选视图整列入队」使用。
  void playQueue(List<Track> tracks, {int startIndex = 0}) {
    if (tracks.isEmpty) return;
    final queue = List<Track>.of(tracks);
    final index = _clampIndex(startIndex, queue.length);
    state = PlaybackState(
      queue: queue,
      currentIndex: index,
      isPlaying: true,
      playbackMode: state.playbackMode,
    );
    unawaited(_loadToEngine(queue[index]));
  }

  static int _clampIndex(int index, int length) {
    if (index < 0) return 0;
    if (index >= length) return length - 1;
    return index;
  }

  /// 加入播放队列：追加到队尾，不打断当前播放。
  void enqueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
  }

  /// 切换播放/暂停。状态同步翻转（驱动 UI），声音经引擎异步执行。
  void togglePlay() {
    if (!state.hasTrack) return;
    final engine = _engine;
    if (state.isPlaying) {
      state = state.copyWith(isPlaying: false);
      unawaited(engine.pause());
    } else {
      state = state.copyWith(isPlaying: true);
      unawaited(_resumeOrReload(engine));
    }
  }

  /// 暂停当前播放（如睡眠定时归零）。已暂停时为 no-op。
  void pause() {
    if (!state.isPlaying) return;
    state = state.copyWith(isPlaying: false);
    unawaited(_engine.pause());
  }

  /// 恢复播放；若引擎无可恢复源（首次/播放被清空），回退为重新加载当前曲目。
  Future<void> _resumeOrReload(AudioEngine engine) async {
    final track = state.currentTrack;
    if (track == null) return;
    try {
      await engine.resume();
    } catch (_) {
      await _loadToEngine(track);
    }
  }

  /// 循环切换播放模式：顺序 → 循环 → 单曲循环 → 随机。
  void cyclePlaybackMode() {
    final modes = PlaybackMode.values;
    state = state.copyWith(
      playbackMode: modes[(state.playbackMode.index + 1) % modes.length],
    );
  }

  /// 播放完成：按当前模式决定自动行为（单曲循环重播本曲、顺序到队尾停止等）。
  void _onComplete() {
    if (!state.hasNext) return;
    final mode = state.playbackMode;
    if (mode == PlaybackMode.loopOne) {
      _playAtIndex(state.currentIndex, state.queue);
      return;
    }
    if (mode == PlaybackMode.sequential && state.currentIndex == state.queue.length - 1) {
      state = state.copyWith(isPlaying: false);
      return;
    }
    next();
  }

  /// 下一首：环绕 / 顺序 / 随机 / 单曲（手动切歌前进）。
  void next() {
    if (!state.hasNext) return;
    final queue = state.queue;
    final current = state.currentIndex;
    switch (state.playbackMode) {
      case PlaybackMode.shuffle:
        _playAtIndex(_shuffleIndex(current, queue.length), queue);
      case PlaybackMode.sequential:
        _playAtIndex(min(current + 1, queue.length - 1), queue);
      case PlaybackMode.loopAll:
      case PlaybackMode.loopOne:
        _playAtIndex((current + 1) % queue.length, queue);
    }
  }

  /// 上一首：环绕 / 顺序 / 随机 / 单曲（手动切歌后退）。
  void previous() {
    if (!state.hasNext) return;
    final queue = state.queue;
    final current = state.currentIndex;
    switch (state.playbackMode) {
      case PlaybackMode.shuffle:
        _playAtIndex(_shuffleIndex(current, queue.length), queue);
      case PlaybackMode.sequential:
        _playAtIndex(max(current - 1, 0), queue);
      case PlaybackMode.loopAll:
      case PlaybackMode.loopOne:
        _playAtIndex((current - 1 + queue.length) % queue.length, queue);
    }
  }

  /// 随机选一个与 [current] 不同的下标（单曲队列时回退为自身）。
  int _shuffleIndex(int current, int length) {
    if (length < 2) return current;
    final candidates = List<int>.generate(length, (i) => i)..remove(current);
    return candidates[_random.nextInt(candidates.length)];
  }

  /// 跳转到指定进度。
  void seek(Duration position) {
    if (!state.hasTrack) return;
    state = state.copyWith(position: position);
    unawaited(_engine.seek(position));
  }

  void _playAtIndex(int index, List<Track> queue) {
    final track = queue[index];
    state = PlaybackState(
      queue: queue,
      currentIndex: index,
      isPlaying: true,
      playbackMode: state.playbackMode,
    );
    unawaited(_loadToEngine(track));
  }

  /// 驱动引擎播放当前曲目；失败时经 errorStream 上报并回退为暂停（不崩溃）。
  Future<void> _loadToEngine(Track track) async {
    _applyVolume(_engine, _currentVolume());
    try {
      await _engine.playSource(track);
    } catch (_) {
      state = state.copyWith(isPlaying: false);
    }
  }
}

/// 全局播放状态 Provider。
final audioControllerProvider =
    NotifierProvider<AudioController, PlaybackState>(AudioController.new);