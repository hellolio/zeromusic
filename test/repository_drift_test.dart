import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/data/database/app_database.dart';
import 'package:zeromusic/data/repository/media_repository.dart';
import 'package:zeromusic/data/repository/tag_repository.dart';

/// 纯 Dart 数据层测试：真实 drift（内存库）+ Drift* 实现。
/// 非 widget 环境，`db.close()` 不存在 fake-async 冲突。

/// 等待 drift 的流发射/微任务落地。
Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late AppDatabase db;
  late DriftMediaRepository media;
  late DriftTagRepository tags;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    media = DriftMediaRepository(db);
    tags = DriftTagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertSong(
    String title, {
    int createdAt = 0,
    bool favorite = false,
  }) {
    return db.into(db.songs).insert(
          SongsCompanion.insert(
            title: title,
            durationMs: 1000,
            filePath: '/tmp/${title}_song.mp3',
            createdAt: createdAt,
            isFavorite: Value(favorite),
          ),
        );
  }

  Future<int> insertTag(String name) {
    return db.into(db.tags).insert(
          TagsCompanion.insert(name: name),
          mode: InsertMode.insertOrIgnore,
        );
  }

  group('DriftMediaRepository', () {
    test('watchAllSongs 返回全部歌曲并按导入时间升序', () async {
      final seen = <List<Song>>[];
      final sub = media.watchAllSongs().listen(seen.add);
      addTearDown(sub.cancel);

      await _flush();
      expect(seen, isNotEmpty);
      expect(seen.last, isEmpty);

      await insertSong('B', createdAt: 20);
      await insertSong('A', createdAt: 10);
      await insertSong('C', createdAt: 15);
      await _flush();

      expect(seen.last.map((s) => s.title), ['A', 'C', 'B']);
    });

    test('toggleFavorite 切换收藏标记', () async {
      final id = await insertSong('X');

      await media.toggleFavorite(id, true);
      await _flush();
      var row = await (db.select(db.songs)..where((s) => s.id.equals(id))).getSingle();
      expect(row.isFavorite, isTrue);

      await media.toggleFavorite(id, false);
      await _flush();
      row = await (db.select(db.songs)..where((s) => s.id.equals(id))).getSingle();
      expect(row.isFavorite, isFalse);
    });

    test('batchSetFavorite 批量设置/清除收藏', () async {
      final a = await insertSong('A');
      final b = await insertSong('B');

      await media.batchSetFavorite([a, b], true);
      await _flush();
      var rows = await (db.select(db.songs)..where((s) => s.id.isIn([a, b]))).get();
      expect(rows, hasLength(2));
      expect(rows.every((s) => s.isFavorite), isTrue);

      await media.batchSetFavorite([a], false);
      await _flush();
      rows = await (db.select(db.songs)..where((s) => s.id.isIn([a, b]))).get();
      expect(rows.firstWhere((s) => s.id == a).isFavorite, isFalse);
      expect(rows.firstWhere((s) => s.id == b).isFavorite, isTrue);
    });

    test('deleteSongs 批量删除并级联清理', () async {
      final a = await insertSong('A');
      final b = await insertSong('B');
      final tagId = await insertTag('健身');
      await db.into(db.songsTags).insert(
            SongsTagsCompanion.insert(songId: a, tagId: tagId),
          );
      await db.into(db.queueItems).insert(
            QueueItemsCompanion.insert(position: Value(0), songId: b),
          );

      await media.deleteSongs([a, b]);
      await _flush();

      expect(await db.songs.count().getSingle(), 0);
      expect(await db.songsTags.count().getSingle(), 0);
      expect(await db.queueItems.count().getSingle(), 0);
    });

    test('updateSong 更新元数据', () async {
      final id = await insertSong('X');

      await media.updateSong(id, title: 'Y', artist: '作者', album: '合集', genre: '流行');
      final row =
          await (db.select(db.songs)..where((s) => s.id.equals(id))).getSingle();
      expect(row.title, 'Y');
      expect(row.artist, '作者');
      expect(row.album, '合集');
      expect(row.genre, '流行');
    });

    test('updateSongs 批量更新：仅更新传入字段，null 字段保持不变', () async {
      final a = await insertSong('A');
      final b = await insertSong('B');

      await media.updateSongs([a, b], artist: '作者', genre: '流行');
      await _flush();

      for (final id in [a, b]) {
        final row =
            await (db.select(db.songs)..where((s) => s.id.equals(id))).getSingle();
        expect(row.title, id == a ? 'A' : 'B'); // 未传 title 不修改
        expect(row.artist, '作者');
        expect(row.album == null, isTrue);
        expect(row.genre, '流行');
      }
    });

    test('markPlayed 播放次数 +1 并刷新最近播放；未知 id 忽略', () async {
      final id = await insertSong('X');
      await media.markPlayed(id);
      await media.markPlayed(id);
      await _flush();

      final row =
          await (db.select(db.songs)..where((s) => s.id.equals(id))).getSingle();
      expect(row.playCount, 2);
      expect(row.lastPlayedAt == null, isFalse);

      await media.markPlayed(99999); // 不应抛异常
    });

    test('deleteSong 级联清理关联表', () async {
      final id = await insertSong('X');
      final tagId = await insertTag('健身');
      await db.into(db.songsTags).insert(
            SongsTagsCompanion.insert(songId: id, tagId: tagId),
          );
      await db.into(db.queueItems).insert(
            QueueItemsCompanion.insert(position: Value(0), songId: id),
          );
      await db.into(db.lyricsCache).insert(
            LyricsCacheCompanion.insert(songId: id, lrcText: '[00:00]x'),
          );

      await media.deleteSong(id);
      await _flush();

      expect(await db.songs.count().getSingle(), 0);
      expect(await db.songsTags.count().getSingle(), 0);
      expect(await db.queueItems.count().getSingle(), 0);
      expect(await db.lyricsCache.count().getSingle(), 0);
    });

    test('isEmpty 反映媒体库是否为空', () async {
      expect(await media.isEmpty(), isTrue);
      await insertSong('X');
      expect(await media.isEmpty(), isFalse);
    });
  });

  group('DriftTagRepository', () {
    test('watchTags 与 watchSongTagMap 正确反映关联', () async {
      final seenTags = <List<Tag>>[];
      final seenMap = <Map<int, List<int>>>[];
      final tagSub = tags.watchTags().listen(seenTags.add);
      final mapSub = tags.watchSongTagMap().listen(seenMap.add);
      addTearDown(tagSub.cancel);
      addTearDown(mapSub.cancel);

      final songId1 = await insertSong('A');
      final songId2 = await insertSong('B');
      final fitnessId = await insertTag('健身');
      final healingId = await insertTag('治愈');
      await tags.setTagOnSong(songId1, fitnessId, assign: true);
      await tags.setTagOnSong(songId1, healingId, assign: true);
      await tags.setTagOnSong(songId2, fitnessId, assign: true);
      await _flush();

      expect(seenTags.last.map((t) => t.name), ['健身', '治愈']);
      expect(seenMap.last[songId1], [fitnessId, healingId]);
      expect(seenMap.last[songId2], [fitnessId]);

      await tags.setTagOnSong(songId1, fitnessId, assign: false);
      await _flush();
      expect(seenMap.last[songId1], [healingId]);
    });

    test('createTag 幂等：同名返回相同 id', () async {
      final a = await tags.createTag('健身');
      final b = await tags.createTag('健身');
      expect(a, b);
    });

    test('setTagOnSongs 批量打标/取消', () async {
      final songId1 = await insertSong('A');
      final songId2 = await insertSong('B');
      final songId3 = await insertSong('C');
      final fitnessId = await insertTag('健身');

      await tags.setTagOnSongs([songId1, songId2, songId3], fitnessId, assign: true);
      await _flush();
      expect(
        await (db.select(db.songsTags)
              ..where((st) => st.tagId.equals(fitnessId)))
            .get(),
        hasLength(3),
      );

      // 重复打标幂等。
      await tags.setTagOnSongs([songId1], fitnessId, assign: true);
      await _flush();
      expect(
        await (db.select(db.songsTags)
              ..where((st) => st.tagId.equals(fitnessId)))
            .get(),
        hasLength(3),
      );

      // 批量取消其中两首。
      await tags.setTagOnSongs([songId1, songId3], fitnessId, assign: false);
      await _flush();
      final rows = await (db.select(db.songsTags)
            ..where((st) => st.tagId.equals(fitnessId)))
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.songId, songId2);
    });

    test('renameTag 修改标签名', () async {
      final id = await tags.createTag('旧名');
      await tags.renameTag(id, '新名');
      final row = await (db.select(db.tags)..where((t) => t.id.equals(id))).getSingle();
      expect(row.name, '新名');
    });

    test('deleteTag 级联清理 songs_tags', () async {
      final id = await insertSong('A');
      final tagId = await tags.createTag('待删');
      await tags.setTagOnSong(id, tagId, assign: true);

      await tags.deleteTag(tagId);
      await _flush();

      expect(await db.tags.count().getSingle(), 0);
      expect(await db.songsTags.count().getSingle(), 0);
    });
  });
}