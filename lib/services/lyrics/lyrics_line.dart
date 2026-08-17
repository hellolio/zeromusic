import 'package:flutter/foundation.dart';

/// 一句歌词：开始时间 + 文本。
@immutable
class LyricsLine {
  const LyricsLine({required this.time, required this.text});

  final Duration time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricsLine &&
      other.time == time &&
      other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LyricsLine(${time.inMilliseconds}ms, "$text")';
}