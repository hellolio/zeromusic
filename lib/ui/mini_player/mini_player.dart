import 'dart:io' show File;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anim/app_curves.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/device_type.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/audio/audio_controller.dart';
import '../../services/audio/track.dart';
import '../components/glass_overlay.dart';

/// 全局迷你播放条「水滴胶囊」。
/// 移动端：悬于底栏上方、内容底部；桌面端：内容右下角悬浮。
///
/// 可见性规则：
/// - 媒体库为空（无当前曲目）时不渲染、不占布局空间；
/// - 进入完整播放页时隐藏（[hidden] = true）；
/// - 其余情况全局显示。
///
/// 播放行为全部经 [AudioController] 编排（内部只依赖 [AudioEngine] 抽象）。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({
    super.key,
    required this.deviceType,
    this.hidden = false,
    this.onTap,
    this.onTogglePlay,
    this.onNext,
    this.onPrev,
  });

  final DeviceType deviceType;

  /// 是否因当前处于完整播放页而隐藏。
  final bool hidden;

  /// 点按迷你条进入完整播放页（由骨架层决定如何进入）。
  final VoidCallback? onTap;

  /// 点按播放/暂停按钮切换状态。
  final VoidCallback? onTogglePlay;

  /// 切到下一首（桌面按钮 / 移动端左滑）。
  final VoidCallback? onNext;

  /// 切到上一首（桌面按钮 / 移动端右滑）。
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioControllerProvider);
    // 无当前曲目：彻底不渲染，不占据底部布局空间。
    if (!state.hasTrack) return const SizedBox.shrink();
    final visible = !hidden;

    final content = deviceType == DeviceType.desktop
        ? _DesktopMiniPlayer(
            data: _CapsuleData.from(state),
            onTap: onTap,
            onTogglePlay: onTogglePlay,
            onNext: onNext,
            onPrev: onPrev,
          )
        : _SwipeableCapsule(
            data: _CapsuleData.from(state),
            onTap: onTap,
            onTogglePlay: onTogglePlay,
            onNext: onNext,
            onPrev: onPrev,
          );

    return AnimatedSlide(
      duration: AppCurves.miniPlayerMotion,
      curve: AppCurves.standard,
      offset: visible ? Offset.zero : const Offset(0, 1.5),
      child: AnimatedOpacity(
        duration: AppCurves.miniPlayerMotion,
        curve: AppCurves.standard,
        opacity: visible ? 1 : 0,
        child: content,
      ),
    );
  }
}

/// 播放条渲染数据（从 [PlaybackState] 提炼，两平台共用）。
@immutable
class _CapsuleData {
  const _CapsuleData({
    required this.isPlaying,
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.queue,
    required this.currentIndex,
    required this.hasNext,
  });

  factory _CapsuleData.from(PlaybackState state) {
    return _CapsuleData(
      isPlaying: state.isPlaying,
      title: state.currentTrack?.title ?? '',
      subtitle: state.currentTrack?.subtitle ?? '',
      coverPath: state.currentTrack?.coverPath,
      queue: state.queue,
      currentIndex: state.currentIndex,
      hasNext: state.hasNext,
    );
  }

  final bool isPlaying;
  final String title;
  final String subtitle;
  final String? coverPath;
  final List<Track> queue;
  final int currentIndex;
  final bool hasNext;

  /// 生成展示指定曲目的副本（用于滑动 peek 卡片）。
  _CapsuleData withTrack(Track track) {
    return _CapsuleData(
      isPlaying: isPlaying,
      title: track.title,
      subtitle: track.subtitle,
      coverPath: track.coverPath,
      queue: queue,
      currentIndex: currentIndex,
      hasNext: hasNext,
    );
  }

  /// 邻曲（在队列中偏移 [dir]，环绕取模）。
  Track? adjacent(int dir) {
    if (!hasNext || queue.isEmpty || currentIndex < 0) return null;
    final len = queue.length;
    return queue[(currentIndex + dir + len) % len];
  }
}

/// 封面缩略图：有本地封面则读文件，否则音符占位。
class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.coverPath,
    required this.size,
    required this.radius,
  });

  final String? coverPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _FallbackCover(size: size, radius: radius);
    final path = coverPath;
    if (path == null || path.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        CupertinoIcons.music_note,
        size: size * 0.45,
        color: Theme.of(context).colorScheme.onSecondary,
      ),
    );
  }
}

/// 播放/暂停按钮（图标 AnimatedSwitcher 动画）。
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isPlaying, required this.onPressed});

  final bool isPlaying;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: const EdgeInsets.all(6),
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: AppCurves.quickMotion,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(isPlaying),
          size: 26,
        ),
      ),
    );
  }
}

/// 下一曲按钮（移动端：直接点按切歌，左右滑动切歌不受影响）。
class _NextButton extends StatelessWidget {
  const _NextButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('mini-player-next'),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: const EdgeInsets.all(6),
      onPressed: onPressed,
      icon: const Icon(Icons.skip_next_rounded, size: 26),
    );
  }
}

// ---------------------------------------------------------------------------
// 移动端：可横滑内容切歌的水滴胶囊
// ---------------------------------------------------------------------------

/// 内容横向位移动画阶段。
enum _Phase { idle, out, slideIn, spring }

/// 移动端胶囊：玻璃胶囊本体固定不动，仅内部内容左右滑动切换上一首/下一首。
/// 拖动跟手 → 未过阈值回弹（spring）→ 过阈值内容滑出后换曲、再从对侧滑入（回弹）。
class _SwipeableCapsule extends StatefulWidget {
  const _SwipeableCapsule({
    required this.data,
    this.onTap,
    this.onTogglePlay,
    this.onNext,
    this.onPrev,
  });

  final _CapsuleData data;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  State<_SwipeableCapsule> createState() => _SwipeableCapsuleState();
}

class _SwipeableCapsuleState extends State<_SwipeableCapsule>
    with SingleTickerProviderStateMixin {
  /// 触发换歌的拖动阈值。
  static const double _slop = 56;

  /// 跟手最大位移。
  static const double _maxPull = 96;

  /// 换歌滑出距离。
  static const double _exitDistance = 220;

  static const double _coverSize = 38;

  double get _pickRadius => (_coverSize + 2 * AppTokens.spaceXs) / 2;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.miniPlayerMotion,
  );

  /// 横向偏移（跟手 / 动画实时值）。
  double _offset = 0;

  /// 手势方向：0 空闲；+1 朝下一首（左滑）；-1 朝上一首（右滑）。
  int _dir = 0;

  /// 正在播换歌动画（禁止手势打断）。
  bool _animating = false;

  _Phase _phase = _Phase.idle;
  double _phaseFrom = 0;
  double _phaseTo = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onAnim);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onAnim)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SwipeableCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部切歌（如列表点按）且非换歌动画期间 → 复位手势状态。
    if (!_animating &&
        oldWidget.data.currentIndex != widget.data.currentIndex) {
      setState(() {
        _offset = 0;
        _dir = 0;
      });
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animating) return;
    final next = (_offset + details.delta.dx).clamp(-_maxPull, _maxPull);
    setState(() {
      _offset = next;
      _dir = next < 0 ? 1 : (next > 0 ? -1 : 0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_animating) return;
    final vx = details.primaryVelocity ?? 0;
    final pastThreshold = _offset.abs() >= _slop || vx.abs() >= 800;
    if (!pastThreshold) {
      _springBack();
      return;
    }
    final toNext = vx < 0 || (vx == 0 && _offset < 0);
    _doSwap(toNext: toNext);
  }

  void _onHorizontalDragCancel() {
    // 手势被取消（如被其它手势打断）：回到原位，避免内容停留在半途。
    if (_animating) return;
    _springBack();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // 上滑快速进入完整播放页（需求 4.3）。
    final v = details.primaryVelocity ?? 0;
    if (v < -700) widget.onTap?.call();
  }

  Future<void> _springBack() async {
    if (_offset == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _offset = 0;
        _dir = 0;
      });
      return;
    }
    await _runPhase(_Phase.spring, _offset, 0);
    if (!mounted) return;
    setState(() {
      _offset = 0;
      _dir = 0;
    });
  }

  /// 换歌：先整卡滑出，再换曲、从对侧滑入（回弹）。
  Future<void> _doSwap({required bool toNext}) async {
    final action = toNext ? widget.onNext : widget.onPrev;
    if (action == null) {
      _springBack();
      return;
    }
    final dir = toNext ? 1 : -1;

    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _dir = 0;
        _animating = false;
      });
      action();
      return;
    }

    _dir = dir;
    setState(() => _animating = true);

    final from = _offset;
    final outTo = toNext ? -_exitDistance : _exitDistance;
    await _runPhase(_Phase.out, from, outTo);
    if (!mounted) return;

    action();

    // 入：新曲从对侧滑入，带回弹曲线。
    await _runPhase(_Phase.slideIn, -outTo, 0);
    if (!mounted) return;
    setState(() {
      _offset = 0;
      _dir = 0;
      _animating = false;
    });
  }

  Future<void> _runPhase(_Phase phase, double from, double to) async {
    _phase = phase;
    _phaseFrom = from;
    _phaseTo = to;
    _controller.reset();
    await _controller.forward();
  }

  void _onAnim() {
    if (!mounted) return;
    final t = _controller.value;
    final curve = switch (_phase) {
      _Phase.out => Curves.easeInCubic,
      _Phase.slideIn || _Phase.spring => Curves.easeOutBack,
      _Phase.idle => Curves.linear,
    };
    final v = _phaseFrom + (_phaseTo - _phaseFrom) * curve.transform(t);
    setState(() => _offset = v);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      // down：把越过 slop 前的位移一并作为首次 update 派发，让内容更跟手。
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) {},
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: SizedBox(
        height: AppTokens.mobileMiniPlayerHeight,
        // 玻璃胶囊本体固定不动，仅内部内容左右滑动。
        child: GlassOverlay(
          blur: 8,
          radius: AppTokens.radiusPill,
          child: ClipRRect(
            // 全胶囊圆角：圆角直径 = 条高（radiusPill 会被 RRect 自动钳制为高的一半）。
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // 后层邻曲内容 peek（手势拖动/动画中显示）。
                if (_dir != 0) _buildBehindContent(data),
                Transform.translate(
                  offset: Offset(_offset, 0),
                  child: _miniContent(data),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBehindContent(_CapsuleData data) {
    final behind = data.adjacent(_dir);
    if (behind == null) return const SizedBox.shrink();
    return Transform.translate(
      // 滞后跟手，形成层叠 peek。
      offset: Offset(_offset * 0.55, 0),
      child: Opacity(opacity: 0.85, child: _miniContent(data.withTrack(behind))),
    );
  }

  /// 胶囊内的内容（封面/歌名/控制），由外层玻璃框固定、内容横向滑动。
  Widget _miniContent(_CapsuleData data) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _pickRadius, vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CoverArt(
                coverPath: data.coverPath,
                size: _coverSize,
                radius: AppTokens.radiusM,
              ),
              const SizedBox(width: AppTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _PlayPauseButton(
                isPlaying: data.isPlaying,
                onPressed: widget.onTogglePlay,
              ),
              _NextButton(onPressed: widget.onNext),
            ],
          ),
          // 移除底部进度线，避免形成多余的“下边框”。
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端：双行胶囊（封面/歌名 + 控制）+ 滚轮切歌
// ---------------------------------------------------------------------------

class _DesktopMiniPlayer extends StatelessWidget {
  const _DesktopMiniPlayer({
    required this.data,
    this.onTap,
    this.onTogglePlay,
    this.onNext,
    this.onPrev,
  });

  final _CapsuleData data;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final dy = event.scrollDelta.dy;
        if (dy > 0) {
          onNext?.call();
        } else if (dy < 0) {
          onPrev?.call();
        }
      },
      child: GestureDetector(
        onTap: onTap,
        // 桌面端胶囊固定在 Positioned(right/bottom) 中，宽度无约束；
        // 给定固定宽度避免 stretch 纵向布局收到无限宽约束。
        child: SizedBox(
          width: 480,
          child: GlassOverlay(
            blur: 8,
            radius: AppTokens.radiusPill,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceM,
              vertical: AppTokens.spaceS,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _CoverArt(
                      coverPath: data.coverPath,
                      size: 40,
                      radius: AppTokens.radiusS,
                    ),
                    const SizedBox(width: AppTokens.spaceM),
                    // 封面/歌名靠左，占满中间剩余空间；长歌名省略号截断，
                    // 不会挤压右侧控制按钮。
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            data.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceM),
                    _DesktopControl(
                      isPlaying: data.isPlaying,
                      onTogglePlay: onTogglePlay,
                      onNext: onNext,
                      onPrev: onPrev,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopControl extends StatelessWidget {
  const _DesktopControl({
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onNext,
    required this.onPrev,
  });

  final bool isPlaying;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrev,
          tooltip: strings.miniPrevious,
          icon: const Icon(CupertinoIcons.backward_end_fill, size: 20),
        ),
        IconButton(
          onPressed: onTogglePlay,
          tooltip: strings.miniPlayPause,
          icon: AnimatedSwitcher(
            duration: AppCurves.quickMotion,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isPlaying
                  ? CupertinoIcons.pause_circle_fill
                  : CupertinoIcons.play_circle_fill,
              key: ValueKey(isPlaying),
              size: 30,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: strings.miniNext,
          icon: const Icon(CupertinoIcons.forward_end_fill, size: 20),
        ),
      ],
    );
  }
}
