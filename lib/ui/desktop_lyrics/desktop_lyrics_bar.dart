import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/desktop_lyrics/lyric_bar_messenger.dart';
import '../../services/preferences/preferences_controller.dart';

/// 桌面歌词条（纯渲染）：两行歌词 + ✕ 关闭，悬停淡底，行切换滑动动画。
///
/// 零业务：展示内容全部来自 [state]；✕ / 拖动经回调交给宿主壳
/// （`lyric_bar_app.dart`）转发到主窗口 / 原生窗口操作。
class DesktopLyricsBar extends StatefulWidget {
  const DesktopLyricsBar({
    super.key,
    required this.state,
    required this.fontTier,
    this.onClose,
    this.onDragStart,
  });

  final LyricBarStateMessage state;
  final DesktopLyricsFontSize fontTier;
  final VoidCallback? onClose;
  final VoidCallback? onDragStart;

  @override
  State<DesktopLyricsBar> createState() => _DesktopLyricsBarState();
}

class _DesktopLyricsBarState extends State<DesktopLyricsBar> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // 减弱动态效果（构架 §5.6）：动画时长归零直接替换。
    final motionReduced = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);

    // ---- 占位决策（需求 §2.2）----
    // current=null → 「歌名 · 歌手」；current='' → 间奏；否则正常歌词行。
    final state = widget.state;
    String currentText;
    String? nextText;
    var highlight = true;
    if (!state.hasTrack) {
      currentText = strings.desktopLyricsNotPlaying;
      highlight = false;
    } else if (state.currentText == null) {
      currentText = state.placeholderText;
      highlight = false;
    } else if (state.currentText!.isEmpty) {
      currentText = strings.desktopLyricsInterlude;
      highlight = false;
    } else {
      currentText = state.currentText!;
      final next = state.nextText;
      if (next == null) {
        nextText = null; // 最后一句：第二行不渲染
      } else if (next.isEmpty) {
        nextText = strings.desktopLyricsInterlude;
      } else {
        nextText = next;
      }
    }

    final (currentSize, nextSize) = switch (widget.fontTier) {
      DesktopLyricsFontSize.small => (17.0, 12.0),
      DesktopLyricsFontSize.medium => (20.0, 13.0),
      DesktopLyricsFontSize.large => (24.0, 15.0),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: motionReduced ? Duration.zero : AppCurves.quickMotion,
        curve: AppCurves.quick,
        decoration: BoxDecoration(
          // 悬停极淡底色：提示可拖拽，平时完全透明（需求 §3.3）。
          color: _hovering
              ? theme.colorScheme.surface.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceL,
          vertical: AppTokens.spaceS,
        ),
        child: Row(
          children: [
            Expanded(
              // 按下歌词区即进入原生窗口拖拽（startDragging 为原生模态循环，
              // 不依赖 Flutter 手势键位，三端行为一致）。
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => widget.onDragStart?.call(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LyricSlot(
                      key: const ValueKey('current'),
                      text: currentText,
                      fontSize: currentSize,
                      highlighted: highlight,
                      motionReduced: motionReduced,
                    ),
                    if (nextText != null) ...[
                      const SizedBox(height: AppTokens.spaceXxs),
                      _LyricSlot(
                        key: const ValueKey('next'),
                        text: nextText,
                        fontSize: nextSize,
                        highlighted: false,
                        motionReduced: motionReduced,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceS),
            _CloseButton(
              motionReduced: motionReduced,
              tooltip: strings.desktopLyricsClose,
              onClose: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单行歌词：行切换 = 旧句上滑淡出 + 新句自上下滑入（需求 §2.4）。
///
/// AnimatedSwitcher 对「出句」复用其入场 transition 反向播放；
/// 选用对称的 `begin: 上方 → end: 原位` Tween，恰好同时满足
/// 「新句下滑入（t:0→1 自上而下）」与「旧句上滑淡出（t:1→0 回到上方）」。
class _LyricSlot extends StatelessWidget {
  const _LyricSlot({
    super.key,
    required this.text,
    required this.fontSize,
    required this.highlighted,
    required this.motionReduced,
  });

  final String text;
  final double fontSize;
  final bool highlighted;
  final bool motionReduced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.25,
      fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
      color: highlighted
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
      // 投影保证任意壁纸上可读（需求 §2.1）。
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    );
    return AnimatedSwitcher(
      duration: motionReduced ? Duration.zero : AppCurves.standardMotion,
      switchInCurve: AppCurves.standard,
      switchOutCurve: AppCurves.standard,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, ?currentChild],
      ),
      child: Text(
        text,
        key: ValueKey(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// ✕ 关闭按钮：平时低透明度常显，悬停透明度提升 + 轻微放大
/// （≤200ms，需求 §3.3 / 构架 §5；减弱动效直接替换）。
class _CloseButton extends StatefulWidget {
  const _CloseButton({
    required this.motionReduced,
    required this.tooltip,
    this.onClose,
  });

  final bool motionReduced;
  final String tooltip;
  final VoidCallback? onClose;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = widget.motionReduced ? Duration.zero : AppCurves.quickMotion;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedScale(
          duration: duration,
          curve: AppCurves.quick,
          scale: _hovering ? 1.15 : 1.0,
          child: AnimatedOpacity(
            duration: duration,
            curve: AppCurves.quick,
            // 平时低透明度常显（可见性与可测性），悬停变亮。
            opacity: _hovering ? 1.0 : 0.55,
            child: CupertinoButton(
              key: const ValueKey('desktop_lyrics_close'),
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              onPressed: widget.onClose,
              minimumSize: Size(28, 28),
              child: Icon(
                CupertinoIcons.xmark,
                size: 14,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
