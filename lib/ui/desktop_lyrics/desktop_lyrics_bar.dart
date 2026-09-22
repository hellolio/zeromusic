import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/anim/app_curves.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/desktop_lyrics/lyric_bar_messenger.dart';
import '../../services/preferences/preferences_controller.dart';

/// 桌面歌词条（纯渲染）：两行歌词；悬停时浮现「右上角 ✕ + 右侧播放控制条
/// （音量 / ⏮ / ⏯ / ⏭）」，移开即隐藏。行切换滑动动画。
///
/// 零业务：展示内容全部来自 [state]；✕ / 播放控制 / 拖动经回调交给宿主壳
/// （`lyric_bar_app.dart`）转发到主窗口 / 原生窗口操作。
class DesktopLyricsBar extends StatefulWidget {
  const DesktopLyricsBar({
    super.key,
    required this.state,
    required this.fontTier,
    this.onClose,
    this.onDragStart,
    this.onTogglePlay,
    this.onNext,
    this.onPrevious,
    this.onVolumeChanged,
  });

  final LyricBarStateMessage state;
  final DesktopLyricsFontSize fontTier;
  final VoidCallback? onClose;
  final VoidCallback? onDragStart;

  /// ⏯ 播放/暂停（回传主窗口 togglePlay）。
  final VoidCallback? onTogglePlay;

  /// ⏭ 下一曲（回传主窗口 next）。
  final VoidCallback? onNext;

  /// ⏮ 上一曲（回传主窗口 previous）。
  final VoidCallback? onPrevious;

  /// 音量滑杆提交（onChangeEnd 才回传，拖动中仅本地反馈）。
  final ValueChanged<double>? onVolumeChanged;

  @override
  State<DesktopLyricsBar> createState() => _DesktopLyricsBarState();
}

class _DesktopLyricsBarState extends State<DesktopLyricsBar> {
  bool _hovering = false;

  /// 音量拖动中的本地即时反馈（提交后由状态推送对齐，避免跨窗口回环闪烁）。
  double? _volumeOverride;

  @override
  void didUpdateWidget(covariant DesktopLyricsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 主窗口新状态到达（含音量变化）→ 丢弃本地覆写，回归唯一事实源。
    if (widget.state.volume != oldWidget.state.volume) {
      _volumeOverride = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // 减弱动态效果（构架 §5.6）：动画时长归零直接替换。
    final motionReduced = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);

    // ---- 占位决策（需求 §2.2）----
    // current=null → 「歌名 · 歌手」；current='' → 间奏；否则正常歌词行。
    // 第二行永远渲染（无下一句时空格占位）→ 窗口高度恒定两行（需求 §3.1）。
    final state = widget.state;
    String currentText;
    String nextText;
    var highlight = true;
    if (!state.hasTrack) {
      currentText = strings.desktopLyricsNotPlaying;
      nextText = ' ';
      highlight = false;
    } else if (state.currentText == null) {
      currentText = state.placeholderText;
      nextText = ' ';
      highlight = false;
    } else if (state.currentText!.isEmpty) {
      currentText = strings.desktopLyricsInterlude;
      nextText = ' ';
      highlight = false;
    } else {
      currentText = state.currentText!;
      final next = state.nextText;
      if (next == null) {
        nextText = ' '; // 最后一句：第二行空行占位（高度固定两行）
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

    final duration = motionReduced ? Duration.zero : AppCurves.quickMotion;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _volumeOverride = null;
      }),
      child: AnimatedContainer(
        duration: duration,
        curve: AppCurves.quick,
        decoration: BoxDecoration(
          // 悬停才浮现柔和淡底（可拖拽 + 悬停控件的暗示），平时完全透明。
          color: _hovering
              ? theme.colorScheme.surface.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceL,
          vertical: AppTokens.spaceS,
        ),
        child: Stack(
          children: [
            // ---- 歌词层：非定位子级，驱动 Stack 高度（窗口高度量测基准）。
            // 按下即进入原生窗口拖拽（startDragging 为原生模态循环）。
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => widget.onDragStart?.call(),
              child: SizedBox(
                width: double.infinity,
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
                    const SizedBox(height: AppTokens.spaceXxs),
                    _LyricSlot(
                      key: const ValueKey('next'),
                      text: nextText,
                      fontSize: nextSize,
                      highlighted: false,
                      motionReduced: motionReduced,
                    ),
                  ],
                ),
              ),
            ),
            // ---- 播放控制行：悬停时浮现于右侧（垂直居中），
            // ✕ 与播放控制钮同一行（需求 §3.3）。常驻树内
            // （透明度 0 + IgnorePointer），布局不随悬停抖动；
            // 控件间隙命中穿透到底层歌词区（仍可拖拽）。
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: AnimatedOpacity(
                key: const ValueKey('desktop_lyrics_controls_fade'),
                duration: duration,
                curve: AppCurves.quick,
                opacity: _hovering ? 1.0 : 0.0,
                child: IgnorePointer(
                  key: const ValueKey('desktop_lyrics_controls_gate'),
                  ignoring: !_hovering,
                  child: Row(
                    key: const ValueKey('desktop_lyrics_controls'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _VolumeControl(
                        key: const ValueKey('desktop_lyrics_volume'),
                        volume: (_volumeOverride ?? widget.state.volume).clamp(
                          0.0,
                          1.0,
                        ),
                        motionReduced: motionReduced,
                        onChanged: (v) => setState(() => _volumeOverride = v),
                        onChangeEnd: widget.onVolumeChanged,
                      ),
                      const SizedBox(width: AppTokens.spaceS),
                      _BarButton(
                        key: const ValueKey('desktop_lyrics_prev'),
                        icon: CupertinoIcons.backward_end_fill,
                        onPressed: widget.onPrevious,
                      ),
                      _BarButton(
                        key: const ValueKey('desktop_lyrics_play_pause'),
                        icon: state.isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        onPressed: widget.onTogglePlay,
                      ),
                      _BarButton(
                        key: const ValueKey('desktop_lyrics_next'),
                        icon: CupertinoIcons.forward_end_fill,
                        onPressed: widget.onNext,
                      ),
                      const SizedBox(width: AppTokens.spaceXs),
                      // ✕：与播放控制钮同一水平线，仅悬停时出现
                      // （透明度 0 + IgnorePointer；减弱动效由父层归零时长）。
                      AnimatedOpacity(
                        key: const ValueKey('desktop_lyrics_close_fade'),
                        duration: duration,
                        curve: AppCurves.quick,
                        opacity: _hovering ? 1.0 : 0.0,
                        child: AnimatedScale(
                          duration: duration,
                          curve: AppCurves.quick,
                          scale: _hovering ? 1.0 : 0.6,
                          child: IgnorePointer(
                            key: const ValueKey('desktop_lyrics_close_gate'),
                            ignoring: !_hovering,
                            child: _CloseButton(onClose: widget.onClose),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

/// 悬停控制条按钮（⏮ / ⏯ / ⏭）：出现/消失由父层悬停态驱动。
class _BarButton extends StatelessWidget {
  const _BarButton({super.key, required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CupertinoButton(
      padding: const EdgeInsets.all(AppTokens.spaceXs),
      onPressed: onPressed,
      minimumSize: const Size(28, 28),
      child: Icon(icon, size: 15, color: theme.colorScheme.onSurface),
    );
  }
}

/// 音量控制：静音感知图标 + 紧凑滑杆。
///
/// 拖动中 [onChanged] 仅本地反馈（父层 setState 覆写值）；
/// [onChangeEnd] 提交才回传主窗口（跨窗口通道防刷屏）。
class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    super.key,
    required this.volume,
    required this.motionReduced,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double volume;
  final bool motionReduced;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          volume <= 0
              ? CupertinoIcons.volume_mute
              : CupertinoIcons.speaker_2_fill,
          size: 14,
          color: theme.colorScheme.onSurface,
        ),
        const SizedBox(width: AppTokens.spaceXs),
        SizedBox(
          width: 64,
          height: 28,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
            ),
            child: Slider(
              key: const ValueKey('desktop_lyrics_volume_slider'),
              value: volume,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}

/// ✕ 关闭按钮：出现/消失由父层悬停态驱动，自身恒定满透明度
/// （需求 §3.3：悬停才显示关闭入口；减弱动效由父层归零时长）。
class _CloseButton extends StatelessWidget {
  const _CloseButton({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CupertinoButton(
      key: const ValueKey('desktop_lyrics_close'),
      padding: const EdgeInsets.all(AppTokens.spaceXs),
      onPressed: onClose,
      minimumSize: const Size(28, 28),
      child: Icon(
        CupertinoIcons.xmark,
        size: 14,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}
