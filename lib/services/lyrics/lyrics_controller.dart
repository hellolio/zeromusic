import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_providers.dart';
import '../audio/audio_controller.dart';
import 'lrc_parser.dart';
import 'lyrics_line.dart';

/// 当前曲目的数字 songId（用于读写歌词）；曲目 id 非数字时为 null。
final currentSongIdProvider = Provider<int?>((ref) {
  final track = ref.watch(audioControllerProvider.select((s) => s.currentTrack));
  return int.tryParse(track?.id ?? '');
});

/// 当前曲目的原始 LRC 文本（未解析；用于编辑回填）。
final lyricsRawProvider = StreamProvider<String?>((ref) {
  final track = ref.watch(audioControllerProvider.select((s) => s.currentTrack));
  final songId = int.tryParse(track?.id ?? '');
  if (songId == null) {
    return Stream.value(null);
  }
  return ref.watch(lyricsRepositoryProvider).watchLyrics(songId);
});

/// 当前曲目的歌词行（已解析并按时间排序）。无歌词或 id 非数字时为空列表。
final lyricsLinesProvider = StreamProvider<List<LyricsLine>>((ref) {
  final track = ref.watch(audioControllerProvider.select((s) => s.currentTrack));
  final songId = int.tryParse(track?.id ?? '');
  if (songId == null) {
    return Stream.value(const <LyricsLine>[]);
  }
  return ref.watch(lyricsRepositoryProvider).watchLyrics(songId).map((raw) {
    if (raw == null || raw.trim().isEmpty) return const <LyricsLine>[];
    return parseLrc(raw);
  });
});

/// 当前高亮行下标：最后一条 time ≤ position 的歌词；-1 = 尚未到第一行。
final activeLyricIndexProvider = Provider<int>((ref) {
  final position =
      ref.watch(audioControllerProvider.select((s) => s.position));
  final lines = ref.watch(lyricsLinesProvider).value ?? const <LyricsLine>[];
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time <= position) {
      index = i;
    } else {
      break;
    }
  }
  return index;
});