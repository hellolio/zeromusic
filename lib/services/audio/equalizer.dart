/// 均衡器抽象契约 —— 业务层（设置页 / 控制器）的唯一均衡器依赖。
///
/// 与 [AudioEngine] 同层：具体实现（just_audio 的 AndroidEqualizer 等）
/// 由引擎内部包装成本抽象，业务代码不感知引擎类型。
///
/// 平台支持度：just_audio 目前仅 Android 提供均衡器；不支持的平台
/// 引擎返回 `equalizer == null`，UI 降级为「不支持」展示。
library;

/// 单个频段。
abstract interface class EqualizerBand {
  /// 中心频率（Hz）。
  double get centerFrequency;

  /// 当前增益（dB）。
  double get gain;

  /// 设置增益（dB）。调用方负责 clamp 到设备范围。
  Future<void> setGain(double gain);
}

/// 频段参数（引擎激活后可读；段数与范围设备相关，典型 5 段 ±15dB）。
abstract interface class EqualizerParameters {
  /// 设备支持的最小增益（dB，负值）。
  double get minDecibels;

  /// 设备支持的最大增益（dB，正值）。
  double get maxDecibels;

  /// 频段列表（低频→高频）。
  List<EqualizerBand> get bands;
}

/// 引擎级均衡器。
abstract interface class AudioEqualizer {
  /// 频段参数。引擎尚未激活（首次播放前）时本 Future 暂不完成，
  /// 调用方应保持「未就绪」UI，不得加超时误判为不支持。
  Future<EqualizerParameters> get parameters;

  /// 是否启用（bypass 时为 false）。激活前设置的状态会在激活时生效。
  bool get enabled;

  /// 启用/停用。
  Future<void> setEnabled(bool enabled);
}
