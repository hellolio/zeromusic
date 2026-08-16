import 'package:drift/drift.dart';

/// 媒体库（音/视频统一）。字段对应《07_数据库设计》4.1。
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1)();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get durationMs => integer()();
  IntColumn get mediaType => integer().withDefault(const Constant(0))();
  TextColumn get filePath => text().unique()();
  TextColumn get coverPath => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get lastPlayedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
}

/// 标签（含内置“来源:xxx”）。对应 4.2。
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get color => integer().withDefault(const Constant(0))();
}

/// 歌曲与标签多对多关联。对应 4.3。
class SongsTags extends Table {
  IntColumn get songId => integer()();
  IntColumn get tagId => integer()();

  @override
  Set<Column> get primaryKey => {songId, tagId};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE',
        'FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE',
      ];
}

/// 当前播放队列（方案 B，逐行有序）。对应 4.4。
class QueueItems extends Table {
  IntColumn get position => integer()();
  IntColumn get songId => integer()();

  @override
  Set<Column> get primaryKey => {position};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE',
      ];
}

/// 歌词缓存。对应 4.5。
class LyricsCache extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get songId => integer().unique()();
  TextColumn get lrcText => text()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE',
      ];
}