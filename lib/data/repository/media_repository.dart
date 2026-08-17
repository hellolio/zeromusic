import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 媒体库仓库契约：统一封装歌曲元数据的查询与增删改，屏蔽底层实现。
abstract interface class MediaRepository {
  /// 全部歌曲（按导入时间升序）。上层自行做分类/分组/搜索。
  Stream<List<Song>> watchAllSongs();

  /// 切换喜欢状态。
  Future<void> toggleFavorite(int id, bool favorite);

  /// 批量设置喜欢状态。
  Future<void> batchSetFavorite(List<int> ids, bool favorite);

  /// 批量删除歌曲：songs_tags / queue_items / lyrics_cache 级联清理。
  Future<void> deleteSongs(List<int> ids);

  /// 编辑歌曲元数据（歌名必填，其余可清空）。
  Future<void> updateSong(
    int id, {
    required String title,
    String? artist,
    String? album,
    String? genre,
  });

  /// 删除歌曲：songs_tags / queue_items / lyrics_cache 级联清理。
  Future<void> deleteSong(int id);

  /// 批量更新歌曲元数据（仅非空字段应用到全部选中的歌曲）。
  Future<void> updateSongs(
    List<int> ids, {
    String? title,
    String? artist,
    String? album,
    String? genre,
  });

  /// 记录一次播放：播放次数 +1，更新最近播放时间。
  Future<void> markPlayed(int id);

  /// 媒体库是否为空。
  Future<bool> isEmpty();

  /// 导入落库：写入一首新歌（音频），返回新歌 id。
  /// [filePath] 唯一（避免重复导入同名冲突）；[createdAt] 默认取当前时间。
  Future<int> addSong({
    required String title,
    String? artist,
    String? album,
    String? genre,
    required int durationMs,
    required String filePath,
    String? coverPath,
    int? createdAt,
  });
}

/// drift 实现：读写本地 SQLite 数据库。
class DriftMediaRepository implements MediaRepository {
  DriftMediaRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Song>> watchAllSongs() {
    return (_db.select(_db.songs)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  @override
  Future<void> toggleFavorite(int id, bool favorite) async {
    await (_db.update(_db.songs)..where((t) => t.id.equals(id)))
        .write(SongsCompanion(isFavorite: Value(favorite)));
  }

  @override
  Future<void> batchSetFavorite(List<int> ids, bool favorite) async {
    await (_db.update(_db.songs)..where((t) => t.id.isIn(ids)))
        .write(SongsCompanion(isFavorite: Value(favorite)));
  }

  @override
  Future<void> deleteSongs(List<int> ids) async {
    await (_db.delete(_db.songs)..where((t) => t.id.isIn(ids))).go();
  }

  @override
  Future<void> updateSong(
    int id, {
    required String title,
    String? artist,
    String? album,
    String? genre,
  }) async {
    await (_db.update(_db.songs)..where((t) => t.id.equals(id))).write(
      SongsCompanion(
        title: Value(title),
        artist: Value(artist),
        album: Value(album),
        genre: Value(genre),
      ),
    );
  }

  @override
  Future<void> deleteSong(int id) async {
    await (_db.delete(_db.songs)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> updateSongs(
    List<int> ids, {
    String? title,
    String? artist,
    String? album,
    String? genre,
  }) async {
    await (_db.update(_db.songs)..where((t) => t.id.isIn(ids))).write(
      SongsCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        artist: artist != null ? Value(artist) : const Value.absent(),
        album: album != null ? Value(album) : const Value.absent(),
        genre: genre != null ? Value(genre) : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> markPlayed(int id) async {
    final rows =
        await (_db.select(_db.songs)..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty) return;
    await (_db.update(_db.songs)..where((t) => t.id.equals(id))).write(
      SongsCompanion(
        playCount: Value(rows.first.playCount + 1),
        lastPlayedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<bool> isEmpty() async => await _db.songs.count().getSingle() == 0;

  @override
  Future<int> addSong({
    required String title,
    String? artist,
    String? album,
    String? genre,
    required int durationMs,
    required String filePath,
    String? coverPath,
    int? createdAt,
  }) async {
    return _db.into(_db.songs).insert(
          SongsCompanion.insert(
            title: title,
            durationMs: durationMs,
            filePath: filePath,
            createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
            artist: Value(artist),
            album: Value(album),
            genre: Value(genre),
            coverPath: Value(coverPath),
          ),
        );
  }
}