import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../services/preferences/preferences_controller.dart';
import 'center_popup.dart';
import 'glass_overlay.dart';

/// 音量调节：在锚点控件正上方弹出竖向滑杆小窗（不遮暗背景），
/// 拖动即时持久化并应用到引擎；点击窗口外任意处关闭。
///
/// 与播放页 / 桌面歌词条 / 设置页共用同一数据源（偏好 defaultVolume）。
/// [anchorKey] 需挂在锚点控件（按钮或其定宽包裹）上。
void showVolumePopover(BuildContext context, GlobalKey anchorKey) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return;
  final overlay = Overlay.of(context);
  final anchor = box.localToGlobal(Offset.zero);
  final anchorSize = box.size;
  final overlaySize = overlay.context.size ?? Size.zero;

  // 竖向滑杆只需要容纳百分比、滑块和图标，保持紧凑避免多余留白。
  const popWidth = 56.0;
  const popHeight = 216.0;

  // 水平：以锚点中心为基准，靠边时留 12px 间距。
  var left = anchor.dx + anchorSize.width / 2 - popWidth / 2;
  final maxLeft = (overlaySize.width - popWidth - 12.0).clamp(
    12.0,
    double.infinity,
  );
  left = left.clamp(12.0, maxLeft);
  // 垂直：优先锚点上方；上方空间不足时翻转到下方。
  var top = anchor.dy - popHeight - 12;
  if (top < 12) {
    top = anchor.dy + anchorSize.height + 12;
    if (top + popHeight > overlaySize.height) top = 12;
  }

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        // 透明点击层：仅用于点击外部关闭，不遮暗背景。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: entry.remove,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: popWidth,
          height: popHeight,
          child: const VolumePopover(),
        ),
      ],
    ),
  );
  overlay.insert(entry);
}

/// 竖向音量窗口：百分比 / 竖向滑杆 / 静音图标，实时写入偏好并同步引擎。
/// 点击窗口外部（透明点击层）关闭；窗口内仅滑杆响应拖拽。
class VolumePopover extends ConsumerWidget {
  const VolumePopover({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(preferencesProvider).value?.defaultVolume ?? 1.0;
    final theme = Theme.of(context);
    // 与其他弹窗一致套用白色文字主题：浅色模式下玻璃窗偏暗，默认黑字不清。
    return GlassPopupTextTheme(
      child: GlassOverlay(
        key: const ValueKey('volume-popover'),
        radius: AppTokens.radiusM,
        // 不传 tint：与其他弹窗一致的统一灰雾，避免雾渐变中段出现色带。
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              '${(volume * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  key: const ValueKey('volume-slider'),
                  value: volume.clamp(0.0, 1.0),
                  onChanged: (v) => ref
                      .read(preferencesProvider.notifier)
                      .setDefaultVolume(v),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              volume <= 0
                  ? CupertinoIcons.volume_mute
                  : CupertinoIcons.speaker_2_fill,
              size: 16,
              color: theme.colorScheme.onSecondary,
            ),
            const SizedBox(height: AppTokens.spaceXs),
          ],
        ),
      ),
    );
  }
}
