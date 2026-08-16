import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart';

/// 曲目元数据（骨架占位，后续由媒体库填充完整字段）。
@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.filePath,
  });

  /// 从数据库歌曲记录构建队列曲目。
  factory Track.fromSong(Song song) {
    return Track(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
      filePath: song.filePath,
    );
  }

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? filePath;

  String get subtitle => artist ?? '';
}