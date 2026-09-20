import 'dart:async';

import 'package:zeromusic/services/audio/equalizer.dart';

/// 测试用内存频段：记录 setGain 调用。
class FakeEqualizerBand implements EqualizerBand {
  FakeEqualizerBand({required this.centerFrequency, this.gain = 0});

  @override
  final double centerFrequency;

  @override
  double gain;

  /// [setGain] 调用次数。
  int setGainCount = 0;

  @override
  Future<void> setGain(double gain) async {
    setGainCount++;
    this.gain = gain;
  }
}

/// 测试用内存频段参数。
class FakeEqualizerParameters implements EqualizerParameters {
  FakeEqualizerParameters({
    this.minDecibels = -15,
    this.maxDecibels = 15,
    required this.bands,
  });

  @override
  final double minDecibels;

  @override
  final double maxDecibels;

  @override
  final List<FakeEqualizerBand> bands;
}

/// 测试用内存均衡器：默认 5 段（60/230/910/3600/14000Hz）±15dB。
/// [autoReady]=false 时 [parameters] 保持未完成，由测试调 [completeParameters]
/// 模拟「引擎激活（首次播放）后参数就绪」。
class FakeEqualizer implements AudioEqualizer {
  FakeEqualizer({
    int bandCount = 5,
    double minDecibels = -15,
    double maxDecibels = 15,
    this.autoReady = true,
  }) : _params = FakeEqualizerParameters(
          minDecibels: minDecibels,
          maxDecibels: maxDecibels,
          bands: [
            for (var i = 0; i < bandCount; i++)
              FakeEqualizerBand(
                centerFrequency: _defaultFreqs[i % _defaultFreqs.length],
              ),
          ],
        );

  static const _defaultFreqs = [60.0, 230.0, 910.0, 3600.0, 14000.0];

  /// true = 访问 [parameters] 即就绪；false = 由测试手动 [completeParameters]。
  final bool autoReady;
  final FakeEqualizerParameters _params;
  final Completer<EqualizerParameters> _completer = Completer();
  bool _completed = false;

  /// 最近一次 setEnabled 的值与调用次数。
  @override
  bool enabled = false;
  int setEnabledCount = 0;

  /// 已就绪的频段（仅断言用；未就绪时访问 parameters 不完成）。
  List<FakeEqualizerBand> get bands => _params.bands;

  double get minDecibels => _params.minDecibels;
  double get maxDecibels => _params.maxDecibels;

  @override
  Future<EqualizerParameters> get parameters {
    if (autoReady) completeParameters();
    return _completer.future;
  }

  /// 手动让参数就绪。
  void completeParameters() {
    if (_completed) return;
    _completed = true;
    _completer.complete(_params);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    setEnabledCount++;
    this.enabled = enabled;
  }
}
