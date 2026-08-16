import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 标签仓库契约：标签 CRUD 与「歌曲-标签」多对多管理。
abstract interface class TagRepository {
  /// 全部标签（按名称升序）。
  Stream<List<Tag>> watchTags();

  /// 歌曲 → 标签 id 列表 的映射流（供按标签筛选与打标回显）。
  Stream<Map<int, List<int>>> watchSongTagMap();

  /// 创建标签；已存在同名标签则返回现有 id。
  Future<int> createTag(String name, {int color = 0});

  /// 重命名标签。
  Future<void> renameTag(int id, String name);

  /// 删除标签（级联清理 songs_tags）。
  Future<void> deleteTag(int id);

  /// 为歌曲打上/取消某个标签。
  Future<void> setTagOnSong(int songId, int tagId, {required bool assign});

  /// 批量给（或取消）一批歌曲打某个标签。
  Future<void> setTagOnSongs(
    List<int> songIds,
    int tagId, {
    required bool assign,
  });
}

/// drift 实现：读写本地 SQLite 数据库。
class DriftTagRepository implements TagRepository {
  DriftTagRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Tag>> watchTags() {
    return (_db.select(_db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  @override
  Stream<Map<int, List<int>>> watchSongTagMap() {
    return _db.select(_db.songsTags).watch().map((rows) {
      final map = <int, List<int>>{};
      for (final r in rows) {
        map.putIfAbsent(r.songId, () => <int>[]).add(r.tagId);
      }
      return map;
    });
  }

  @override
  Future<int> createTag(String name, {int color = 0}) async {
    await _db.into(_db.tags).insert(
          TagsCompanion.insert(name: name, color: Value(color)),
          mode: InsertMode.insertOrIgnore,
        );
    final row = await (_db.select(_db.tags)..where((t) => t.name.equals(name)))
        .getSingle();
    return row.id;
  }

  @override
  Future<void> renameTag(int id, String name) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id)))
        .write(TagsCompanion(name: Value(name)));
  }

  @override
  Future<void> deleteTag(int id) async {
    await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> setTagOnSong(int songId, int tagId, {required bool assign}) async {
    if (assign) {
      await _db.into(_db.songsTags).insert(
            SongsTagsCompanion.insert(songId: songId, tagId: tagId),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (_db.delete(_db.songsTags)
            ..where((st) => st.songId.equals(songId) & st.tagId.equals(tagId)))
          .go();
    }
  }

  @override
  Future<void> setTagOnSongs(
    List<int> songIds,
    int tagId, {
    required bool assign,
  }) async {
    if (songIds.isEmpty) return;
    await _db.transaction(() async {
      if (assign) {
        for (final songId in songIds) {
          await _db.into(_db.songsTags).insert(
                SongsTagsCompanion.insert(songId: songId, tagId: tagId),
                mode: InsertMode.insertOrIgnore,
              );
        }
      } else {
        await (_db.delete(_db.songsTags)
              ..where((st) =>
                  st.songId.isIn(songIds) & st.tagId.equals(tagId)))
            .go();
      }
    });
  }
}