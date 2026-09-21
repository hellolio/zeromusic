import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/audio/equalizer_controller.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';

/// 均衡器行值（设置页与弹层单源：equalizerControllerProvider）。
String equalizerValueLabel(AppStrings strings, EqualizerState state) {
  if (!state.supported) return strings.eqUnsupported;
  return state.enabled ? strings.eqOn : strings.eqOff;
}

/// 打开均衡器弹层：窗口居中（桌面/移动一致，复用统一弹窗动效）。
/// 固定宽度与其他弹窗一致：避免「不支持」等短文案分支把窗口收窄。
Future<void> showEqualizerSheet(BuildContext context) {
  return showCenterPopup<void>(
    context,
    width: centerPopupWidth,
    child: const EqualizerSheet(),
  );
}

/// 均衡器弹层：三态降级。
///
/// - 不支持（非 Android 平台 / 引擎未提供）：仅说明文案；
/// - 未就绪（引擎未激活=首次播放前）：开关 + 「开始播放后可调节」提示；
/// - 就绪：开关 + 预设 chips + 每频段一行水平滑杆（频率标签 + dB 值）+ 重置。
class EqualizerSheet extends ConsumerWidget {
  const EqualizerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final state = ref.watch(equalizerControllerProvider);

    return GlassOverlay(
      radius: AppTokens.radiusL,
      // 内容可能超出弹层高度上限（移动端 50% 屏高），内部滚动；
      // 水平滑杆与纵向滚动手势方向正交，无竞技场冲突。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceM,
                AppTokens.spaceM,
                AppTokens.spaceM,
                AppTokens.spaceS,
              ),
              child: Text(
                strings.settingsEqualizer,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (!state.supported)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceM,
                  0,
                  AppTokens.spaceM,
                  AppTokens.spaceM,
                ),
                child: Text(
                  strings.eqUnsupportedHint,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSecondary),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceM,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.eqEnable,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    CupertinoSwitch(
                      key: const ValueKey('equalizer-switch'),
                      value: state.enabled,
                      onChanged: (v) => ref
                          .read(equalizerControllerProvider.notifier)
                          .setEnabled(v),
                    ),
                  ],
                ),
              ),
              if (!state.ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceM,
                    AppTokens.spaceS,
                    AppTokens.spaceM,
                    AppTokens.spaceM,
                  ),
                  child: Text(
                    strings.eqPlayToEnable,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondary),
                  ),
                )
              else if (state.enabled) ...[
                const SizedBox(height: AppTokens.spaceS),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceM,
                  ),
                  child: Wrap(
                    spacing: AppTokens.spaceS,
                    runSpacing: AppTokens.spaceXs,
                    children: [
                      for (final preset in EqualizerPreset.values)
                        ActionChip(
                          key: ValueKey('equalizer-preset-${preset.name}'),
                          label: Text(_presetLabel(strings, preset)),
                          onPressed: () => ref
                              .read(equalizerControllerProvider.notifier)
                              .applyPreset(preset),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceS),
                for (var i = 0; i < state.centerFrequencies.length; i++)
                  _BandSlider(index: i, state: state),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceM,
                    0,
                    AppTokens.spaceM,
                    AppTokens.spaceS,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('equalizer-reset'),
                      onPressed: () => ref
                          .read(equalizerControllerProvider.notifier)
                          .reset(),
                      child: Text(strings.eqReset),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spaceS),
            ],
          ],
        ),
      ),
    );
  }

  static String _presetLabel(AppStrings strings, EqualizerPreset preset) {
    switch (preset) {
      case EqualizerPreset.flat:
        return strings.eqPresetFlat;
      case EqualizerPreset.pop:
        return strings.eqPresetPop;
      case EqualizerPreset.rock:
        return strings.eqPresetRock;
      case EqualizerPreset.jazz:
        return strings.eqPresetJazz;
      case EqualizerPreset.classical:
        return strings.eqPresetClassical;
      case EqualizerPreset.electronic:
        return strings.eqPresetElectronic;
    }
  }
}

/// 单个频段行：频率标签 + 水平滑杆 + 当前 dB 值。
class _BandSlider extends ConsumerWidget {
  const _BandSlider({required this.index, required this.state});

  final int index;
  final EqualizerState state;

  /// 中心频率展示：60Hz / 910Hz / 3.6kHz / 14kHz。
  static String formatFrequency(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return k % 1 == 0 ? '${k.toInt()}kHz' : '${k.toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }

  /// 增益展示：+3.0dB / 0.0dB / -2.5dB。
  static String formatGain(double db) =>
      '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}dB';

  /// 0.5dB 步进分段数；量程 < 0.5dB 时 round 为 0，返回 null 不分段。
  static int? _divisions(double min, double max) {
    if (max <= min) return null;
    final d = ((max - min) * 2).round();
    return d > 0 ? d : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final min = state.minDecibels;
    final max = state.maxDecibels;
    final value = index < state.gains.length ? state.gains[index] : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              formatFrequency(state.centerFrequencies[index]),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondary),
            ),
          ),
          Expanded(
            child: Slider(
              key: ValueKey('equalizer-band-$index'),
              value: value.clamp(min, max),
              min: min,
              max: max,
              // 0.5dB 步进；量程过小（异常设备）时分段数可能为 0，
              // Slider 断言 divisions>0，故二次守卫为 null。
              divisions: _divisions(min, max),
              onChanged: (v) => ref
                  .read(equalizerControllerProvider.notifier)
                  .setBandGain(index, v),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              formatGain(value),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
