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
import '../../scaffold/content_bottom_inset.dart';
import 'playlist_data.dart';
import 'playlist_menus.dart';

/// 播放列表页面：分类/标签筛选、搜索、点按即播、歌曲上下文菜单。
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key, this.onSwipeNext});

  /// 移动端：在「最近播放」页继续左滑（到达分类边界）时回调，供外层切换到导入页。
  final VoidCallback? onSwipeNext;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  /// 可左右滑动切换的主分类（「标签」分类经弹窗进入，不参与滑动）。
  static const List<PlaylistCategory> _categories = [
    PlaylistCategory.all,
    PlaylistCategory.artists,
    PlaylistCategory.favorites,
    PlaylistCategory.recent,
  ];

  PlaylistCategory _category = PlaylistCategory.all;
  int? _selectedTagId;
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  /// 当前 PageView 页（对应 [_categories] 下标）；「标签」分类选中时页不动，仅内容切换。
  int _pageIndex = 0;
  final PageController _categoryPageController = PageController();

  /// 单次手势是否已触发「交棒外层进入导入页」（防止重复触发）。
  bool _forwardFired = false;

  /// 是否处于批量编辑（多选）模式。
  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _categoryPageController.dispose();
    super.dispose();
  }

  void _selectCategory(PlaylistCategory c) {
    if (c == PlaylistCategory.tag) {
      setState(() {
        _category = c;
        _selectedTagId = null;
      });
      return;
    }
    final index = _categories.indexOf(c);
    setState(() {
      _category = c;
      _selectedTagId = null;
      _pageIndex = index;
    });
    if (_categoryPageController.hasClients) {
      _categoryPageController.animateToPage(
        index,
        duration: AppCurves.pageTransition,
        curve: AppCurves.standard,
      );
    }
  }

  /// 滑动切换主分类；「标签」模式下滑动即回到主分类并清空标签筛选。
  void _onCategoryPageChanged(int i) {
    setState(() {
      _pageIndex = i;
      _category = _categories[i];
      _selectedTagId = null;
    });
  }

  /// 手势开始：复位交棒标志，供下一次手势重新判定。
  bool _onScrollStart(ScrollStartNotification _) {
    _forwardFired = false;
    return false;
  }

  /// 到达最右页（最近播放）后继续左滑（越界）→ 交棒外层进入导入页。
  ///
  /// 使用 [ScrollUpdateNotification] 而非 [OverscrollNotification]：
  /// 本页 PageView 采用 BouncingScrollPhysics，其 applyBoundaryConditions 恒为 0，
  /// 永远不会派发 OverscrollNotification；但拖过最右页边界时 pixels 会越过
  /// maxScrollExtent，据此即可判定越界。
  bool _handleScrollUpdate(ScrollUpdateNotification n) {
    if (_pageIndex != _categories.length - 1) return false;
    // 程序化滚动（如分类切换的 animateToPage）不算手势越界。
    if (n.dragDetails == null) return false;
    if (n.metrics.pixels <= n.metrics.maxScrollExtent + 8) return false;
    if (!_forwardFired) {
      _forwardFired = true;
      widget.onSwipeNext?.call();
    }
    return false;
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
    await showBatchSongMenu(context, ref, songs: songs);
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

  void _openSongMenu(Song song) =>
      showSongMenu(context, ref, song: song);

  Future<void> _openTagFilter() async {
    final selected = await showTagFilterSheet(
      context,
      ref,
      selectedTagId: _selectedTagId,
    );
    if (selected == null || !mounted) return;
    if (selected == -1) {
      _selectCategory(PlaylistCategory.all);
    } else {
      setState(() {
        _selectedTagId = selected;
        _category = PlaylistCategory.tag;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final songs = ref.watch(allSongsProvider).value ?? const <Song>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final songTags =
        ref.watch(songTagMapProvider).value ?? const <int, List<int>>{};
    final playback = ref.watch(audioControllerProvider);
    final currentTrackId = playback.currentTrack?.id;
    // 当前页可见歌曲（全选/批量编辑入口等）——「标签」分类时即标签筛选结果。
    final currentSections = _sectionsFor(
      _category,
      songs: songs,
      tags: tags,
      songTags: songTags,
      search: _searchCtrl.text,
      tagId: _selectedTagId,
    );
    final visibleSongs = [for (final s in currentSections) ...s.songs];
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
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _handleScrollUpdate,
              child: NotificationListener<ScrollStartNotification>(
                onNotification: _onScrollStart,
                child: PageView(
                  controller: _categoryPageController,
                  // 回弹物理：允许拖过最右页边界（pixels 越过 maxScrollExtent），
                  // 由外层 ScrollUpdateNotification 监听判定交棒切页。
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: _onCategoryPageChanged,
                  children: [
                    for (var i = 0; i < _categories.length; i++)
                      _buildCategoryPage(
                        i,
                        strings,
                        songs: songs,
                        tags: tags,
                        songTags: songTags,
                        currentTrackId: currentTrackId,
                        playing: playback.isPlaying,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按分类构建分组列表（纯逻辑，供当前页与 PageView 各页共用）。
  List<PlaylistSection> _sectionsFor(
    PlaylistCategory category, {
    required List<Song> songs,
    required List<Tag> tags,
    required Map<int, List<int>> songTags,
    required String search,
    required int? tagId,
  }) {
    return buildPlaylistSections(
      PlaylistQuery(category: category, search: search, tagId: tagId),
      songs,
      tags,
      songTags,
    );
  }

  /// PageView 某一页：按页主分类渲染；「标签」分类选中时，当前页展示标签筛选结果。
  Widget _buildCategoryPage(
    int i,
    AppStrings strings, {
    required List<Song> songs,
    required List<Tag> tags,
    required Map<int, List<int>> songTags,
    required String? currentTrackId,
    required bool playing,
  }) {
    final pageCat = _categories[i];
    final activeCat = (_category == PlaylistCategory.tag && i == _pageIndex)
        ? PlaylistCategory.tag
        : pageCat;
    final sections = _sectionsFor(
      activeCat,
      songs: songs,
      tags: tags,
      songTags: songTags,
      search: _searchCtrl.text,
      tagId: _selectedTagId,
    );
    final visibleSongs = [for (final s in sections) ...s.songs];
    final visibleTracks = [for (final s in visibleSongs) Track.fromSong(s)];
    final isEmpty = sections.every((s) => s.songs.isEmpty);
    final query = PlaylistQuery(
      category: activeCat,
      search: _searchCtrl.text,
      tagId: _selectedTagId,
    );
    return isEmpty
        ? _buildEmpty(strings, query)
        : _buildList(sections, currentTrackId, visibleTracks, playing: playing);
  }

  Widget _buildCategoryBar(AppStrings strings) {
    final items = [
      (PlaylistCategory.all, strings.tabAll),
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
    List<PlaylistSection> sections,
    String? currentTrackId,
    List<Track> tracks, {
    required bool playing,
  }) {
    final rows = <Widget>[];
    for (final section in sections) {
      if (section.title.isNotEmpty) {
        rows.add(_SectionHeader(title: section.title, count: section.songs.length));
      }
      for (final song in section.songs) {
        final isPlaying = currentTrackId != null &&
            currentTrackId == song.id.toString();
        rows.add(
          SongTile(
            song: song,
            isPlaying: isPlaying,
            isAudible: playing && isPlaying,
            onTap: () => _play(song, tracks),
            onMore: _selecting
                ? null
                : () => _openSongMenu(song),
            selecting: _selecting,
            selected: _selected.contains(song.id),
            onSelect: () => _toggleSelect(song.id),
          ),
        );
      }
    }
    return ListView(
      // 底部预留悬浮玻璃（迷你条+底栏）高度，最后一项可滚到玻璃之上。
      padding: EdgeInsets.only(
        bottom: AppTokens.spaceL + ContentBottomInset.of(context),
      ),
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