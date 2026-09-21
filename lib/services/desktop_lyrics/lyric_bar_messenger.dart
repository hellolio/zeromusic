import 'dart:convert';

import 'package:flutter/animation.dart' show Offset;
import 'package:flutter/foundation.dart';

import '../preferences/preferences_controller.dart' show DesktopLyricsFontSize;

/// 跨窗口通道名（主窗口 ↔ 歌词条窗口）。
///
/// - [kLyricBarPushChannel]：主窗口 → 歌词条（单向，歌词条注册 handler）。
/// - [kLyricBarBackChannel]：歌词条 → 主窗口（单向，主窗口注册 handler）。
/// - [kLyricBarNativeChannel]：歌词条 → 平台原生（macOS orderFront 等）。
abstract final class LyricBarChannels {
  static const push = 'zeromusic/lyric_bar/push';
  static const back = 'zeromusic/lyric_bar/back';
  static const native = 'zeromusic/lyric_window';
}

/// desktop_multi_window 子窗口入口约定：dartEntrypointArguments 首位。
const String kMultiWindowEntryArg = 'multi_window';

/// 主窗口 → 歌词条：当前展示状态（唯一推送内容，节流在主窗口侧完成）。
///
/// - [currentText] 为 null：无歌词 / 尚未到第一行 → 显示「歌名 · 歌手」占位。
/// - [currentText] 为空字符串：纯音乐间奏 → 显示「♪ 间奏 ♪」占位。
/// - [nextText] 为 null：无下一句（最后一句 / 无歌词）→ 第二行不渲染。
@immutable
class LyricBarStateMessage {
  const LyricBarStateMessage({
    required this.hasTrack,
    this.title = '',
    this.artist = '',
    this.currentText,
    this.nextText,
  });

  /// 当前是否有曲目；false → 显示「未在播放」占位。
  final bool hasTrack;
  final String title;
  final String artist;
  final String? currentText;
  final String? nextText;

  /// 无歌词 / 未到首行时由歌词条渲染的占位正文。
  String get placeholderText => '$title · $artist';

  Map<String, Object?> toJson() => {
    'hasTrack': hasTrack,
    'title': title,
    'artist': artist,
    'current': currentText,
    'next': nextText,
  };

  factory LyricBarStateMessage.fromJson(Map<Object?, Object?> json) {
    return LyricBarStateMessage(
      hasTrack: json['hasTrack'] == true,
      title: json['title'] is String ? json['title'] as String : '',
      artist: json['artist'] is String ? json['artist'] as String : '',
      currentText: json['current'] is String ? json['current'] as String : null,
      nextText: json['next'] is String ? json['next'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricBarStateMessage &&
      other.hasTrack == hasTrack &&
      other.title == title &&
      other.artist == artist &&
      other.currentText == currentText &&
      other.nextText == nextText;

  @override
  int get hashCode =>
      Object.hash(hasTrack, title, artist, currentText, nextText);

  @override
  String toString() =>
      'LyricBarStateMessage(hasTrack: $hasTrack, title: $title, '
      'artist: $artist, current: $currentText, next: $nextText)';
}

/// 歌词条 → 主窗口的回传事件。
@immutable
sealed class LyricBarHostEvent {
  const LyricBarHostEvent();
}

/// 歌词条内 ✕ 被点击：主窗口应把开关置为关并持久化。
class LyricBarClosedEvent extends LyricBarHostEvent {
  const LyricBarClosedEvent();
}

/// 歌词条子窗口引擎就绪（push handler 已注册）：
/// 主窗口收到后才下发 show（修「hiddenAtLaunch 创建后无人 show」的首次不显示），
/// 并立即推送当前状态（修冷启动窗口期行推送被丢弃）。
class LyricBarReadyEvent extends LyricBarHostEvent {
  const LyricBarReadyEvent();
}

/// 拖动结束：主窗口应把新位置存入偏好（写回只发生在主窗口）。
class LyricBarPositionSavedEvent extends LyricBarHostEvent {
  const LyricBarPositionSavedEvent(this.position);

  final Offset position;
}

/// 编解码：通道上的 method/arguments ↔ 强类型消息。
abstract final class LyricBarMessenger {
  /// 编码推送消息（push 通道 method='state'）。
  static Map<String, Object?> encodeState(LyricBarStateMessage state) =>
      state.toJson();

  /// 解码推送消息；格式不符时回退「未在播放」。
  static LyricBarStateMessage decodeState(Object? arguments) {
    if (arguments is Map<Object?, Object?>) {
      return LyricBarStateMessage.fromJson(arguments);
    }
    return const LyricBarStateMessage(hasTrack: false);
  }

  /// 编码 ✕ 事件（back 通道 method='closed'）。
  static const String closedMethod = 'closed';

  /// 编码引擎就绪事件（back 通道 method='ready'，无参数）。
  static const String readyMethod = 'ready';

  /// 编码位置回传（back 通道 method='position'）。
  static Map<String, Object?> encodePosition(Offset position) => {
    'x': position.dx,
    'y': position.dy,
  };

  /// 解码 back 通道调用；无法识别返回 null。
  static LyricBarHostEvent? decodeHostEvent(String method, Object? arguments) {
    switch (method) {
      case closedMethod:
        return const LyricBarClosedEvent();
      case readyMethod:
        return const LyricBarReadyEvent();
      case positionMethod:
        if (arguments is Map<Object?, Object?> &&
            arguments['x'] is num &&
            arguments['y'] is num) {
          return LyricBarPositionSavedEvent(
            Offset(
              (arguments['x'] as num).toDouble(),
              (arguments['y'] as num).toDouble(),
            ),
          );
        }
        return null;
      default:
        return null;
    }
  }

  static const String positionMethod = 'position';

  /// 编码窗口配置（创建窗口时随参数携带，含初始状态，避免首帧占位闪变）。
  static String encodeConfig(LyricWindowConfig config) =>
      jsonEncode(config.toJson());

  /// 解码窗口配置；损坏输入回退默认配置。
  static LyricWindowConfig decodeConfig(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<Object?, Object?>) {
        return LyricWindowConfig.fromJson(decoded);
      }
    } catch (_) {
      // fallthrough
    }
    return const LyricWindowConfig();
  }
}

/// 歌词条窗口的显示配置：随创建参数传入子窗口。
@immutable
class LyricWindowConfig {
  const LyricWindowConfig({
    this.localeCode = 'zh',
    this.dark = false,
    this.fontTier = DesktopLyricsFontSize.medium,
    this.offset,
    this.initialState = const LyricBarStateMessage(hasTrack: false),
  });

  /// 界面语言（languageCode）。
  final String localeCode;

  /// 深色模式（歌词条窗口独立于主窗口主题，需显式携带）。
  final bool dark;

  /// 字号档位（决定窗口尺寸与字号）。
  final DesktopLyricsFontSize fontTier;

  /// 恢复位置；null = 默认底部居中偏下。
  final Offset? offset;

  /// 创建时刻的展示状态（首帧直接可用）。
  final LyricBarStateMessage initialState;

  Map<String, Object?> toJson() => {
    'locale': localeCode,
    'dark': dark,
    'fontTier': fontTier.name,
    'offset': offset == null ? null : [offset!.dx, offset!.dy],
    'initialState': initialState.toJson(),
  };

  factory LyricWindowConfig.fromJson(Map<Object?, Object?> json) {
    final offsetRaw = json['offset'];
    Offset? offset;
    if (offsetRaw is List && offsetRaw.length == 2) {
      offset = Offset(
        (offsetRaw[0] as num).toDouble(),
        (offsetRaw[1] as num).toDouble(),
      );
    }
    return LyricWindowConfig(
      localeCode: json['locale'] is String ? json['locale'] as String : 'zh',
      dark: json['dark'] == true,
      fontTier: DesktopLyricsFontSize.values.firstWhere(
        (tier) => tier.name == json['fontTier'],
        orElse: () => DesktopLyricsFontSize.medium,
      ),
      offset: offset,
      initialState: json['initialState'] is Map<Object?, Object?>
          ? LyricBarStateMessage.fromJson(
              json['initialState'] as Map<Object?, Object?>,
            )
          : const LyricBarStateMessage(hasTrack: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricWindowConfig &&
      other.localeCode == localeCode &&
      other.dark == dark &&
      other.fontTier == fontTier &&
      other.offset == offset &&
      other.initialState == initialState;

  @override
  int get hashCode =>
      Object.hash(localeCode, dark, fontTier, offset, initialState);

  @override
  String toString() => 'LyricWindowConfig(${toJson()})';
}
