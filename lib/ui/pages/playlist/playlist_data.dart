import '../../../data/database/app_database.dart';

/// 播放列表页面纯逻辑：分类、搜索过滤、分组。
/// 不依赖 Flutter 组件，便于单元测试。

enum PlaylistCategory { all, albums, artists, favorites, recent, tag }

/// 页面当前筛选状态。
class PlaylistQuery {
  const PlaylistQuery({
    required this.category,
    this.search = '',
    this.tagId,
  });

  final PlaylistCategory category;
  final String search;
  final int? tagId;

  bool get hasSearch => search.trim().isNotEmpty;
  String get keyword => search.trim().toLowerCase();
}

/// 一组需要渲染的歌曲（分组标题；扁平视图标题为空串）。
class PlaylistSection {
  const PlaylistSection({required this.title, required this.songs});

  final String title;
  final List<Song> songs;
}

/// mm:ss 时长格式。
String formatDurationMs(int ms) {
  final total = ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 根据查询状态把歌曲构建为分组列表。
List<PlaylistSection> buildPlaylistSections(
  PlaylistQuery query,
  List<Song> songs,
  List<Tag> tags,
  Map<int, List<int>> songTags,
) {
  final tagNamesById = {for (final t in tags) t.id: t.name.toLowerCase()};
  var list = _applyCategory(query, songs, songTags);
  if (query.hasSearch) {
    list = list
        .where((s) => _matches(s, query.keyword, songTags, tagNamesById))
        .toList();
  }

  switch (query.category) {
    case PlaylistCategory.albums:
      return _groupBy(list, (s) => s.album ?? _unknown);
    case PlaylistCategory.artists:
      return _groupBy(list, (s) => s.artist ?? _unknown);
    default:
      return [PlaylistSection(title: '', songs: list)];
  }
}

const _unknown = '未知';

List<Song> _applyCategory(
  PlaylistQuery query,
  List<Song> songs,
  Map<int, List<int>> songTags,
) {
  switch (query.category) {
    case PlaylistCategory.favorites:
      return songs.where((s) => s.isFavorite).toList();
    case PlaylistCategory.recent:
      final list = songs.toList()
        ..sort((a, b) {
          final aT = a.lastPlayedAt;
          final bT = b.lastPlayedAt;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1; // 无播放时间排最后
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });
      return list;
    case PlaylistCategory.tag:
      final tagId = query.tagId;
      if (tagId == null) return const [];
      return songs
          .where((s) => songTags[s.id]?.contains(tagId) ?? false)
          .toList();
    case PlaylistCategory.all:
    case PlaylistCategory.albums:
    case PlaylistCategory.artists:
      return songs.toList();
  }
}

/// 歌名 / 歌手 / 专辑 / 标签名 任一命中即匹配。
bool _matches(
  Song song,
  String keyword,
  Map<int, List<int>> songTags,
  Map<int, String> tagNamesById,
) {
  final haystacks = [
    song.title.toLowerCase(),
    song.artist?.toLowerCase() ?? '',
    song.album?.toLowerCase() ?? '',
  ];
  for (final h in haystacks) {
    if (h.contains(keyword)) return true;
  }
  // 搜索打在该歌上的标签名。
  final tagIds = songTags[song.id] ?? const [];
  return tagIds.any((id) => (tagNamesById[id] ?? '').contains(keyword));
}

/// 按 key 分组，保持首次出现顺序。
List<PlaylistSection> _groupBy(List<Song> songs, String Function(Song) key) {
  final order = <String>[];
  final map = <String, List<Song>>{};
  for (final s in songs) {
    final k = key(s);
    if (!map.containsKey(k)) {
      order.add(k);
      map[k] = [];
    }
    map[k]!.add(s);
  }
  return [
    for (final k in order) PlaylistSection(title: k, songs: map[k]!),
  ];
}