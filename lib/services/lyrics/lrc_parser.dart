import 'lyrics_line.dart';

/// LRC 歌词解析器。
///
/// 支持：
/// - 时间戳格式 `[mm:ss]`、`[mm:ss.xx]`、`[mm:ss.xxx]`；
/// - 一行多个时间戳（`[00:12][00:45]text` → 两条歌词）；
/// - 元信息行 `[ti:…]`、`[ar:…]`、`[al:…]`、`[by:…]`（忽略）；
/// - 全局偏移 `[offset:+/-毫秒]`（作用于全部时间戳）；
/// - 内联增强时间戳 `<mm:ss.xx>` 会被剥离（仅保留行文本）。
///
/// 无任何有效歌词行时返回空列表。
List<LyricsLine> parseLrc(String text) {
  if (text.trim().isEmpty) return const [];

  int? offsetMs;
  final rawLines = <(Duration, String)>[];

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    // 全局 offset 标签：[offset:+500] / [offset:-100]
    final offsetMatch = RegExp(r'^\[offset:([+-]?\d+)\]$').firstMatch(line);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1)!);
      continue;
    }

    // 连续时间戳 + 文本。
    final stamps = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]')
        .allMatches(line);
    if (stamps.isEmpty) continue;

    final start = stamps.last.end;
    final content = line
        .substring(start)
        .trim()
        .replaceAll(RegExp(r'<[^>]+>'), '');

    for (final m in stamps) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final frac = m.group(3) ?? '';
      var millis = minutes * 60000 + seconds * 1000;
      if (frac.isNotEmpty) {
        // .xx → x0 / .xxx → xxx（毫秒）。
        millis += (frac.length == 1)
            ? int.parse(frac) * 100
            : ((frac.length == 2) ? int.parse(frac) * 10 : int.parse(frac));
      }
      rawLines.add((Duration(milliseconds: millis), content));
    }
  }

  if (rawLines.isEmpty) return const [];

  final delta = offsetMs ?? 0;
  return (rawLines.map((e) {
        final (time, text) = e;
        return LyricsLine(
          time: Duration(milliseconds: time.inMilliseconds + delta),
          text: text,
        );
      }).toList()
        ..sort((a, b) => a.time.compareTo(b.time)));
}