import 'equalizer.dart';
import 'track.dart';

/// 播放引擎抽象契约 —— 业务层的唯一播放依赖。
///
/// 所有 UI / 状态编排代码（AudioController、迷你条、播放页、列表）只 import 本文件，
/// 绝不直接依赖具体实现（just_audio / media_kit 等）。
///
/// 换引擎 = 新增一个 `implements AudioEngine` 的实现，并在
/// `audio_engine_provider.dart` 中替换注入点即可，业务代码零改动。
abstract interface class AudioEngine {
  /// 引擎级初始化（如 media_kit 需要 `ensureInitialized`，just_audio 为 no-op）。
  /// 在应用启动 `main()` 中统一调用一次。
  Future<void> init();

  /// 播放进度流（随播放推进；暂停时可能静止）。
  Stream<Duration> get positionStream;

  /// 当前资源总时长流（加载后更新；未知时为零）。
  Stream<Duration> get durationStream;

  /// 播放/暂停状态流。
  Stream<bool> get playingStream;

  /// 一首歌曲自然播完时触发（用于自动切歌）。
  Stream<void> get completedStream;

  /// 加载/解码失败（如格式不被平台支持）时上报，携带异常对象。
  Stream<Object?> get errorStream;

  /// 加载 [track] 并立即播放。[track] 携带 filePath/url，由引擎内部解析。
  /// 失败时抛错或经 [errorStream] 上报，不得静默吞掉播放状态。
  Future<void> playSource(Track track);

  /// 暂停当前播放。
  Future<void> pause();

  /// 恢复当前播放。
  Future<void> resume();

  /// 跳转到指定进度。
  Future<void> seek(Duration position);

  /// 引擎级均衡器；平台/实现不支持时为 null（UI 降级为「不支持」展示）。
  /// 实例在引擎构造后即存在（未激活时 [AudioEqualizer.parameters] 暂不完成）。
  AudioEqualizer? get equalizer;

  /// 设置播放音量（0.0–1.0）。引擎尚未加载资源时为 no-op，不影响后续播放。
  Future<void> setVolume(double volume);

  /// 释放引擎资源（应用退出 / 引擎替换时触发）。
  Future<void> dispose();
}