import 'dart:io' show File;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/database/app_database.dart';
import '../pages/playlist/playlist_data.dart';

/// 歌曲行：封面占位、歌名/歌手/时长、收藏红心、播放高亮+均衡动画、⋯菜单。
/// 交互：点按播放；长按（移动）/鼠标右键（桌面）/「⋯」弹出上下文菜单；
/// 桌面端悬停高亮。批量编辑模式下显示左侧选择圈，点按切换选中。
class SongTile extends StatefulWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
    this.onMore,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;

  /// 弹出歌曲菜单，anchor 为桌面端菜单定位点；批量编辑模式下为 null。
  final void Function(Offset anchor)? onMore;

  /// 是否处于批量编辑模式（显示选择圈、隐藏行内菜单）。
  final bool selecting;

  /// 批量编辑模式下是否已选中。
  final bool selected;

  /// 批量编辑模式下点按回调（切换选中）。
  final VoidCallback? onSelect;

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _hovered = false;

  void _openMoreAt(Offset position) => widget.onMore?.call(position);

  void _openMore() {
    final box = context.findRenderObject();
    final center = box is RenderBox ? box.localToGlobal(box.size.center(Offset.zero)) : Offset.zero;
    _openMoreAt(center);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.song;
    final selecting = widget.selecting;
    final selected = widget.selected;
    final subtitle = [
      song.artist ?? '',
      formatDurationMs(song.durationMs),
    ].where((s) => s.isNotEmpty).join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selecting ? widget.onSelect : widget.onTap,
        onLongPress: selecting ? null : _openMore,
        onSecondaryTapDown: selecting
            ? null
            : (d) => _openMoreAt(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : _hovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM, vertical: AppTokens.spaceS),
          child: Row(
            children: [
              if (selecting) ...[
                _SelectMark(selected: selected),
                const SizedBox(width: AppTokens.spaceM),
              ],
              _CoverArt(song: song),
              const SizedBox(width: AppTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: widget.isPlaying
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                        if (song.isFavorite) ...[
                          const SizedBox(width: AppTokens.spaceS),
                          _FavoriteHeart(),
                        ],
                        if (widget.isPlaying) ...[
                          const SizedBox(width: AppTokens.spaceS),
                          const _Equalizer(isPlaying: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSecondary),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  onPressed: _openMore,
                  icon: Icon(
                    CupertinoIcons.ellipsis,
                    size: 20,
                    color: theme.colorScheme.onSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 批量编辑模式下的左侧选择标记：选中=实心勾圈，未选中=空圈。
class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(
      selected
          ? CupertinoIcons.checkmark_circle_fill
          : CupertinoIcons.circle,
      size: 22,
      color: selected ? theme.colorScheme.primary : theme.colorScheme.onSecondary,
    );
  }
}

/// 封面占位：按歌曲稳定取色的一组渐变 + 音符图标。
class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.song});

  final Song song;

  static const _palette = [
    [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
    [Color(0xFFFF6482), Color(0xFFBF5AF2)],
    [Color(0xFF30D158), Color(0xFF64D2FF)],
    [Color(0xFFFF9F0A), Color(0xFFFF375F)],
    [Color(0xFF32ADE6), Color(0xFF5E5CE6)],
  ];

  @override
  Widget build(BuildContext context) {
    final coverPath = song.coverPath;
    if (coverPath != null && coverPath.isNotEmpty) {
      return Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
        child: Image.file(
          File(coverPath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _gradientFallback(context),
        ),
      );
    }
    return _gradientFallback(context);
  }

  Widget _gradientFallback(BuildContext context) {
    final colors = _palette[song.id % _palette.length];
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      child: const Icon(CupertinoIcons.music_note, color: Colors.white, size: 22),
    );
  }
}

/// 收藏红心：红心弹跳入场（AnimatedScale）。
class _FavoriteHeart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: Icon(
        CupertinoIcons.heart_fill,
        size: 13,
        color: AppTokens.favorite,
      ),
    );
  }
}

/// 均衡波形象征动画：播放中三根小柱上下跳动；减弱动效时静止显示。
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.isPlaying});

  final bool isPlaying;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(_Equalizer old) {
    super.didUpdateWidget(old);
    final animated = !MediaQuery.disableAnimationsOf(context);
    if (widget.isPlaying && animated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPlaying && !MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat();
    }
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _bar(color, 0.3 + 0.7 * _phase(0.0)),
              _bar(color, 0.3 + 0.7 * _phase(0.5)),
              _bar(color, 0.3 + 0.7 * _phase(0.9)),
            ],
          );
        },
      ),
    );
  }

  double _phase(double offset) {
    if (!widget.isPlaying) return 0.5;
    final t = (_controller.value + offset) % 1.0;
    return (1 - (2 * t - 1).abs());
  }

  Widget _bar(Color color, double heightFactor) {
    return Container(
      width: 3,
      height: 12 * (0.25 + 0.75 * heightFactor),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}