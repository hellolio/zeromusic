import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_controller.dart';
import '../lyrics/lyrics_controller.dart';
import '../lyrics/lyrics_line.dart';
import '../preferences/preferences_controller.dart';
import 'lyric_bar_messenger.dart';
import 'lyric_window_api.dart';

/// 当前应展示在歌词条上的状态（主窗口计算）。
///
/// 依赖经过 `select` / `==` 逐层去重：行内进度推进不产生新消息，
/// 只有「行变化 / 切歌 / 曲目信息变化」才会让下游收到新值 —— 推送节流
/// 由此天然达成（对齐构架 §5.3：逐行推流 + 主窗口节流）。
final desktopLyricsStateProvider = Provider<LyricBarStateMessage>((ref) {
  final playback = ref.watch(
    audioControllerProvider.select(
      (s) => (
        hasTrack: s.hasTrack,
        title: s.currentTrack?.title ?? '',
        artist: s.currentTrack?.artist ?? '',
      ),
    ),
  );
  final lines = ref.watch(lyricsLinesProvider).value ?? const <LyricsLine>[];
  final index = ref.watch(activeLyricIndexProvider);

  /// 取第 [i] 行文本；越界返回 null（无该行）；空文本返回 ''（间奏占位）。
  String? slot(int i) {
    if (i < 0 || i >= lines.length) return null;
    final text = lines[i].text;
    return text.isEmpty ? '' : text;
  }

  return LyricBarStateMessage(
    hasTrack: playback.hasTrack,
    title: playback.title,
    artist: playback.artist,
    currentText: slot(index),
    nextText: slot(index + 1),
  );
});

/// 桌面歌词编排器：把「主窗口偏好 ↔ 歌词条窗口」双向对齐。
///
/// - 唯一事实源是主窗口偏好；state 只是开关镜像（供调试/保活）。
/// - 偏好变化（开关 / 字号 / 位置 / 主题 / 语言）→ open / close / configure。
/// - 行变化 / 切歌 → pushState（[desktopLyricsStateProvider] 已去重）。
/// - 歌词条回传（✕ / 拖动位置）→ 只写偏好，窗口同步交给下一次 build。
class DesktopLyricsController extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(preferencesProvider).value;

    // 行变化推送：仅在开关打开时生效。
    ref.listen(desktopLyricsStateProvider, (_, msg) {
      if (state) {
        ref.read(lyricWindowApiProvider).pushState(msg);
      }
    });

    // 歌词条回传事件：只写偏好，其余交给响应式重建。
    final sub = ref.read(lyricWindowApiProvider).events.listen((event) {
      final prefsNotifier = ref.read(preferencesProvider.notifier);
      switch (event) {
        case LyricBarClosedEvent():
          unawaited(prefsNotifier.setDesktopLyricsEnabled(false));
        case LyricBarPositionSavedEvent(:final position):
          unawaited(prefsNotifier.setDesktopLyricsOffset(position));
      }
    });
    ref.onDispose(sub.cancel);

    if (prefs != null) {
      unawaited(_syncWindow(prefs));
    }
    return prefs?.desktopLyricsEnabled ?? false;
  }

  /// 对齐窗口与偏好；窗口复用（open/close/configure 均幂等）。
  Future<void> _syncWindow(AppPreferences prefs) async {
    if (!ref.mounted) return;
    final api = ref.read(lyricWindowApiProvider);
    if (!prefs.desktopLyricsEnabled) {
      await api.close();
      return;
    }
    final config = _buildConfig(prefs);
    if (!ref.mounted) return;
    if (api.isOpen) {
      await api.configure(config);
    } else {
      await api.open(config);
    }
  }

  LyricWindowConfig _buildConfig(AppPreferences prefs) {
    final dark = switch (prefs.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    };
    return LyricWindowConfig(
      // 空字符串 = 跟随系统（歌词条引擎自行解析平台 locale）。
      localeCode: prefs.locale?.languageCode ?? '',
      dark: dark,
      fontTier: prefs.desktopLyricsFontSize,
      offset: prefs.desktopLyricsOffset,
      initialState: ref.read(desktopLyricsStateProvider),
    );
  }
}

final desktopLyricsControllerProvider =
    NotifierProvider<DesktopLyricsController, bool>(
      DesktopLyricsController.new,
    );
