import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preferences_controller.dart';
import 'audio_engine.dart';
import 'audio_engine_provider.dart';
import 'equalizer.dart';

/// 均衡器预设：5 点 dB 曲线（低频→高频），按 log(中心频率) 插值到设备实际段数。
enum EqualizerPreset {
  flat([0, 0, 0, 0, 0]),
  pop([-1, 2, 4, 2, 0]),
  rock([3, 2, -1, 2, 4]),
  jazz([2, 1, 0, 1, 3]),
  classical([3, 1, -1, 2, 3]),
  electronic([4, 2, 0, 2, 3]);

  const EqualizerPreset(this.curve);

  /// 低频→高频 5 个锚点的增益（dB）。
  final List<double> curve;
}

/// 预设曲线锚点频率（典型 5 段中心频率，Hz）。
const List<double> kEqualizerPresetAnchors = [60, 230, 910, 3600, 14000];

/// 预设 5 点曲线 → 实际频段：按 log(中心频率) 线性插值（频段分布非线性，
/// 按下标插值会失真）。段数恰为 5 时直接返回原曲线。
@visibleForTesting
List<double> presetGains(
  EqualizerPreset preset,
  List<double> centerFrequencies,
) {
  final curve = preset.curve;
  if (centerFrequencies.isEmpty) return const [];
  if (centerFrequencies.length == curve.length) return List.of(curve);
  final logLo = math.log(kEqualizerPresetAnchors.first);
  final logHi = math.log(kEqualizerPresetAnchors.last);
  return [
    for (final f in centerFrequencies)
      _sampleCurve(curve, _logPosition(f, logLo, logHi)),
  ];
}

/// 频段在锚点区间 [logLo, logHi] 上的归一化位置（0–1，越界 clamp）。
double _logPosition(double frequency, double logLo, double logHi) {
  final safe = math.max(1.0, frequency);
  final t = (math.log(safe) - logLo) / (logHi - logLo);
  return math.min(1.0, math.max(0.0, t));
}

/// 按归一化位置 [t]（0–1）在曲线上线性插值。
double _sampleCurve(List<double> curve, double t) {
  final scaled = t * (curve.length - 1);
  final i = math.min(curve.length - 2, math.max(0, scaled.floor()));
  return curve[i] + (curve[i + 1] - curve[i]) * (scaled - i);
}

/// 均衡器 UI 状态：三态（不支持 / 未就绪 / 就绪）+ 当前参数。
@immutable
class EqualizerState {
  const EqualizerState({
    required this.supported,
    this.ready = false,
    this.enabled = false,
    this.minDecibels = 0,
    this.maxDecibels = 0,
    this.centerFrequencies = const [],
    this.gains = const [],
  });

  /// 引擎是否提供均衡器（平台不支持为 false，UI 降级展示）。
  final bool supported;

  /// 频段参数是否已就绪（引擎激活=首次播放后可用）。
  final bool ready;

  /// 开关状态（镜像偏好）。
  final bool enabled;

  /// 设备增益范围（dB）。
  final double minDecibels;
  final double maxDecibels;

  /// 各频段中心频率（Hz，低频→高频）。
  final List<double> centerFrequencies;

  /// 各频段当前增益（dB），与 [centerFrequencies] 等长（就绪后对齐）。
  final List<double> gains;

  EqualizerState copyWith({
    bool? supported,
    bool? ready,
    bool? enabled,
    double? minDecibels,
    double? maxDecibels,
    List<double>? centerFrequencies,
    List<double>? gains,
  }) {
    return EqualizerState(
      supported: supported ?? this.supported,
      ready: ready ?? this.ready,
      enabled: enabled ?? this.enabled,
      minDecibels: minDecibels ?? this.minDecibels,
      maxDecibels: maxDecibels ?? this.maxDecibels,
      centerFrequencies: centerFrequencies ?? this.centerFrequencies,
      gains: gains ?? this.gains,
    );
  }
}

/// 全局均衡器控制器：偏好为唯一事实源，引擎单向镜像。
///
/// 与 [AudioController] 处理默认音量的模式一致：
/// - 公共方法只写偏好（持久化），由 build 里注册的偏好监听统一镜像到引擎，
///   避免「方法直写 + 监听回写」双路径漂移；
/// - 监听/异步回调内不碰 `ref`（Riverpod 3 会断言拦截），所需值在 build 捕获；
/// - `enabled` 立即应用（引擎激活时会带上该状态）；增益等参数就绪后统一应用，
///   按设备段数 pad 0 / 截断并 clamp 到设备范围。
class EqualizerController extends Notifier<EqualizerState> {
  /// 就绪后的设备频段参数；null = 未就绪。
  EqualizerParameters? _params;

  /// 待应用的持久化增益（偏好监听器持续更新；就绪后一次性应用）。
  List<double> _pendingGains = const [];

  /// 本 build 绑定的引擎实例：引擎替换后旧参数回调不得写脏 state。
  AudioEngine? _boundEngine;

  @override
  EqualizerState build() {
    final engine = ref.watch(audioEngineProvider);
    _boundEngine = engine;
    final equalizer = engine.equalizer;
    if (equalizer == null) {
      _params = null;
      return const EqualizerState(supported: false);
    }

    final prefs =
        ref.read(preferencesProvider).value ?? const AppPreferences();
    _pendingGains = prefs.equalizerGains;

    // 偏好变化 → 镜像引擎 + 回写本状态（UI 单源）。
    ref.listen(preferencesProvider, (previous, next) {
      if (!next.hasValue) return;
      final p = next.value!;
      _pendingGains = p.equalizerGains;
      unawaited(equalizer.setEnabled(p.equalizerEnabled).catchError((_) {}));
      _applyGains();
      state = _stateFromPrefs(p);
    });

    // 兜底：启动/重建时立即应用开关（激活前设置会在引擎激活时生效）。
    unawaited(equalizer.setEnabled(prefs.equalizerEnabled).catchError((_) {}));
    // 频段参数：引擎激活后完成；完成前 UI 保持「未就绪」（不加超时）。
    unawaited(_loadParameters(engine, equalizer));

    return EqualizerState(
      supported: true,
      enabled: prefs.equalizerEnabled,
      gains: prefs.equalizerGains,
    );
  }

  /// 把偏好镜像到本状态；就绪后按设备段数对齐 + clamp。
  EqualizerState _stateFromPrefs(AppPreferences p) {
    final bands = state.centerFrequencies.length;
    return state.copyWith(
      enabled: p.equalizerEnabled,
      gains: bands == 0
          ? p.equalizerGains
          : [
              for (var i = 0; i < bands; i++)
                _clampGain(_gainAt(p.equalizerGains, i)),
            ],
    );
  }

  Future<void> _loadParameters(
    AudioEngine engine,
    AudioEqualizer equalizer,
  ) async {
    final EqualizerParameters params;
    try {
      params = await equalizer.parameters;
    } catch (_) {
      // 平台异常：保持未就绪（UI 停留降级态），不误报为不支持。
      return;
    }
    // provider 已销毁 / 引擎已替换：旧回调不得写 state。
    if (!ref.mounted || _boundEngine != engine) return;
    _params = params;
    state = state.copyWith(
      ready: true,
      minDecibels: params.minDecibels,
      maxDecibels: params.maxDecibels,
      centerFrequencies: [for (final b in params.bands) b.centerFrequency],
      gains: [
        for (var i = 0; i < params.bands.length; i++)
          _clampGain(_gainAt(_pendingGains, i)),
      ],
    );
    _applyGains();
  }

  /// 把待应用增益写入各频段；未就绪时为 no-op（就绪后统一补应用）。
  void _applyGains() {
    final params = _params;
    if (params == null) return;
    for (var i = 0; i < params.bands.length; i++) {
      final band = params.bands[i];
      unawaited(
        band.setGain(_clampGain(_gainAt(_pendingGains, i))).catchError((_) {}),
      );
    }
  }

  static double _gainAt(List<double> gains, int index) =>
      index < gains.length ? gains[index] : 0.0;

  double _clampGain(double gain) {
    final params = _params;
    if (params == null) return gain;
    return gain.clamp(params.minDecibels, params.maxDecibels).toDouble();
  }

  // ---- 公共操作：只写偏好（持久化），引擎由偏好监听统一镜像 ----

  /// 开关均衡器。
  Future<void> setEnabled(bool enabled) =>
      ref.read(preferencesProvider.notifier).setEqualizerEnabled(enabled);

  /// 调整单个频段增益（dB）。
  Future<void> setBandGain(int index, double gainDb) {
    final bands = state.centerFrequencies.length;
    if (bands == 0 || index < 0 || index >= bands) return Future.value();
    final next = [
      for (var i = 0; i < bands; i++)
        i == index ? gainDb : _gainAt(state.gains, i),
    ];
    return ref.read(preferencesProvider.notifier).setEqualizerGains(next);
  }

  /// 应用预设：5 点曲线按 log(中心频率) 插值到实际段数。
  Future<void> applyPreset(EqualizerPreset preset) {
    if (!state.ready) return Future.value();
    return ref
        .read(preferencesProvider.notifier)
        .setEqualizerGains(presetGains(preset, state.centerFrequencies));
  }

  /// 重置为平直（全 0）。
  Future<void> reset() {
    if (!state.ready) return Future.value();
    return ref
        .read(preferencesProvider.notifier)
        .setEqualizerGains(List.filled(state.centerFrequencies.length, 0.0));
  }
}

/// 全局均衡器状态 Provider。
final equalizerControllerProvider =
    NotifierProvider<EqualizerController, EqualizerState>(
      EqualizerController.new,
    );
