import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/app_providers.dart';
import '../../../data/database/app_database.dart';
import '../../../services/audio/audio_controller.dart';
import '../../../services/audio/track.dart';
import '../../components/song_tile.dart';
import 'playlist_data.dart';
import 'playlist_menus.dart';

/// 播放列表页面：分类/标签筛选、搜索、点按即播、歌曲上下文菜单。
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  PlaylistCategory _category = PlaylistCategory.all;
  int? _selectedTagId;
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  /// 是否处于批量编辑（多选）模式。
  bool _selecting = false;
  final Set<int> _selected = {};
  final GlobalKey _batchMenuKey = GlobalKey();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectCategory(PlaylistCategory c) {
    setState(() {
      _category = c;
      _selectedTagId = null;
    });
  }

  void _enterSelect() {
    setState(() {
      _selecting = true;
      _selected.clear();
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleSelectAll(List<Song> visibleSongs) {
    if (visibleSongs.isEmpty) return;
    final ids = {for (final s in visibleSongs) s.id};
    final allSelected = _selected.containsAll(ids);
    setState(() {
      if (allSelected) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  List<Song> _allSongs() =>
      ref.read(allSongsProvider).value ?? const <Song>[];

  List<Song> _selectedSongs() =>
      _allSongs().where((s) => _selected.contains(s.id)).toList(growable: false);

  Future<void> _openBatchMenu() async {
    final songs = _selectedSongs();
    if (songs.isEmpty) return;
    final box = _batchMenuKey.currentContext?.findRenderObject();
    final center =
        box is RenderBox ? box.localToGlobal(box.size.center(Offset.zero)) : Offset.zero;
    await showBatchSongMenu(context, ref, songs: songs, anchor: center);
    if (!mounted) return;
    // 删除可能已移除部分歌曲，清理失效的选中项。
    final aliveIds = {for (final s in _allSongs()) s.id};
    setState(() => _selected.removeWhere((id) => !aliveIds.contains(id)));
  }

  /// 点按歌曲：按当前筛选视图的展示顺序整列入队，并从该曲开始播放。
  Future<void> _play(Song song, List<Track> tracks) async {
    final startIndex = tracks.indexWhere((t) => t.id == song.id.toString());
    ref
        .read(audioControllerProvider.notifier)
        .playQueue(tracks, startIndex: startIndex < 0 ? 0 : startIndex);
    await ref.read(mediaRepositoryProvider).markPlayed(song.id);
  }

  void _openSongMenu(Song song, Offset anchor) =>
      showSongMenu(context, ref, song: song, anchor: anchor);

  Future<void> _openTagFilter() async {
    final selected = await showTagFilterSheet(
      context,
      ref,
      selectedTagId: _selectedTagId,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (selected == -1) {
        _selectedTagId = null;
        _category = PlaylistCategory.all;
      } else {
        _selectedTagId = selected;
        _category = PlaylistCategory.tag;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final songs = ref.watch(allSongsProvider).value ?? const <Song>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final songTags =
        ref.watch(songTagMapProvider).value ?? const <int, List<int>>{};
    final query = PlaylistQuery(
      category: _category,
      search: _searchCtrl.text,
      tagId: _selectedTagId,
    );
    final sections = buildPlaylistSections(query, songs, tags, songTags);
    final visibleSongs = [for (final s in sections) ...s.songs];
    final visibleTracks = [for (final s in visibleSongs) Track.fromSong(s)];
    final playback = ref.watch(audioControllerProvider);
    final currentTrackId = playback.currentTrack?.id;
    final isEmpty = sections.every((s) => s.songs.isEmpty);
    final allVisibleSelected =
        visibleSongs.isNotEmpty && visibleSongs.every((s) => _selected.contains(s.id));

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(CupertinoIcons.xmark),
                tooltip: strings.cancel,
                onPressed: _exitSelect,
              )
            : null,
        title: Text(
          _selecting
              ? '${strings.selectedCount} ${_selected.length}'
              : strings.libraryTitle,
        ),
        actions: _selecting
            ? [
                IconButton(
                  icon: Icon(
                    allVisibleSelected
                        ? CupertinoIcons.checkmark_square
                        : CupertinoIcons.square,
                  ),
                  tooltip:
                      allVisibleSelected ? strings.deselectAll : strings.selectAll,
                  onPressed: () => _toggleSelectAll(visibleSongs),
                ),
                IconButton(
                  key: _batchMenuKey,
                  icon: const Icon(CupertinoIcons.ellipsis),
                  tooltip: strings.batchEdit,
                  onPressed: _selected.isEmpty ? null : _openBatchMenu,
                ),
              ]
            : [
                IconButton(
                  icon: Icon(_searching ? CupertinoIcons.xmark : CupertinoIcons.search),
                  tooltip: strings.search,
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _searchCtrl.clear();
                  }),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.add),
                  tooltip: strings.newTag,
                  onPressed: () => showCreateTagDialog(context, ref),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.square_list),
                  tooltip: strings.batchEdit,
                  onPressed: visibleSongs.isEmpty ? null : _enterSelect,
                ),
              ],
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceM, AppTokens.spaceXs, AppTokens.spaceM, AppTokens.spaceS),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: strings.search,
                  prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                          onPressed: () => setState(_searchCtrl.clear),
                        ),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          _buildCategoryBar(strings),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppCurves.pageTransition,
              switchInCurve: AppCurves.standard,
              switchOutCurve: AppCurves.standard,
              transitionBuilder: (child, animation) {
                final slide = SlideTransition(
                  position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
                      .animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
                return slide;
              },
              child: KeyedSubtree(
                key: ValueKey('$_category|$_selectedTagId|${_searchCtrl.text}'),
                child: isEmpty ? _buildEmpty(strings, query) : _buildList(sections, currentTrackId, visibleTracks),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(AppStrings strings) {
    final items = [
      (PlaylistCategory.all, strings.tabAll),
      (PlaylistCategory.albums, strings.tabAlbums),
      (PlaylistCategory.artists, strings.tabArtists),
      (PlaylistCategory.favorites, strings.tabFavorites),
      (PlaylistCategory.recent, strings.tabRecent),
    ];
    final selectedTag = _selectedTagId;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM),
        children: [
          for (final (cat, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: AppTokens.spaceS),
              child: _CategoryChip(
                label: label,
                selected: _category == cat,
                onTap: () => _selectCategory(cat),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.spaceS),
            child: _CategoryChip(
              label: _category == PlaylistCategory.tag && selectedTag != null
                  ? strings.tabTags
                  : '${strings.tabTags} ▾',
              selected: _category == PlaylistCategory.tag,
              onTap: _openTagFilter,
              icon: CupertinoIcons.tag,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
      List<PlaylistSection> sections, String? currentTrackId, List<Track> tracks) {
    final rows = <Widget>[];
    for (final section in sections) {
      if (section.title.isNotEmpty) {
        rows.add(_SectionHeader(title: section.title, count: section.songs.length));
      }
      for (final song in section.songs) {
        rows.add(
          SongTile(
            song: song,
            isPlaying: currentTrackId != null && currentTrackId == song.id.toString(),
            onTap: () => _play(song, tracks),
            onMore: _selecting
                ? null
                : (anchor) => _openSongMenu(song, anchor),
            selecting: _selecting,
            selected: _selected.contains(song.id),
            onSelect: () => _toggleSelect(song.id),
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceL),
      children: rows,
    );
  }

  Widget _buildEmpty(AppStrings strings, PlaylistQuery query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.music_note, size: 56),
          const SizedBox(height: AppTokens.spaceM),
          Text(
            query.hasSearch ? strings.noResult : strings.empty,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
          ),
        ],
      ),
    );
  }
}

/// 分类横向标签（胶囊）。
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppCurves.quickMotion,
        curve: AppCurves.standard,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : theme.colorScheme.onSecondary),
              const SizedBox(width: AppTokens.spaceXs),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? Colors.white : theme.colorScheme.onSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceM, AppTokens.spaceM, AppTokens.spaceM, AppTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSecondary),
          ),
        ],
      ),
    );
  }
}