import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anim/app_curves.dart';
import '../../core/platform/device_type.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/audio/audio_controller.dart';
import '../components/glass_overlay.dart';

/// 全局迷你播放条「水滴胶囊」。
/// 移动端：悬于底栏上方、内容底部；桌面端：内容右下角悬浮。
///
/// 可见性规则：
/// - 媒体库为空（无当前曲目）时不渲染、不占布局空间；
/// - 进入完整播放页时隐藏（[hidden] = true）；
/// - 其余情况全局显示。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({
    super.key,
    required this.deviceType,
    this.hidden = false,
    this.onTap,
    this.onTogglePlay,
  });

  final DeviceType deviceType;

  /// 是否因当前处于完整播放页而隐藏。
  final bool hidden;

  /// 点按迷你条进入完整播放页（由骨架层决定如何进入）。
  final VoidCallback? onTap;

  /// 点按播放/暂停按钮切换状态。
  final VoidCallback? onTogglePlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioControllerProvider);
    // 无当前曲目：彻底不渲染，不占据底部布局空间。
    if (!state.hasTrack) return const SizedBox.shrink();
    final visible = !hidden;

    return AnimatedSlide(
      duration: AppCurves.miniPlayerMotion,
      curve: AppCurves.standard,
      offset: visible ? Offset.zero : const Offset(0, 1.5),
      child: AnimatedOpacity(
        duration: AppCurves.miniPlayerMotion,
        curve: AppCurves.standard,
        opacity: visible ? 1 : 0,
        child: deviceType == DeviceType.desktop
            ? _DesktopMiniPlayer(
                isPlaying: state.isPlaying,
                title: state.currentTrack?.title ?? '',
                subtitle: state.currentTrack?.subtitle ?? '',
                onTap: onTap,
                onTogglePlay: onTogglePlay,
              )
            : _MobileMiniPlayer(
                isPlaying: state.isPlaying,
                title: state.currentTrack?.title ?? '',
                subtitle: state.currentTrack?.subtitle ?? '',
                onTap: onTap,
                onTogglePlay: onTogglePlay,
              ),
      ),
    );
  }
}

class _MobileMiniPlayer extends StatelessWidget {
  const _MobileMiniPlayer({
    required this.isPlaying,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onTogglePlay,
  });

  static const double _coverSize = 44;

  final bool isPlaying;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;

  /// 胶囊左右内边距取高度的一半，圆角端不裁切封面。
  EdgeInsets get _capsulePadding {
    final capRadius = (_coverSize + 2 * AppTokens.spaceXs) / 2;
    return EdgeInsets.symmetric(
      horizontal: capRadius,
      vertical: AppTokens.spaceXs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassOverlay(
        blur: 30,
        radius: AppTokens.radiusPill,
        padding: _capsulePadding,
        child: Row(
          children: [
            _cover(context),
            const SizedBox(width: AppTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onTogglePlay,
              icon: AnimatedSwitcher(
                duration: AppCurves.quickMotion,
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(isPlaying),
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    return Container(
      width: _coverSize,
      height: _coverSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      child: const Icon(CupertinoIcons.music_note, size: 20),
    );
  }
}

class _DesktopMiniPlayer extends StatelessWidget {
  const _DesktopMiniPlayer({
    required this.isPlaying,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onTogglePlay,
  });

  final bool isPlaying;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassOverlay(
        blur: 30,
        radius: AppTokens.radiusL,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM, vertical: AppTokens.spaceS),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cover(context),
            const SizedBox(width: AppTokens.spaceM),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSecondary)),
              ],
            ),
            const SizedBox(width: AppTokens.spaceM),
            IconButton(
              onPressed: onTogglePlay,
              icon: Icon(isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill, size: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
      ),
      child: const Icon(CupertinoIcons.music_note, size: 18),
    );
  }
}
