import 'dart:async';

import 'package:zeromusic/services/audio/audio_engine.dart';
import 'package:zeromusic/services/audio/track.dart';

/// 测试用内存播放引擎：记录所有调用、暴露可控流。
/// 完全不触达真实平台播放器，供纯 Dart 与 widget 测试注入。
class FakeAudioEngine implements AudioEngine {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playing =
      StreamController<bool>.broadcast();
  final StreamController<void> _completed =
      StreamController<void>.broadcast();
  final StreamController<Object?> _error =
      StreamController<Object?>.broadcast();

  /// 被 [playSource] 加载过的曲目（按调用顺序）。
  final List<Track> playedTracks = [];

  int initCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int seekCount = 0;
  int volumeCount = 0;
  Duration? lastSeek;
  double? lastVolume;
  bool disposed = false;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Stream<Object?> get errorStream => _error.stream;

  /// 最近一次 [playSource] 的曲目。
  Track? get lastPlayed => playedTracks.isEmpty ? null : playedTracks.last;

  @override
  Future<void> init() async {
    initCount++;
  }

  @override
  Future<void> playSource(Track track) async {
    playedTracks.add(track);
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _playing.add(false);
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    _playing.add(true);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    lastSeek = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeCount++;
    lastVolume = volume;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
    await _error.close();
  }

  // ---- 测试驱动：向流中注入事件 ----

  void emitPosition(Duration position) => _position.add(position);

  void emitDuration(Duration duration) => _duration.add(duration);

  void emitPlaying(bool playing) => _playing.add(playing);

  void emitCompleted() => _completed.add(null);

  void emitError(Object error) => _error.add(error);
}