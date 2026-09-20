import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/platform/device_type.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/app_providers.dart';
import '../../../data/database/app_database.dart';
import '../../../services/audio/audio_controller.dart';
import '../../../services/audio/sleep_timer_controller.dart';
import '../../../services/audio/track.dart';
import '../../../services/lyrics/lyrics_controller.dart';
import '../../../services/lyrics/lyrics_line.dart';
import '../../../services/preferences/preferences_controller.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';
import '../../mini_player/mini_player_bounce.dart';
import 'lyrics_editor.dart';
import 'lyrics_view.dart';
import 'player_background.dart';
import 'pull_to_dismiss.dart';

/// 播放页面：全屏沉浸式，Apple Music 风格。
///
/// 核心签名动效【节拍变色背景】：见 [AnimatedPaletteBackground]——
/// 有封面时模糊大图呼吸变色，无封面时随机色板五彩渐变。
/// 唯一入口：点按/上滑迷你播放条（移动端与桌面端一致）。
///
/// 顶部小横条始终显示：点按（移动端可下拉）即收起本页返回上一页。
/// 歌词：
/// - 桌面端：播放页内左侧控制元素 + 右侧歌词分栏（顶部 × 关闭，动画滑入/滑出）；
/// - 移动端：📄 切换为全屏歌词视图，切换按钮与播放页底行「歌词」槽位对齐。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, this.anchor, this.miniPlayerSize});

  /// 迷你条中心的屏幕坐标：收起动画（[PullToDismiss]）围绕该点缩放进迷你条。
  /// 为 null（如直接 push）时回退底部中央。
  final Offset? anchor;

  /// 迷你条尺寸：收起时页面非等比缩放逼近迷你条胶囊形状（宽扁）。
  /// 为 null 时按等比缩放兜底。
  final Size? miniPlayerSize;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 移动端：当前是否全屏歌词视图（true）/ 播放视图（false）。
  bool _lyricsMode = false;

  /// 桌面端：右侧歌词分栏是否展开（默认收起，点「歌词」打开）。
  bool _lyricsPanelOpen = false;

  /// 下拉 / 点收起条共用的收起动画控制器。
  final GlobalKey<PullToDismissState> _dismissKey =
      GlobalKey<PullToDismissState>();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final state = ref.watch(audioControllerProvider);
    final track = state.currentTrack;
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

    return Scaffold(
      // 拖动时背景随整页移动，露出下方路由而非一块静态黑色底。
      backgroundColor: Colors.transparent,
      body: PullToDismiss(
        key: _dismissKey,
        enabled: true,
        // 仅屏幕上方 60%（进度条上方一定距离）下拉才退出，避免与进度条拖动冲突。
        startAreaFraction: 0.6,
        // 页面下滑到达迷你条时 → 迷你条开始回弹（与收进过程同步，收完正好结束）。
        onDismissStart: () =>
            ref.read(miniPlayerBounceProvider.notifier).bump(),
        onDismiss: () => Navigator.of(context).maybePop(),
        // 围绕迷你条中心收进迷你条；拿不到锚点时回退右下/底部中央。
        collapseAnchor: widget.anchor,
        // 收起时非等比缩放逼近迷你条胶囊形状（宽扁）。
        collapseTargetSize: widget.miniPlayerSize,
        collapseAlignment: isDesktop
            ? Alignment.bottomRight
            : Alignment.bottomCenter,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 实心兜底底色：播放页自身始终不透明，下层页面只在播放页缩小
            // 露出的区域显示，绝不从播放页内部透出。
            const ColoredBox(color: Colors.black),
            AnimatedPaletteBackground(
              seed: track?.id.hashCode ?? 0,
              isPlaying: state.isPlaying,
              hasTrack: state.hasTrack,
              level: prefs.backgroundEffect,
              coverPath: track?.coverPath,
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: AppTokens.spaceS),
                  _CloseBar(
                    isDesktop: isDesktop,
                    // 顶部横线点按：走同一收起动画（含迷你条回弹）。
                    onTap: () => _dismissKey.currentState?.collapse(),
                  ),
                  Expanded(
                    child: state.hasTrack
                        ? _PlayerContent(
                            state: state,
                            strings: strings,
                            isDesktop: isDesktop,
                            lyricsOpen: isDesktop
                                ? _lyricsPanelOpen
                                : _lyricsMode,
                            onToggleLyrics: () => setState(() {
                              if (isDesktop) {
                                _lyricsPanelOpen = !_lyricsPanelOpen;
                              } else {
                                _lyricsMode = !_lyricsMode;
                              }
                            }),
                          )
                        : _EmptyPlayback(strings: strings),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// 播放页主体内容（不含顶部收起条）：移动端播放/歌词双视图 + 桌面端分栏。
class _PlayerContent extends ConsumerWidget {
  const _PlayerContent({
    required this.state,
    required this.strings,
    required this.isDesktop,
    required this.lyricsOpen,
    required this.onToggleLyrics,
  });

  final PlaybackState state;
  final AppStrings strings;
  final bool isDesktop;
  final bool lyricsOpen;
  final VoidCallback onToggleLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.currentTrack!;
    final audio = ref.read(audioControllerProvider.notifier);

    // 当前曲目喜欢态：仅当播放中的歌曲存在于媒体库时可切换。
    final songs = ref.watch(allSongsProvider).value ?? const <Song>[];
    Song? favSong;
    for (final s in songs) {
      if (s.id.toString() == track.id) {
        favSong = s;
        break;
      }
    }
    final isFavorite = favSong?.isFavorite ?? false;

    // 睡眠定时剩余时长（null = 未启用）。
    final sleepLeft = ref.watch(sleepTimerProvider);

    // 歌词数据。
    final lines = ref.watch(lyricsLinesProvider).value ?? const <LyricsLine>[];
    final activeIndex = ref.watch(activeLyricIndexProvider);
    final lyricsRaw = ref.watch(lyricsRawProvider).value;

    void seekTo(Duration d) => audio.seek(d);

    Future<void> editLyrics({String? initial}) async {
      final songId = ref.read(currentSongIdProvider);
      if (songId == null) return;
      await showLyricsEditor(context, ref, songId, initial: initial);
    }

    final playerColumn = Column(
      children: [
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
          onQueue: () => _showQueueSheet(context, ref),
        ),
        const SizedBox(height: AppTokens.spaceS),
        _BottomRow(
          strings: strings,
          isFavorite: isFavorite,
          favEnabled: favSong != null,
          sleepLeft: sleepLeft,
          volume: ref.watch(preferencesProvider).value?.defaultVolume ?? 1.0,
          lyricsActive: lyricsOpen,
          onToggleFavorite: favSong == null
              ? null
              : () => ref
                    .read(mediaRepositoryProvider)
                    .toggleFavorite(favSong!.id, !isFavorite),
          onOpenTimer: () => _showSleepTimerSheet(context, ref),
          onOpenVolume: () => _showVolumePopover(context, ref),
          onOpenLyrics: onToggleLyrics,
        ),
        const SizedBox(height: AppTokens.spaceM),
      ],
    );

    // 歌词面板（桌面端右侧分栏 / 移动端全屏视图共享控件）。
    final lyricsView = LyricsView(
      lines: lines,
      activeIndex: activeIndex,
      onSeek: seekTo,
      strings: strings,
      onAddLyrics: () => editLyrics(),
      onEditLyrics: () => editLyrics(initial: lyricsRaw),
    );

    // 桌面端：左侧控制元素固定，右侧歌词分栏动画展开/收起（抽屉式滑入滑出）。
    if (isDesktop) {
      final panelBody = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.playerLyrics,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTokens.fontSizeTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('lyrics-panel-close'),
                tooltip: strings.cancel,
                onPressed: onToggleLyrics,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceS),
          Expanded(child: lyricsView),
        ],
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = (constraints.maxWidth * 0.45).clamp(280.0, 460.0);
          return Row(
            children: [
              Expanded(flex: 55, child: playerColumn),
              AnimatedSwitcher(
                duration: AppCurves.standardMotion,
                switchInCurve: AppCurves.standard,
                switchOutCurve: AppCurves.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: lyricsOpen
                    ? SizedBox(
                        key: const ValueKey('lyrics-panel-open'),
                        width: panelWidth,
                        child: Row(
                          children: [
                            Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(
                                vertical: AppTokens.spaceL,
                              ),
                              color: Colors.white12,
                            ),
                            const SizedBox(width: AppTokens.spaceL),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: AppTokens.spaceL,
                                ),
                                child: panelBody,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('lyrics-panel-closed'),
                        width: 0,
                      ),
              ),
            ],
          );
        },
      );
    }

    // 移动端：播放视图 ↔ 全屏歌词视图平滑过渡。
    final mobileLyrics = LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(child: lyricsView),
            // 切换按钮与播放页底行「歌词」槽位对齐：鼠标几乎不移动即可切回。
            Positioned(
              right: _lyricsToggleRight(constraints.maxWidth),
              bottom: _lyricsToggleBottom,
              child: _LyricsToggleButton(
                strings: strings,
                onTap: onToggleLyrics,
              ),
            ),
          ],
        );
      },
    );
    return AnimatedSwitcher(
      duration: AppCurves.pageTransition,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.standard,
      transitionBuilder: (child, animation) {
        // 歌词从下方滑入、播放视图反向滑出；反向时自动对称。
        final isLyrics = child.key == const ValueKey('lyrics-view');
        final begin = isLyrics ? const Offset(0, 0.06) : const Offset(0, -0.06);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: begin, end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: lyricsOpen
          ? KeyedSubtree(
              key: const ValueKey('lyrics-view'),
              child: mobileLyrics,
            )
          : KeyedSubtree(
              key: const ValueKey('player-view'),
              child: playerColumn,
            ),
    );
  }
}

/// 底行槽位几何：播放页底行与歌词视图切回按钮共享，保证二者对齐。
const double _bottomSlotWidth = 48;
const double _bottomSlotHeight = 52;

/// 音量按钮锚点（竖向音量弹窗定位基准，全局单例保证跨构建稳定）。
final GlobalKey _volumeAnchorKey = GlobalKey();

/// 移动端歌词切换按钮（圆形）的直径。
const double _lyricsToggleDiameter = 46;

/// 「歌词 → 播放视图」右下角切换按钮（仅移动端全屏歌词视图显示）。
///
/// 位置与播放页底行「歌词」槽位对齐：从播放页点歌词进入歌词页后，
/// 几乎不用移动鼠标即可点该按钮切回播放视图。
class _LyricsToggleButton extends StatelessWidget {
  const _LyricsToggleButton({required this.strings, required this.onTap});

  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: strings.lyricsBackToPlayer,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('lyrics-toggle-player'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(
              CupertinoIcons.music_note,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// 切换按钮距容器右缘的偏移：使按钮中心与底行第 4 个槽位（歌词）中心对齐。
/// 底行 4 个等宽槽位 spaceEvenly 排布，槽间空隙 = (W - 4*slotW) / 5。
double _lyricsToggleRight(double width) {
  final gap = (width - 4 * _bottomSlotWidth) / 5;
  return gap + (_bottomSlotWidth - _lyricsToggleDiameter) / 2;
}

/// 切换按钮距容器底缘的偏移：与底行中心对齐（底行下方有 spaceM 间距）。
double get _lyricsToggleBottom =>
    AppTokens.spaceM + (_bottomSlotHeight - _lyricsToggleDiameter) / 2;

/// 顶部收起条：移动端为 Apple Music 风格细横线；桌面端为倒三角（点击区更大）。
class _CloseBar extends StatelessWidget {
  const _CloseBar({required this.onTap, this.isDesktop = false});

  final VoidCallback onTap;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('player-close-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: isDesktop
          ? const SizedBox(
              height: 32,
              child: Center(
                child: _DownTriangle(key: ValueKey('player-close-triangle')),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceL),
              child: const Center(
                child: SizedBox(
                  width: 44,
                  height: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// 倒 V / chevron-down（桌面端收起条）：比细横线更醒目、点击区更大。
class _DownTriangle extends StatelessWidget {
  const _DownTriangle({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 15),
      painter: _DownTrianglePainter(color: Colors.white),
    );
  }
}

class _DownTrianglePainter extends CustomPainter {
  const _DownTrianglePainter({required this.color});

  /// 描边粗细（适中，不过粗）。
  static const double _strokeWidth = 2.4;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 长宽不等（宽 > 高，约 2:1）的 V 形：两段圆头线在底部交汇。
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(_strokeWidth / 2 + 1, 2)
      ..lineTo(size.width / 2, size.height - 2)
      ..lineTo(size.width - _strokeWidth / 2 - 1, 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DownTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
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
        final size = min(
          constraints.maxWidth,
          min(constraints.maxHeight, 340.0),
        );
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
    final subtitle = [
      track.artist,
      track.album,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
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

  /// 点击进度条直接跳转：按点按位置换算比例 seek。
  /// 纯点击不会触发 [onHorizontalDragEnd]，必须单独处理点按手势。
  void _seekAt(double dx) {
    if (!_canSeek) return;
    final f = (dx / _width).clamp(0.0, 1.0);
    widget.onSeek(
      Duration(milliseconds: (widget.duration.inMilliseconds * f).round()),
    );
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
                  // 点击（不滑动）时直接按点按位置 seek。
                  onTapUp: (d) => _seekAt(d.localPosition.dx),
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

/// 空格键行：🔁 播放模式 · ⏮ · ▶/⏸ · ⏭ · ▾ 播放队列。
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.strings,
    required this.isPlaying,
    required this.mode,
    required this.onRepeat,
    required this.onPrev,
    required this.onTogglePlay,
    required this.onNext,
    required this.onQueue,
  });

  final AppStrings strings;
  final bool isPlaying;
  final PlaybackMode mode;
  final VoidCallback onRepeat;
  final VoidCallback onPrev;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onQueue;

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
          color: repeatActive
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
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
        IconButton(
          key: const ValueKey('player-queue-button'),
          onPressed: onQueue,
          tooltip: strings.playerQueue,
          iconSize: 26,
          padding: const EdgeInsets.all(10),
          icon: const Icon(CupertinoIcons.list_bullet, color: Colors.white),
        ),
      ],
    );
  }
}

/// 底行（从左到右）：喜欢 ♥ · 睡眠定时 🌙 · 音量 🔊 · 歌词 📄。
/// 四个槽位等宽，定时启用时图标+倒计时纵向堆叠，宽度固定不变不挤占其它按钮。
class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.strings,
    required this.isFavorite,
    required this.favEnabled,
    required this.sleepLeft,
    required this.volume,
    required this.lyricsActive,
    required this.onToggleFavorite,
    required this.onOpenTimer,
    required this.onOpenVolume,
    required this.onOpenLyrics,
  });

  /// 槽位固定宽度：等宽图标列，任何变化不影响其它按钮位置。
  static const double _slotWidth = _bottomSlotWidth;
  static const double _slotHeight = _bottomSlotHeight;

  final AppStrings strings;
  final bool isFavorite;
  final bool favEnabled;
  final Duration? sleepLeft;
  final double volume;
  final bool lyricsActive;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onOpenTimer;
  final VoidCallback onOpenVolume;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _slotHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 喜欢（红心动画切换）。
          SizedBox(
            width: _slotWidth,
            child: IconButton(
              key: const ValueKey('player-favorite-button'),
              onPressed: favEnabled ? onToggleFavorite : null,
              tooltip: isFavorite ? strings.unfavorite : strings.favorite,
              icon: AnimatedSwitcher(
                duration: AppCurves.quickMotion,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  key: ValueKey(isFavorite),
                  color: isFavorite ? AppTokens.favorite : Colors.white,
                ),
              ),
            ),
          ),
          // 睡眠定时（启用时图标 + mm:ss 倒计时，纵向堆叠于固定槽内）。
          _TimerButton(
            strings: strings,
            sleepLeft: sleepLeft,
            onTap: onOpenTimer,
            width: _slotWidth,
            height: _slotHeight,
          ),
          // 音量（静音时换图标）。
          SizedBox(
            key: _volumeAnchorKey,
            width: _slotWidth,
            child: IconButton(
              key: const ValueKey('player-volume-button'),
              onPressed: onOpenVolume,
              tooltip: strings.playerVolume,
              icon: Icon(
                volume <= 0
                    ? CupertinoIcons.volume_mute
                    : CupertinoIcons.speaker_2_fill,
                color: Colors.white,
              ),
            ),
          ),
          // 歌词（展开时高亮）。
          SizedBox(
            width: _slotWidth,
            child: IconButton(
              key: const ValueKey('player-lyrics-button'),
              onPressed: onOpenLyrics,
              tooltip: strings.playerLyrics,
              icon: Icon(
                CupertinoIcons.doc_text,
                color: lyricsActive
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 睡眠定时按钮：未启用显示 🌙；启用后 🌙 + mm:ss 倒计时（仅图标与时间，无文案）。
class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.strings,
    required this.sleepLeft,
    required this.onTap,
    this.width = 48,
    this.height = 52,
  });

  final AppStrings strings;
  final Duration? sleepLeft;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final remaining = sleepLeft;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        key: const ValueKey('player-timer-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: remaining != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.moon_zzz_fill,
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatClock(remaining),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: AppTokens.fontSizeCaption,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              )
            : const Center(
                child: Icon(
                  CupertinoIcons.moon_zzz_fill,
                  size: 22,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// mm:ss 倒计时格式。
String _formatClock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 睡眠定时选择。
Future<void> _showSleepTimerSheet(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final current = ref.read(sleepTimerProvider);
  const presets = [15, 30, 45, 60];

  final result = await showCenterPopup<Duration?>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
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
              strings.playerSleepTimer,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _sleepTile(
            context,
            strings,
            strings.playerSleepOff,
            Duration.zero,
            current,
          ),
          for (final m in presets)
            _sleepTile(
              context,
              strings,
              strings.sleepTimerMinutes(m),
              Duration(minutes: m),
              current,
            ),
          const SizedBox(height: AppTokens.spaceS),
        ],
      ),
    ),
  );

  if (result == null) return; // 点击外部/取消。
  final timer = ref.read(sleepTimerProvider.notifier);
  if (result <= Duration.zero) {
    timer.stop();
  } else {
    timer.start(result);
  }
}

Widget _sleepTile(
  BuildContext context,
  AppStrings strings,
  String label,
  Duration value,
  Duration? current,
) {
  final theme = Theme.of(context);
  final checked = value == Duration.zero ? current == null : current == value;
  return ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(
      checked ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
      color: checked
          ? theme.colorScheme.primary
          : theme.colorScheme.onSecondary,
    ),
    title: Text(
      label,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: checked
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface,
        fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
    onTap: () => Navigator.of(context).pop(value),
  );
}

/// 音量调节：在音量按钮正上方弹出竖向滑杆窗口（不遮暗背景），
/// 拖动即时持久化并应用到引擎；点击窗口外任意处关闭。
void _showVolumePopover(BuildContext context, WidgetRef ref) {
  final box = _volumeAnchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return;
  final overlay = Overlay.of(context);
  final anchor = box.localToGlobal(Offset.zero);
  final anchorSize = box.size;
  final overlaySize = overlay.context.size ?? Size.zero;

  // 竖向滑杆只需要容纳百分比、滑块和图标，保持紧凑避免多余留白。
  const popWidth = 56.0;
  const popHeight = 216.0;

  // 水平：以按钮中心为基准，靠边时留 12px 间距。
  var left = anchor.dx + anchorSize.width / 2 - popWidth / 2;
  final maxLeft = (overlaySize.width - popWidth - 12.0).clamp(
    12.0,
    double.infinity,
  );
  left = left.clamp(12.0, maxLeft);
  // 垂直：优先按钮上方；上方空间不足时翻转到下方。
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
          child: const _VolumePopover(),
        ),
      ],
    ),
  );
  overlay.insert(entry);
}

/// 竖向音量窗口：百分比 / 竖向滑杆 / 静音图标，实时写入偏好并同步引擎。
/// 点击窗口外部（透明点击层）关闭；窗口内仅滑杆响应拖拽。
class _VolumePopover extends ConsumerWidget {
  const _VolumePopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(preferencesProvider).value?.defaultVolume ?? 1.0;
    final theme = Theme.of(context);
    // 与其他弹窗一致套用白色文字主题：浅色模式下玻璃窗偏暗，默认黑字不清。
    return GlassPopupTextTheme(
      child: GlassOverlay(
        key: const ValueKey('player-volume-popover'),
        radius: AppTokens.radiusM,
        tint: theme.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.8),
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
                  key: const ValueKey('player-volume-slider'),
                  value: volume.clamp(0.0, 1.0),
                  onChanged: (v) =>
                      ref.read(preferencesProvider.notifier).setDefaultVolume(v),
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

/// 播放队列：当前曲目高亮，点行即切歌并收起。
Future<void> _showQueueSheet(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final state = ref.read(audioControllerProvider);
  final queue = state.queue;
  if (queue.isEmpty) return;
  final audio = ref.read(audioControllerProvider.notifier);

  await showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      tint: Colors.black.withValues(alpha: 0.55),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceM,
              AppTokens.spaceM,
              AppTokens.spaceM,
              AppTokens.spaceS,
            ),
            child: Text(
              strings.playerUpNext,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          Flexible(
            child: ListView.separated(
              // 显式 zero padding：null 会让 ListView 吸收 MediaQuery
              // 的安全区高度（居中弹窗内无此概念）。
              padding: EdgeInsets.zero,
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
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppTokens.spaceS),
        ],
      ),
    ),
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
      dense: true,
      visualDensity: VisualDensity.compact,
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
