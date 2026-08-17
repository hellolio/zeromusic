import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/lyrics/lyrics_line.dart';

/// 共享歌词视图：居中列表 + 当前行放大高亮（卡拉 OK 滚动），点行 seek。
///
/// 两种用途：
/// - 移动端：播放页内全屏歌词视图（歌词居中，底部切回按钮与播放页歌词按钮对齐）；
/// - 桌面端：播放页右侧歌词分栏。
///
/// 无歌词时显示「暂无歌词」+ 添加歌词按钮；有歌词时右上角提供编辑入口。
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.activeIndex,
    required this.onSeek,
    required this.strings,
    this.onSeekIndex,
    this.onAddLyrics,
    this.onEditLyrics,
  });

  final List<LyricsLine> lines;
  final int activeIndex;
  final ValueChanged<Duration> onSeek;
  final AppStrings strings;
  final ValueChanged<int>? onSeekIndex;
  final VoidCallback? onAddLyrics;
  final VoidCallback? onEditLyrics;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const double _rowHeight = 56;

  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.activeIndex != widget.activeIndex && widget.activeIndex >= 0) {
      _scrollToActive(widget.activeIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把当前行滚动到视口垂直居中。
  void _scrollToActive(int index) {
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final target = (index * _rowHeight + _rowHeight / 2 -
            _controller.position.viewportDimension / 2)
        .clamp(0.0, max);
    _controller.animateTo(
      target,
      duration: AppCurves.quickMotion,
      curve: AppCurves.standard,
    );
  }

  void _tapLine(int index) {
    final seek = widget.onSeekIndex;
    if (seek != null) {
      seek(index);
    } else {
      widget.onSeek(widget.lines[index].time);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final lines = widget.lines;
    final activeIndex = widget.activeIndex;

    if (lines.isEmpty) return _buildEmpty(strings);

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pad = (constraints.maxHeight - _rowHeight) / 2;
              return ListView.builder(
                controller: _controller,
                padding: EdgeInsets.only(
                  top: pad > 0 ? pad : 0,
                  bottom: pad > 0 ? pad : 0,
                ),
                itemCount: lines.length,
                itemBuilder: (context, i) => _buildLine(lines[i], i == activeIndex, i),
              );
            },
          ),
        ),
        if (widget.onEditLyrics != null)
          Positioned(
            top: 0,
            right: AppTokens.spaceS,
            child: IconButton(
              tooltip: strings.lyricsEdit,
              onPressed: widget.onEditLyrics,
              icon: const Icon(
                CupertinoIcons.pencil,
                size: 20,
                color: Colors.white54,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLine(LyricsLine line, bool active, int index) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey(active ? 'lyrics-active-line' : 'lyrics-line-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapLine(index),
      child: SizedBox(
        height: _rowHeight,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppCurves.quickMotion,
            curve: AppCurves.standard,
            style: TextStyle(
              fontSize: active ? 24 : 15,
              color: active ? scheme.primary : Colors.white60,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(AppStrings strings) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.doc_text,
            size: 44,
            color: Colors.white30,
          ),
          const SizedBox(height: AppTokens.spaceM),
          Text(
            strings.playerNoLyrics,
            style: const TextStyle(color: Colors.white54),
          ),
          if (widget.onAddLyrics != null) ...[
            const SizedBox(height: AppTokens.spaceL),
            FilledButton.icon(
              key: const ValueKey('lyrics-add-button'),
              onPressed: widget.onAddLyrics,
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: Text(strings.lyricsAdd),
            ),
          ],
        ],
      ),
    );
  }
}