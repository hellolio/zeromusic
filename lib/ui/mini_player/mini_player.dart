import 'dart:io' show File;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/anim/app_curves.dart';
import '../../core/platform/device_type.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/audio/audio_controller.dart';
import '../../services/audio/track.dart';
import '../../services/preferences/preferences_controller.dart';
import '../components/glass_overlay.dart';
import '../components/volume_popover.dart';
import 'mini_player_bounce.dart';

/// 全局迷你播放条「水滴胶囊」。
/// 移动端：悬于底栏上方、内容底部；桌面端：内容右下角悬浮。
///
/// 可见性规则：
/// - 媒体库为空（无当前曲目）时不渲染、不占布局空间；
/// - 进入完整播放页时由全屏播放页覆盖（路由透明，收起动画时露出并回弹）；
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

  /// 是否显式隐藏（供骨架层按需隐藏；播放页路由透明时无需设置，直接覆盖即可）。
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
    // 播放页收起等场景触发迷你条 spring 回弹；点击进入播放页时触发轻微按压。
    final bounceTick = ref.watch(miniPlayerBounceProvider);
    final pressTick = ref.watch(miniPlayerPressProvider);

    // 桌面歌词开关状态（仅桌面胶囊展示；写偏好后由
    // DesktopLyricsController 响应式开合歌词条窗口）。
    final desktopLyricsEnabled = ref.watch(
      preferencesProvider.select((p) => p.value?.desktopLyricsEnabled ?? false),
    );

    final content = deviceType == DeviceType.desktop
        ? _DesktopMiniPlayer(
            data: _CapsuleData.from(state),
            bounceTick: bounceTick,
            pressTick: pressTick,
            onTap: onTap,
            onTogglePlay: onTogglePlay,
            onNext: onNext,
            onPrev: onPrev,
            desktopLyricsEnabled: desktopLyricsEnabled,
            onToggleDesktopLyrics: () => ref
                .read(preferencesProvider.notifier)
                .setDesktopLyricsEnabled(!desktopLyricsEnabled),
          )
        : _SwipeableCapsule(
            data: _CapsuleData.from(state),
            bounceTick: bounceTick,
            pressTick: pressTick,
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
enum _Phase { idle, out, spring }

/// 移动端胶囊：玻璃胶囊本体固定不动，仅**歌名·歌手**文本左右滑动切换上一首/下一首；
/// 封面、播放/暂停、下一曲按钮固定不动。拖动跟手（轮播式：当前文本滑出的同时，
/// 邻曲文本从滑动方向对侧以**同速 1:1** 滑入）→ 未过阈值回弹（spring）→
/// 过阈值后当前文本滑出、邻曲文本归位，随即切歌复位。
///
/// 动画为「controller + 状态监听」驱动（无 `await forward()`），阶段完成后必然
/// 复位 `_offset/_dir/_animating`，新手势可随时打断接管，不会残留卡死。
class _SwipeableCapsule extends StatefulWidget {
  const _SwipeableCapsule({
    required this.data,
    this.onTap,
    this.onTogglePlay,
    this.onNext,
    this.onPrev,
    this.bounceTick = 0,
    this.pressTick = 0,
  });

  final _CapsuleData data;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  /// 迷你条回弹信号：变化时 [Rebound] 播放一次 spring 回弹。
  final int bounceTick;

  /// 迷你条按压信号：变化时 [Rebound] 播放一次轻微按压反馈。
  final int pressTick;

  @override
  State<_SwipeableCapsule> createState() => _SwipeableCapsuleState();
}

class _SwipeableCapsuleState extends State<_SwipeableCapsule>
    with SingleTickerProviderStateMixin {
  /// 触发换歌的拖动阈值。
  static const double _slop = 56;

  /// 文本区宽度未测得时的回退滑出距离（首帧布局前不会发生手势）。
  static const double _fallbackSlideWidth = 240;

  static const double _coverSize = 38;

  double get _pickRadius => (_coverSize + 2 * AppTokens.spaceXs) / 2;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCurves.miniPlayerMotion,
  );

  /// 文本横向偏移（跟手 / 动画实时值）。
  double _offset = 0;

  /// 文本区宽度（LayoutBuilder 实测）：拖动上限与滑出距离（邻曲文本
  /// 摆在当前文本旁一格宽度处，两块同速 1:1 滑动）。
  double _trackWidth = 0;

  double get _slideWidth => _trackWidth > 0 ? _trackWidth : _fallbackSlideWidth;

  /// 手势方向：0 空闲；+1 朝下一首（左滑）；-1 朝上一首（右滑）。
  int _dir = 0;

  /// 是否正处于换歌动画（动画中忽略新拖动，但可被新按下接管）。
  bool _animating = false;

  _Phase _phase = _Phase.idle;
  double _phaseFrom = 0;
  double _phaseTo = 0;
  VoidCallback? _phaseDone;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onAnim);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onAnim)
      ..removeStatusListener(_onStatus)
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

  void _onHorizontalDragStart(DragStartDetails details) {
    // 动画进行中：停住并从当前偏移接管，杜绝残留卡死。
    if (_animating) {
      _controller.stop();
      _animating = false;
      _phaseDone = null;
      _phase = _Phase.idle;
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animating) return;
    final next = (_offset + details.delta.dx).clamp(
      -_slideWidth,
      _slideWidth,
    );
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

  // ---- 动画：相位机（无 await，杜绝卡死/残留） ----

  /// 启动一个相位动画；完成时执行 [onDone]（用于链式推进下一相位）。
  void _runPhase(_Phase phase, double from, double to, {VoidCallback? onDone}) {
    _phase = phase;
    _phaseFrom = from;
    _phaseTo = to;
    _phaseDone = onDone;
    _animating = true;
    _controller
      ..duration = _durationOf(phase)
      ..stop()
      ..value = 0
      ..forward();
  }

  static Duration _durationOf(_Phase p) => switch (p) {
    _Phase.out => const Duration(milliseconds: 260),
    _Phase.spring => AppCurves.miniPlayerMotion,
    _Phase.idle => Duration.zero,
  };

  static Curve _curveOf(_Phase p) => switch (p) {
    // easeOutCubic：无过冲（过冲会让邻曲文本冲过中点再晃回来）。
    _Phase.out => Curves.easeOutCubic,
    _Phase.spring => Curves.easeOutBack,
    _Phase.idle => Curves.linear,
  };

  void _onAnim() {
    if (!mounted || _phase == _Phase.idle) return;
    final t = _controller.value;
    final v =
        _phaseFrom + (_phaseTo - _phaseFrom) * _curveOf(_phase).transform(t);
    setState(() => _offset = v);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final done = _phaseDone;
    _phaseDone = null;
    done?.call();
  }

  void _springBack() {
    if (_offset == 0) {
      _dir = 0;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _offset = 0;
        _dir = 0;
      });
      return;
    }
    _runPhase(
      _Phase.spring,
      _offset,
      0,
      onDone: () {
        setState(() {
          _offset = 0;
          _dir = 0;
          _animating = false;
        });
      },
    );
  }

  /// 换歌：当前文本滑向对侧一格宽度（邻曲文本同步归位），完成后切歌复位。
  /// 滑出与滑入同一相位：两块文本同速 1:1，无先后、无重影。
  void _doSwap({required bool toNext}) {
    final action = toNext ? widget.onNext : widget.onPrev;
    if (action == null) {
      _springBack();
      return;
    }
    final dir = toNext ? 1 : -1;

    if (MediaQuery.disableAnimationsOf(context)) {
      action();
      setState(() {
        _offset = 0;
        _dir = 0;
        _animating = false;
      });
      return;
    }

    setState(() => _dir = dir);
    _runPhase(
      _Phase.out,
      _offset,
      -dir * _slideWidth,
      onDone: () {
        // 邻曲文本已归位（视觉即新曲在中央）：切歌并复位。
        action();
        setState(() {
          _offset = 0;
          _dir = 0;
          _animating = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      // down：把越过 slop 前的位移一并作为首次 update 派发，让内容更跟手。
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: SizedBox(
        height: AppTokens.mobileMiniPlayerHeight,
        // 玻璃胶囊本体固定不动，仅中间文本滑动。
        child: _Rebound(
          bounceTick: widget.bounceTick,
          pressTick: widget.pressTick,
          child: GlassOverlay(
            radius: AppTokens.radiusPill,
            // 雾基色分模式（同底栏）：浅色更白、深色更黑，提升文字对比。
            fogColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
            child: ClipRRect(
              // 全胶囊圆角：圆角直径 = 条高（radiusPill 会被 RRect 自动钳制为高的一半）。
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              child: _miniContent(data),
            ),
          ),
        ),
      ),
    );
  }

  /// 胶囊内的内容：封面、播放/暂停、下一曲固定；中间歌名·歌手文本横向滑动，
  /// 拖动/换歌时邻曲文本从滑动方向对侧同速 1:1 滑入（轮播式）。
  Widget _miniContent(_CapsuleData data) {
    return Padding(
      // 高度收紧后内容自然高（两行文本 48）已贴近条高，纵向不再额外留白；
      // 内容靠 Column 的垂直居中摆放。
      padding: EdgeInsets.symmetric(horizontal: _pickRadius),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 实测文本区宽度：邻曲文本间距与拖动上限都以此为一步。
                    _trackWidth = constraints.maxWidth;
                    return ClipRect(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          if (_dir != 0) _buildAdjacentText(data),
                          Transform.translate(
                            offset: Offset(_offset, 0),
                            child: _textBlock(data),
                          ),
                        ],
                      ),
                    );
                  },
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

  /// 邻曲文本（轮播式 1:1 跟手）：摆在当前文本旁一格文本区宽度处，
  /// 与当前文本同速滑动——右滑上一曲从左侧滑入，左滑下一曲从右侧滑入；
  /// 不透明度与当前文本一致，无滞后、无重影。
  Widget _buildAdjacentText(_CapsuleData data) {
    final adjacent = data.adjacent(_dir);
    if (adjacent == null) return const SizedBox.shrink();
    return Transform.translate(
      offset: Offset(_offset + _dir * _slideWidth, 0),
      child: _textBlock(data.withTrack(adjacent)),
    );
  }

  /// 歌名 · 歌手（滑动的部分）。
  Widget _textBlock(_CapsuleData data) {
    return Column(
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
              ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 桌面端：双行胶囊（封面/歌名 + 控制）+ 滚轮切歌
// ---------------------------------------------------------------------------

/// 迷你条交互反馈包裹：`bounceTick` 变化播放**回弹**（0.7→1.0 带过冲，收起时），
/// `pressTick` 变化播放**按压**（1→0.9→1 短促，点按进入播放页时）。
class _Rebound extends StatefulWidget {
  const _Rebound({
    required this.bounceTick,
    required this.pressTick,
    required this.child,
  });

  final int bounceTick;
  final int pressTick;
  final Widget child;

  @override
  State<_Rebound> createState() => _ReboundState();
}

class _ReboundState extends State<_Rebound> with TickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    // 与收起动画（300ms，下滑 1/3 后回弹 200ms）的露出阶段对齐，让回弹在
    // 迷你条可见期间完整播放，收完时正好结束。
    duration: const Duration(milliseconds: 200),
  );

  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  @override
  void initState() {
    super.initState();
    // 静止态 = 完整大小（1.0）。回弹播放时 forward(from: 0) 从 0.7 长回 1.0，
    // 否则迷你条在首次回弹前会一直以 0.7 倍渲染（看起来偏小）。
    _bounce.value = 1.0;
  }

  @override
  void didUpdateWidget(_Rebound oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bounceTick != widget.bounceTick &&
        !MediaQuery.disableAnimationsOf(context)) {
      _bounce.forward(from: 0);
    }
    if (oldWidget.pressTick != widget.pressTick &&
        !MediaQuery.disableAnimationsOf(context)) {
      _press.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: 0.7,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOutBack)),
      child: ScaleTransition(
        // 按压：先快速压下到 0.9，再弹回 1.0（轻交互，不做大回弹）。
        scale: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 40),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 60),
        ]).animate(_press),
        child: widget.child,
      ),
    );
  }
}

class _DesktopMiniPlayer extends StatelessWidget {
  const _DesktopMiniPlayer({
    required this.data,
    this.onTap,
    this.onTogglePlay,
    this.onNext,
    this.onPrev,
    this.desktopLyricsEnabled = false,
    this.onToggleDesktopLyrics,
    this.bounceTick = 0,
    this.pressTick = 0,
  });

  final _CapsuleData data;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  /// 桌面歌词开关当前态（仅展示 + 高亮；切换由 [onToggleDesktopLyrics] 完成）。
  final bool desktopLyricsEnabled;
  final VoidCallback? onToggleDesktopLyrics;

  /// 迷你条回弹信号：变化时 [_Rebound] 播放一次 spring 回弹。
  final int bounceTick;

  /// 迷你条按压信号：变化时 [_Rebound] 播放一次轻微按压反馈。
  final int pressTick;

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
        // opaque：胶囊内控件间隙（文字与按钮之间）也是点击热区，
        // 否则中心点落在间隙时点按无法进入播放页。
        behavior: HitTestBehavior.opaque,
        // 桌面端胶囊固定在 Positioned(right/bottom) 中，宽度无约束；
        // 给定固定宽度避免 stretch 纵向布局收到无限宽约束。
        // 宽度 440：控制区五个 40×40 按钮（含歌词开关/音量）之外，
        // 仍保留歌名可读宽度（长名省略号截断）。
        child: SizedBox(
          width: 440,
          child: _Rebound(
            bounceTick: bounceTick,
            pressTick: pressTick,
            child: GlassOverlay(
              radius: AppTokens.radiusPill,
              // 雾基色分模式（同底栏/移动迷你条）：浅色更白、深色更黑。
              fogColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceM,
                vertical: AppTokens.spaceXxs,
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
                        desktopLyricsEnabled: desktopLyricsEnabled,
                        onToggleDesktopLyrics: onToggleDesktopLyrics,
                      ),
                    ],
                  ),
                ],
              ),
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
    required this.desktopLyricsEnabled,
    required this.onToggleDesktopLyrics,
  });

  final bool isPlaying;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  /// 桌面歌词开关当前态（开启时图标主色高亮）。
  final bool desktopLyricsEnabled;
  final VoidCallback? onToggleDesktopLyrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 桌面歌词开关（与播放页歌词按钮同图标 doc_text；开时主色高亮）。
        IconButton(
          key: const ValueKey('mini-player-desktop-lyrics'),
          onPressed: onToggleDesktopLyrics,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: const EdgeInsets.all(6),
          icon: Icon(
            CupertinoIcons.doc_text,
            size: 20,
            color: desktopLyricsEnabled ? theme.colorScheme.primary : null,
          ),
        ),
        // 音量：点击在按钮上方弹出竖向滑杆小窗（与播放页同组件/同数据源）。
        const _MiniVolumeButton(),
        IconButton(
          onPressed: onPrev,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: const EdgeInsets.all(6),
          icon: const Icon(CupertinoIcons.backward_end_fill, size: 20),
        ),
        IconButton(
          onPressed: onTogglePlay,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: const EdgeInsets.all(6),
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
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: const EdgeInsets.all(6),
          icon: const Icon(CupertinoIcons.forward_end_fill, size: 20),
        ),
      ],
    );
  }
}

/// 迷你条音量按钮：静音感知图标（与播放页一致），
/// 点击弹出竖向滑杆小窗；音量值读写偏好 defaultVolume（单数据源）。
class _MiniVolumeButton extends ConsumerStatefulWidget {
  const _MiniVolumeButton();

  @override
  ConsumerState<_MiniVolumeButton> createState() => _MiniVolumeButtonState();
}

class _MiniVolumeButtonState extends ConsumerState<_MiniVolumeButton> {
  /// 弹窗定位锚点（挂在定宽包裹上，与播放页同模式）。
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(
      preferencesProvider.select((p) => p.value?.defaultVolume ?? 1.0),
    );
    return SizedBox(
      key: _anchorKey,
      width: 40,
      child: IconButton(
        key: const ValueKey('mini-player-volume'),
        onPressed: () => showVolumePopover(context, _anchorKey),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: const EdgeInsets.all(6),
        icon: Icon(
          volume <= 0
              ? CupertinoIcons.volume_mute
              : CupertinoIcons.speaker_2_fill,
          size: 20,
        ),
      ),
    );
  }
}
