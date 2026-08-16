import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  tearDown(() async {
    await db.close();
  });

  test('5 张表可创建并写入/读取', () async {
    final checks = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    ).get();
    final names = checks.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll({'songs', 'tags', 'songs_tags', 'queue_items', 'lyrics_cache'}),
    );

    final songId = await db.into(db.songs).insert(
          SongsCompanion.insert(
            title: '测试歌曲',
            durationMs: 180000,
            filePath: '/tmp/test.mp3',
            createdAt: 0,
          ),
        );
    expect(songId, isPositive);

    final tagId = await db.into(db.tags).insert(
          TagsCompanion.insert(name: '来源:云端'),
        );
    await db.into(db.songsTags).insert(
          SongsTagsCompanion.insert(songId: songId, tagId: tagId),
        );
    await db.into(db.queueItems).insert(
          QueueItemsCompanion.insert(position: Value(0), songId: songId),
        );
    await db.into(db.lyricsCache).insert(
          LyricsCacheCompanion.insert(songId: songId, lrcText: '[00:00]test'),
        );

    final song = await (db.select(db.songs)
          ..where((s) => s.id.equals(songId)))
        .getSingle();
    expect(song.title, '测试歌曲');
    expect(await db.songsTags.count().getSingle(), 1);
    expect((await db.select(db.queueItems).getSingle()).position, 0);
  });

  test('删除歌曲级联清理关联数据', () async {
    final songId = await db.into(db.songs).insert(
          SongsCompanion.insert(
            title: '待删歌曲',
            durationMs: 1000,
            filePath: '/tmp/to-delete.mp3',
            createdAt: 0,
          ),
        );
    await db.into(db.queueItems).insert(
          QueueItemsCompanion.insert(position: Value(0), songId: songId),
        );

    await (db.delete(db.songs)..where((s) => s.id.equals(songId))).go();

    expect(await db.songs.count().getSingle(), 0);
    expect(await db.queueItems.count().getSingle(), 0);
  });
}
