import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

import 'audio_engine.dart';
import 'equalizer.dart';
import 'track.dart';

/// [AudioEngine] 的 just_audio 原生实现。
///
/// - 使用各平台原生解码器（iOS/Android ExoPlayer & AVPlayer、macOS/Windows/Linux 原生通道）；
/// - 解码能力取决于平台，不支持时经 [errorStream] 上报，由上层优雅回退。
/// - 播放器实例懒创建：仅首次 [playSource] 才触达平台通道，纯 Dart / widget 测试
///   环境不创建真实播放器。
/// - 均衡器：仅 Android 支持（just_audio 的 [AndroidEqualizer]），构造时即创建
///   实例并包装为 [AudioEqualizer] 抽象（三态之「未就绪」依赖实例先于播放存在）；
///   创建播放器时经 [AudioPipeline] 注入。其余平台 [equalizer] 为 null。
class JustAudioEngine implements AudioEngine {
  JustAudioEngine();

  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  /// Android 均衡器（构造即存在；与 just_audio 内部 `_isAndroid()` 门控一致）。
  final AndroidEqualizer? _androidEqualizer =
      (!kIsWeb && Platform.isAndroid) ? AndroidEqualizer() : null;
  AudioEqualizer? _equalizer;

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

  @override
  AudioEqualizer? get equalizer {
    final inner = _androidEqualizer;
    if (inner == null) return null;
    return _equalizer ??= _JustAudioEqualizer(inner);
  }

  @override
  Future<void> init() async {
    // 显式配置音频会话为「音乐播放」（iOS/macOS：AVAudioSession category =
    // playback），这是锁屏/息屏后继续出声的硬前提；配合 iOS
    // UIBackgroundModes=audio 与 macOS 关闭 App Nap 生效。
    // 配置失败不阻塞播放（降级为普通前台播放）。
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      // 平台不支持（如纯 Dart 测试环境）时静默降级。
    }
  }

  AudioPlayer _ensurePlayer() {
    if (_player case final player?) return player;
    final equalizer = _androidEqualizer;
    final player = AudioPlayer(
      // Android 均衡器必须在创建播放器时注入管线，之后无法追加。
      audioPipeline: equalizer == null
          ? null
          : AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _player = player;

    _playerStateSub = player.playerStateStream.listen((state) {
      _playing.add(state.playing);
      if (state.processingState == ProcessingState.completed) {
        _completed.add(null);
      }
    });
    _playingSub = player.playingStream.listen(_playing.add);
    _positionSub = player.positionStream.listen(_position.add);
    _durationSub = player.durationStream.listen((d) {
      _duration.add(d ?? Duration.zero);
    });
    return player;
  }

  @override
  Future<void> playSource(Track track) async {
    final player = _ensurePlayer();
    try {
      await player.setAudioSource(AudioSource.file(track.filePath!));
      await player.play();
      _playing.add(true);
    } catch (e) {
      _error.add(e);
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    _playing.add(false);
  }

  @override
  Future<void> resume() async {
    await _player?.play();
    _playing.add(true);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final player = _player;
    if (player != null) {
      await player.setVolume(volume.clamp(0.0, 1.0));
    }
  }

  @override
  Future<void> dispose() async {
    // dispose 为终态：再次播放会重建 AudioPlayer 并把同一 AndroidEqualizer
    // 注入新播放器，触发 AudioEffect 重复挂载断言。请勿复用已释放的引擎
    // （引擎随 audioEngineProvider 终生单例，替换时应整体新建）。
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _playerStateSub?.cancel();
    await _player?.dispose();
    _player = null;
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
    await _error.close();
  }
}

/// just_audio [AndroidEqualizer] 的抽象包装：业务层不感知具体引擎类型。
class _JustAudioEqualizer implements AudioEqualizer {
  _JustAudioEqualizer(this._inner);

  final AndroidEqualizer _inner;

  @override
  bool get enabled => _inner.enabled;

  @override
  Future<void> setEnabled(bool enabled) => _inner.setEnabled(enabled);

  @override
  Future<EqualizerParameters> get parameters async {
    final p = await _inner.parameters;
    return _JustAudioEqualizerParameters(p);
  }
}

class _JustAudioEqualizerParameters implements EqualizerParameters {
  _JustAudioEqualizerParameters(AndroidEqualizerParameters inner)
      : minDecibels = inner.minDecibels,
        maxDecibels = inner.maxDecibels,
        bands = [for (final b in inner.bands) _JustAudioEqualizerBand(b)];

  @override
  final double minDecibels;

  @override
  final double maxDecibels;

  @override
  final List<EqualizerBand> bands;
}

class _JustAudioEqualizerBand implements EqualizerBand {
  _JustAudioEqualizerBand(this._inner);

  final AndroidEqualizerBand _inner;

  @override
  double get centerFrequency => _inner.centerFrequency;

  @override
  double get gain => _inner.gain;

  @override
  Future<void> setGain(double gain) => _inner.setGain(gain);
}
