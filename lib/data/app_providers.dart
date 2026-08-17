import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'repository/lyrics_repository.dart';
import 'repository/media_repository.dart';
import 'repository/tag_repository.dart';

/// 本地数据库（可被测试覆盖为内存库）。
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final mediaRepositoryProvider =
    Provider<MediaRepository>((ref) => DriftMediaRepository(ref.watch(databaseProvider)));

final tagRepositoryProvider =
    Provider<TagRepository>((ref) => DriftTagRepository(ref.watch(databaseProvider)));

final lyricsRepositoryProvider =
    Provider<LyricsRepository>((ref) => DriftLyricsRepository(ref.watch(databaseProvider)));

/// 全部歌曲流。
final allSongsProvider = StreamProvider<List<Song>>(
  (ref) => ref.watch(mediaRepositoryProvider).watchAllSongs(),
);

/// 全部标签流。
final tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchTags(),
);

/// 歌曲→标签映射流。
final songTagMapProvider = StreamProvider<Map<int, List<int>>>(
  (ref) => ref.watch(tagRepositoryProvider).watchSongTagMap(),
);