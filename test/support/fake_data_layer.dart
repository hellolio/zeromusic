import 'dart:async';

import 'package:zeromusic/data/database/app_database.dart';
import 'package:zeromusic/data/repository/lyrics_repository.dart';
import 'package:zeromusic/data/repository/media_repository.dart';
import 'package:zeromusic/data/repository/tag_repository.dart';

import 'demo_fixtures.dart';

/// 测试用内存数据层：完全不依赖 drift，提供给 widget 测试使用。
/// 真实 drift 行为由纯 Dart 数据测试（database_test / repository_drift_test）覆盖。
class FakeDataLayer {
  FakeDataLayer({List<DemoSong>? seed}) {
    final seedSongs = seed ?? demoSongs;
    final idByTitle = <String, int>{};
    for (final demo in seedSongs) {
      final id = _store.songs.length + 1;
      idByTitle[demo.title] = id;
      _store.songs.add(_songFromDemo(id, demo));
    }
    final idByName = <String, int>{};
    for (final (name, color) in demoTags) {
      final id = idByName.length + 1;
      idByName[name] = id;
      _store.tags.add(Tag(id: id, name: name, color: color));
    }
    for (final (title, tagName) in demoSongTags) {
      final songId = idByTitle[title];
      final tagId = idByName[tagName];
      if (songId != null && tagId != null) {
        (songTagLinks[songId] ??= <int>{}).add(tagId);
      }
    }
  }

  final FakeDataStore _store = FakeDataStore();
  late final FakeMediaRepository mediaRepository =
      FakeMediaRepository(_store);
  late final FakeTagRepository tagRepository = FakeTagRepository(_store);
  late final FakeLyricsRepository lyricsRepository =
      FakeLyricsRepository();

  /// 歌曲 → 标签 链接（供仓库级断言）。
  Map<int, Set<int>> get songTagLinks => _store.songTagLinks;
}

/// 共享可变状态，媒体库与标签仓库在其上做同一份数据上的读写。
class FakeDataStore {
  final List<Song> songs = [];
  final List<Tag> tags = [];
  final Map<int, Set<int>> songTagLinks = {};

  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) => _listeners.add(listener);

  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

Song _songFromDemo(int id, DemoSong demo) => Song(
      id: id,
      title: demo.title,
      artist: demo.artist,
      album: demo.album,
      genre: demo.genre,
      durationMs: demo.durationMs,
      mediaType: 0,
      filePath: demo.filePath,
      isFavorite: demo.isFavorite,
      playCount: 0,
      lastPlayedAt: demo.lastPlayedAt,
      createdAt: demo.createdAt,
    );

/// 内存版媒体库仓库：模拟 [MediaRepository] 语义（watch 流 + 增删改）。
class FakeMediaRepository implements MediaRepository {
  FakeMediaRepository(this._store) {
    _store.addListener(_emit);
  }

  final FakeDataStore _store;
  final StreamController<List<Song>> _controller =
      StreamController<List<Song>>.broadcast();

  /// 当前歌曲快照（供测试断言）。
  List<Song> get songs => List.of(_store.songs);

  void _emit() {
    final songs = List.of(_store.songs)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _controller.add(songs);
  }

  @override
  Stream<List<Song>> watchAllSongs() {
    Future.microtask(_emit);
    return _controller.stream;
  }

  Song _byId(int id) =>
      _store.songs.firstWhere((s) => s.id == id, orElse: () => throw StateError('song $id not found'));

  @override
  Future<void> toggleFavorite(int id, bool favorite) async {
    final index = _store.songs.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _store.songs[index] = _byId(id).copyWith(isFavorite: favorite);
    _store.notify();
  }

  @override
  Future<void> batchSetFavorite(List<int> ids, bool favorite) async {
    var changed = false;
    for (final id in ids) {
      final index = _store.songs.indexWhere((s) => s.id == id);
      if (index < 0) continue;
      final song = _byId(id);
      if (song.isFavorite != favorite) changed = true;
      _store.songs[index] = song.copyWith(isFavorite: favorite);
    }
    if (changed) _store.notify();
  }

  @override
  Future<void> deleteSongs(List<int> ids) async {
    if (ids.isEmpty) return;
    _store.songs.removeWhere((s) => ids.contains(s.id));
    for (final id in ids) {
      _store.songTagLinks.remove(id);
    }
    _store.notify();
  }

  @override
  Future<void> updateSong(
    int id, {
    required String title,
    String? artist,
    String? album,
    String? genre,
  }) async {
    final index = _store.songs.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final song = _byId(id);
    _store.songs[index] = Song(
      id: song.id,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      durationMs: song.durationMs,
      mediaType: song.mediaType,
      filePath: song.filePath,
      isFavorite: song.isFavorite,
      playCount: song.playCount,
      lastPlayedAt: song.lastPlayedAt,
      createdAt: song.createdAt,
    );
    _store.notify();
  }

  @override
  Future<void> deleteSong(int id) async {
    _store.songs.removeWhere((s) => s.id == id);
    _store.songTagLinks.remove(id);
    _store.notify();
  }

  @override
  Future<void> updateSongs(
    List<int> ids, {
    String? title,
    String? artist,
    String? album,
    String? genre,
  }) async {
    var changed = false;
    for (final id in ids) {
      final index = _store.songs.indexWhere((s) => s.id == id);
      if (index < 0) continue;
      final song = _byId(id);
      final next = Song(
        id: song.id,
        title: title ?? song.title,
        artist: artist ?? song.artist,
        album: album ?? song.album,
        genre: genre ?? song.genre,
        durationMs: song.durationMs,
        mediaType: song.mediaType,
        filePath: song.filePath,
        isFavorite: song.isFavorite,
        playCount: song.playCount,
        lastPlayedAt: song.lastPlayedAt,
        createdAt: song.createdAt,
      );
      if (next.title != song.title ||
          next.artist != song.artist ||
          next.album != song.album ||
          next.genre != song.genre) {
        changed = true;
        _store.songs[index] = next;
      }
    }
    if (changed) _store.notify();
  }

  @override
  Future<void> markPlayed(int id) async {
    final index = _store.songs.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final song = _byId(id);
    _store.songs[index] = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      genre: song.genre,
      durationMs: song.durationMs,
      mediaType: song.mediaType,
      filePath: song.filePath,
      isFavorite: song.isFavorite,
      playCount: song.playCount + 1,
      lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
      createdAt: song.createdAt,
    );
    _store.notify();
  }

  @override
  Future<bool> isEmpty() async => _store.songs.isEmpty;

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
    final id = _store.songs.length + 1;
    _store.songs.add(
      Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        durationMs: durationMs,
        mediaType: 0,
        filePath: filePath,
        coverPath: coverPath,
        isFavorite: false,
        playCount: 0,
        lastPlayedAt: null,
        createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _store.notify();
    return id;
  }
}

/// 内存版标签仓库：模拟 [TagRepository] 语义。
class FakeTagRepository implements TagRepository {
  FakeTagRepository(this._store) {
    _store.addListener(_emit);
  }

  final FakeDataStore _store;
  final StreamController<List<Tag>> _tagsController =
      StreamController<List<Tag>>.broadcast();
  final StreamController<Map<int, List<int>>> _mapController =
      StreamController<Map<int, List<int>>>.broadcast();

  /// 当前标签快照（供测试断言）。
  List<Tag> get tags => List.of(_store.tags);

  void _emit() {
    final tags = List.of(_store.tags)
      ..sort((a, b) => a.name.compareTo(b.name));
    _tagsController.add(tags);
    final map = <int, List<int>>{};
    _store.songTagLinks.forEach((songId, tagIds) {
      map[songId] = List.of(tagIds)..sort();
    });
    _mapController.add(map);
  }

  @override
  Stream<List<Tag>> watchTags() {
    Future.microtask(_emit);
    return _tagsController.stream;
  }

  @override
  Stream<Map<int, List<int>>> watchSongTagMap() {
    Future.microtask(_emit);
    return _mapController.stream;
  }

  @override
  Future<int> createTag(String name, {int color = 0}) async {
    final existing = _store.tags.where((t) => t.name == name);
    if (existing.isNotEmpty) return existing.first.id;
    final id = _store.tags.length + 1;
    _store.tags.add(Tag(id: id, name: name, color: color));
    _store.notify();
    return id;
  }

  Tag _byId(int id) =>
      _store.tags.firstWhere((t) => t.id == id, orElse: () => throw StateError('tag $id not found'));

  @override
  Future<void> renameTag(int id, String name) async {
    final index = _store.tags.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _store.tags[index] = _byId(id).copyWith(name: name);
    _store.notify();
  }

  @override
  Future<void> deleteTag(int id) async {
    _store.tags.removeWhere((t) => t.id == id);
    for (final links in _store.songTagLinks.values) {
      links.remove(id);
    }
    _store.notify();
  }

  @override
  Future<void> setTagOnSong(int songId, int tagId, {required bool assign}) async {
    if (assign) {
      (_store.songTagLinks[songId] ??= <int>{}).add(tagId);
    } else {
      _store.songTagLinks[songId]?.remove(tagId);
    }
    _store.notify();
  }

  @override
  Future<void> setTagOnSongs(
    List<int> songIds,
    int tagId, {
    required bool assign,
  }) async {
    for (final songId in songIds) {
      if (assign) {
        (_store.songTagLinks[songId] ??= <int>{}).add(tagId);
      } else {
        _store.songTagLinks[songId]?.remove(tagId);
      }
    }
    _store.notify();
  }
}

/// 内存版歌词仓库：模拟 [LyricsRepository] 语义（watch 流 + 存/删）。
class FakeLyricsRepository implements LyricsRepository {
  final Map<int, String> _lyrics = {};
  final Map<int, StreamController<String?>> _controllers = {};

  /// 当前歌词快照（供测试断言）。
  Map<int, String> get lyrics => Map.of(_lyrics);

  StreamController<String?> _controller(int songId) =>
      _controllers.putIfAbsent(
        songId,
        () => StreamController<String?>.broadcast(),
      );

  @override
  Stream<String?> watchLyrics(int songId) {
    final controller = _controller(songId);
    Future.microtask(() {
      if (!controller.isClosed) {
        controller.add(_lyrics[songId]);
      }
    });
    return controller.stream;
  }

  @override
  Future<void> saveLyrics(int songId, String lrcText) async {
    _lyrics[songId] = lrcText;
    final controller = _controllers[songId];
    if (controller != null && !controller.isClosed) {
      controller.add(lrcText);
    }
  }

  @override
  Future<void> removeLyrics(int songId) async {
    _lyrics.remove(songId);
    final controller = _controllers[songId];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }
}