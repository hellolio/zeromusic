import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/audio/audio_controller.dart';
import '../../../services/audio/track.dart';
import '../../../services/preferences/preferences_controller.dart';
import '../../components/glass_overlay.dart';
import 'player_background.dart';

/// 播放页面：全屏沉浸式，Apple Music 风格。
///
/// 核心签名动效【节拍变色背景】：见 [AnimatedPaletteBackground]——
/// 有封面时模糊大图呼吸变色，无封面时随机色板五彩渐变。
/// 由迷你条上滑/点按（移动端）或左侧导航「播放页」（桌面端）进入。
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final state = ref.watch(audioControllerProvider);
    final track = state.currentTrack;
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPaletteBackground(
            seed: track?.id.hashCode ?? 0,
            isPlaying: state.isPlaying,
            hasTrack: state.hasTrack,
            level: prefs.backgroundEffect,
            coverPath: track?.coverPath,
          ),
          SafeArea(
            child: state.hasTrack
                ? _PlayerContent(state: state, strings: strings)
                : _EmptyPlayback(strings: strings),
          ),
        ],
      ),
    );
  }
}

/// 空媒体库空态：仅静态默认背景 + 提示。
class _EmptyPlayback extends StatelessWidget {
  const _EmptyPlayback({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_outline,
            size: 64,
            color: Colors.white70,
          ),
          const SizedBox(height: AppTokens.spaceM),
          Text(
            strings.empty,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// 播放页主体内容。
class _PlayerContent extends ConsumerWidget {
  const _PlayerContent({required this.state, required this.strings});

  final PlaybackState state;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.currentTrack!;
    final audio = ref.read(audioControllerProvider.notifier);

    return Column(
      children: [
        const SizedBox(height: AppTokens.spaceS),
        _CloseBar(onTap: () => Navigator.of(context).maybePop()),
        const Spacer(flex: 1),
        Expanded(
          flex: 5,
          child: _RotatingCover(track: track, isPlaying: state.isPlaying),
        ),
        const Spacer(flex: 1),
        const SizedBox(height: AppTokens.spaceS),
        _TrackInfo(track: track),
        const SizedBox(height: AppTokens.spaceL),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceL),
          child: _PlayerSeekBar(
            position: state.position,
            duration: state.duration,
            onSeek: audio.seek,
          ),
        ),
        const SizedBox(height: AppTokens.spaceS),
        _TransportRow(
          strings: strings,
          isPlaying: state.isPlaying,
          mode: state.playbackMode,
          onRepeat: audio.cyclePlaybackMode,
          onPrev: audio.previous,
          onTogglePlay: audio.togglePlay,
          onNext: audio.next,
          onLyrics: () => _showLyricsSheet(context, strings),
        ),
        const SizedBox(height: AppTokens.spaceS),
        _BottomRow(
          strings: strings,
          onOpenQueue: () => _showQueueSheet(context, ref),
        ),
        const SizedBox(height: AppTokens.spaceM),
      ],
    );
  }
}

/// 顶部「▾ 下拉收起」按钮。
class _CloseBar extends StatelessWidget {
  const _CloseBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: const GlassOverlay(
          padding: EdgeInsets.all(8),
          radius: AppTokens.radiusPill,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 播放中缓慢旋转的封面；暂停停止；减弱动效时静止。
class _RotatingCover extends StatefulWidget {
  const _RotatingCover({required this.track, required this.isPlaying});

  final Track track;
  final bool isPlaying;

  @override
  State<_RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<_RotatingCover>
    with SingleTickerProviderStateMixin {
  static const Duration _spin = Duration(seconds: 24);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _spin,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RotatingCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (MediaQuery.disableAnimationsOf(context) || !widget.isPlaying) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            min(constraints.maxWidth, min(constraints.maxHeight, 340.0));
        return Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: RotationTransition(
              turns: _controller,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusL),
                child: _CoverImage(track: widget.track),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 封面图：有封面加载本地图；无封面展示与背景同源色板的渐变 + 音符。
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final cover = track.coverPath;
    if (cover != null && cover.isNotEmpty) {
      return Image.file(
        File(cover),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final palette = pickPalette(track.id.hashCode);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette[0], palette[2], palette[4]],
        ),
      ),
      child: const Icon(
        CupertinoIcons.music_note,
        size: 96,
        color: Colors.white,
      ),
    );
  }
}

/// 歌名 · 歌手 · 专辑。
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [track.artist, track.album]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceL),
      child: Column(
        children: [
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

/// 可拖动进度条：拖动中显示时间气泡与放大手柄，松手 seek。
class _PlayerSeekBar extends StatefulWidget {
  const _PlayerSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> {
  static const double _handleSize = 18;
  static const double _hitHeight = 36;
  static const double _trackHeight = 4;

  double? _dragFraction;
  double _width = 0;

  bool get _canSeek => widget.duration > Duration.zero;

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    if (!_canSeek) return 0;
    final ms = widget.duration.inMilliseconds;
    if (ms <= 0) return 0;
    return (widget.position.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  Duration get _preview {
    final ms = (widget.duration.inMilliseconds * _fraction).round();
    return Duration(milliseconds: ms);
  }

  void _startDrag(double dx) {
    if (!_canSeek) return;
    setState(() => _dragFraction = (dx / _width).clamp(0.0, 1.0));
  }

  void _updateDrag(double dx) {
    if (!_canSeek || _dragFraction == null) return;
    setState(() => _dragFraction = (dx / _width).clamp(0.0, 1.0));
  }

  void _endDrag() {
    if (!_canSeek || _dragFraction == null) return;
    widget.onSeek(_preview);
    setState(() => _dragFraction = null);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dragging = _dragFraction != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final width = constraints.maxWidth;
        final fraction = _fraction;
        final left = (fraction * width).clamp(0.0, width - _handleSize);
        final fillWidth = (fraction * width).clamp(_handleSize, width);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  key: const ValueKey('player-seek-bar'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragDown: (d) => _startDrag(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) =>
                      _updateDrag(d.localPosition.dx),
                  onHorizontalDragEnd: (_) => _endDrag(),
                  child: SizedBox(
                    height: _hitHeight,
                    width: width,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: _trackHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: fillWidth,
                            height: _trackHeight,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusPill,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  top: (_hitHeight - _handleSize) / 2,
                  child: AnimatedScale(
                    scale: dragging ? 1.25 : 1.0,
                    duration: AppCurves.quickMotion,
                    curve: AppCurves.quick,
                    child: Container(
                      width: _handleSize,
                      height: _handleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (dragging)
                  Positioned(
                    left: (left + _handleSize / 2 - 28).clamp(0.0, width - 56),
                    top: -6,
                    child: Container(
                      key: const ValueKey('seek-bubble'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(AppTokens.radiusS),
                      ),
                      child: Text(
                        _fmt(_preview),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTokens.fontSizeCaption,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(dragging ? _preview : widget.position),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppTokens.fontSizeCaption,
                  ),
                ),
                Text(
                  _fmt(widget.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppTokens.fontSizeCaption,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 空格键行：🔁 播放模式 · ⏮ · ▶/⏸ · ⏭ · 🎤 歌词。
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.strings,
    required this.isPlaying,
    required this.mode,
    required this.onRepeat,
    required this.onPrev,
    required this.onTogglePlay,
    required this.onNext,
    required this.onLyrics,
  });

  final AppStrings strings;
  final bool isPlaying;
  final PlaybackMode mode;
  final VoidCallback onRepeat;
  final VoidCallback onPrev;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onLyrics;

  (IconData, String) _modeStyle(AppStrings s, PlaybackMode m) {
    switch (m) {
      case PlaybackMode.sequential:
        return (CupertinoIcons.repeat, s.playerRepeatOff);
      case PlaybackMode.loopAll:
        return (CupertinoIcons.repeat, s.playerRepeatAll);
      case PlaybackMode.loopOne:
        return (CupertinoIcons.repeat_1, s.playerRepeatOne);
      case PlaybackMode.shuffle:
        return (CupertinoIcons.shuffle, s.playerShuffle);
    }
  }

  Widget _transportButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 30,
    Color? color,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: size,
      padding: const EdgeInsets.all(10),
      icon: Icon(icon, color: color ?? Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (repeatIcon, repeatLabel) = _modeStyle(strings, mode);
    final repeatActive = mode != PlaybackMode.sequential;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _transportButton(
          context,
          icon: repeatIcon,
          tooltip: repeatLabel,
          onTap: onRepeat,
          size: 26,
          color: repeatActive ? Theme.of(context).colorScheme.primary : Colors.white,
        ),
        _transportButton(
          context,
          icon: CupertinoIcons.backward_end_fill,
          tooltip: strings.miniPrevious,
          onTap: onPrev,
          size: 34,
        ),
        IconButton(
          onPressed: onTogglePlay,
          tooltip: strings.miniPlayPause,
          padding: EdgeInsets.zero,
          iconSize: 48,
          icon: AnimatedSwitcher(
            duration: AppCurves.quickMotion,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              key: ValueKey(isPlaying),
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
        _transportButton(
          context,
          icon: CupertinoIcons.forward_end_fill,
          tooltip: strings.miniNext,
          onTap: onNext,
          size: 34,
        ),
        _transportButton(
          context,
          icon: CupertinoIcons.mic_fill,
          tooltip: strings.playerLyrics,
          onTap: onLyrics,
          size: 26,
        ),
      ],
    );
  }
}

/// 底行：播放队列 ▾ · 收藏 ♥（占位）· ⋯ · 睡眠定时（占位）。
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.strings, required this.onOpenQueue});

  final AppStrings strings;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        InkWell(
          key: const ValueKey('player-queue-button'),
          onTap: onOpenQueue,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceM,
              vertical: AppTokens.spaceS,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.list_bullet,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Text(
                  strings.playerQueue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTokens.fontSizeBody,
                  ),
                ),
              ],
            ),
          ),
        ),
        _placeholderButton(
          context,
          icon: CupertinoIcons.heart,
          tooltip: strings.favorite,
        ),
        _placeholderButton(
          context,
          icon: CupertinoIcons.ellipsis,
          tooltip: strings.playerComingSoon,
        ),
        _placeholderButton(
          context,
          icon: CupertinoIcons.moon_zzz_fill,
          tooltip: strings.playerComingSoon,
        ),
      ],
    );
  }

  Widget _placeholderButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
  }) {
    return IconButton(
      onPressed: null,
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white54),
    );
  }
}

/// 播放队列 bottom sheet：当前曲目高亮，点行即切歌并收起。
Future<void> _showQueueSheet(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final state = ref.read(audioControllerProvider);
  final queue = state.queue;
  if (queue.isEmpty) return;
  final audio = ref.read(audioControllerProvider.notifier);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: GlassOverlay(
            radius: AppTokens.radiusL,
            tint: Colors.black.withValues(alpha: 0.55),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceM),
                  child: Text(
                    strings.playerUpNext,
                    style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (_, index) {
                      final current = index == state.currentIndex;
                      return _QueueRow(
                        track: queue[index],
                        current: current,
                        onTap: () {
                          audio.playQueue(queue, startIndex: index);
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTokens.spaceS),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.current,
    required this.onTap,
  });

  final Track track;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = current ? scheme.primary : Colors.white;
    final subtitle = track.artist;
    return ListTile(
      leading: Icon(CupertinoIcons.music_note, color: color),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: (subtitle != null && subtitle.isNotEmpty)
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            )
          : null,
      trailing: current
          ? Icon(CupertinoIcons.speaker_3_fill, color: scheme.primary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

/// 歌词 bottom sheet：暂仅「暂无歌词」占位。
Future<void> _showLyricsSheet(BuildContext context, AppStrings strings) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetContext) {
      return SafeArea(
        child: GlassOverlay(
          radius: AppTokens.radiusL,
          tint: Colors.black.withValues(alpha: 0.55),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.playerLyrics,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppTokens.spaceL),
                const Icon(
                  CupertinoIcons.mic_fill,
                  size: 40,
                  color: Colors.white54,
                ),
                const SizedBox(height: AppTokens.spaceM),
                Text(
                  strings.playerNoLyrics,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: AppTokens.spaceM),
              ],
            ),
          ),
        ),
      );
    },
  );
}