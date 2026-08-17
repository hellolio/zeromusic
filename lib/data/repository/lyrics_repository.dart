import '../database/app_database.dart';

/// 歌词仓库契约：按歌曲 id 读写 LRC 歌词缓存。
///
/// 返回原始 LRC 文本；无歌词时流值为 null。解析由上层（services/lyrics）负责。
abstract interface class LyricsRepository {
  /// 监听某首歌曲的歌词文本（null = 无歌词）。
  Stream<String?> watchLyrics(int songId);

  /// 保存歌词（写入或覆盖缓存）。
  Future<void> saveLyrics(int songId, String lrcText);

  /// 删除歌词缓存。
  Future<void> removeLyrics(int songId);
}

/// drift 实现：读写本地 SQLite 数据库的 `lyrics_cache` 表。
class DriftLyricsRepository implements LyricsRepository {
  DriftLyricsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<String?> watchLyrics(int songId) {
    return (_db.select(_db.lyricsCache)
          ..where((t) => t.songId.equals(songId)))
        .watchSingleOrNull()
        .map((row) => row?.lrcText);
  }

  @override
  Future<void> saveLyrics(int songId, String lrcText) async {
    await _db.into(_db.lyricsCache).insertOnConflictUpdate(
          LyricsCacheCompanion.insert(
            songId: songId,
            lrcText: lrcText,
          ),
        );
  }

  @override
  Future<void> removeLyrics(int songId) async {
    await (_db.delete(_db.lyricsCache)..where((t) => t.songId.equals(songId)))
        .go();
  }
}