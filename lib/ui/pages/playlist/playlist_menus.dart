import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/app_providers.dart';
import '../../../data/database/app_database.dart';
import '../../../services/audio/audio_controller.dart';
import '../../../services/audio/track.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';

/// 歌曲上下文菜单（⋯ / 长按 / 鼠标右键）：统一窗口居中的毛玻璃弹框。
Future<void> showSongMenu(
  BuildContext context,
  WidgetRef ref, {
  required Song song,
}) async {
  final strings = context.strings;

  void favorite() =>
      ref.read(mediaRepositoryProvider).toggleFavorite(song.id, !song.isFavorite);
  void tagSong() => showTagPicker(context, ref, song);
  void enqueue() => ref.read(audioControllerProvider.notifier).enqueue(Track.fromSong(song));
  void edit() => showEditSongDialog(context, ref, song);
  void remove() => showDeleteConfirm(context, ref, song);

  await showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(context, song.isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                song.isFavorite ? strings.unfavorite : strings.favorite,
                favorite,
                color: song.isFavorite ? AppTokens.favorite : null),
            _sheetTile(context, CupertinoIcons.tag, strings.tagSong, tagSong),
            _sheetTile(context, CupertinoIcons.add, strings.addToQueue, enqueue),
            _sheetTile(context, CupertinoIcons.pencil, strings.edit, edit),
            _sheetTile(context, CupertinoIcons.trash, strings.delete, remove,
                color: AppTokens.favorite),
            const SizedBox(height: AppTokens.spaceS),
          ],
        ),
      ),
    ),
  );
}

Widget _sheetTile(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback onTap, {
  Color? color,
}) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label),
    onTap: () {
      Navigator.of(context).pop();
      onTap();
    },
  );
}

/// 批量编辑菜单：统一窗口居中的毛玻璃弹框。
/// 操作与单曲菜单一致：喜欢/取消喜欢、打标签、加入播放队列、编辑、删除。
Future<void> showBatchSongMenu(
  BuildContext context,
  WidgetRef ref, {
  required List<Song> songs,
}) async {
  if (songs.isEmpty) return;
  final strings = context.strings;
  final ids = [for (final s in songs) s.id];
  final allFavorite = songs.every((s) => s.isFavorite);

  void favorite() =>
      ref.read(mediaRepositoryProvider).batchSetFavorite(ids, !allFavorite);
  void tagSongs() =>
      showBatchTagPicker(context, ref, songIds: ids);
  void enqueue() {
    final controller = ref.read(audioControllerProvider.notifier);
    for (final s in songs) {
      controller.enqueue(Track.fromSong(s));
    }
  }

  void edit() => showBatchEditDialog(context, ref, songs: songs);
  void remove() => showBatchDeleteConfirm(context, ref, songs: songs);

  await showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(context, allFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                allFavorite ? strings.unfavorite : strings.favorite,
                favorite,
                color: allFavorite ? AppTokens.favorite : null),
            _sheetTile(context, CupertinoIcons.tag, strings.tagSong, tagSongs),
            _sheetTile(context, CupertinoIcons.pencil, strings.edit, edit),
            _sheetTile(context, CupertinoIcons.add, strings.addToQueue, enqueue),
            _sheetTile(context, CupertinoIcons.trash, strings.delete, remove,
                color: AppTokens.favorite),
            const SizedBox(height: AppTokens.spaceS),
          ],
        ),
      ),
    ),
  );
}

/// 批量删除二次确认弹窗。
Future<void> showBatchDeleteConfirm(
  BuildContext context,
  WidgetRef ref, {
  required List<Song> songs,
}) async {
  final strings = context.strings;
  final confirmed = await showCenterPopup<bool>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      padding: const EdgeInsets.all(AppTokens.spaceL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.deleteConfirmTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceM),
          Text(strings.deleteConfirmMessage,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSecondary)),
          const SizedBox(height: AppTokens.spaceL),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              const SizedBox(width: AppTokens.spaceS),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(strings.delete,
                    style: const TextStyle(color: AppTokens.favorite)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) {
    await ref
        .read(mediaRepositoryProvider)
        .deleteSongs([for (final s in songs) s.id]);
  }
}

/// 批量编辑歌曲信息弹窗：字段留空表示不修改，非空字段应用到全部选中歌曲。
Future<void> showBatchEditDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Song> songs,
}) async {
  final strings = context.strings;
  final ids = [for (final s in songs) s.id];
  final titleCtrl = TextEditingController();
  final artistCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final genreCtrl = TextEditingController();

  await showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      padding: const EdgeInsets.all(AppTokens.spaceL),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.edit, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceXs),
            Text(strings.batchEditHint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSecondary)),
            const SizedBox(height: AppTokens.spaceM),
            _field(context, strings.songTitle, titleCtrl),
            _field(context, strings.songArtist, artistCtrl),
            _field(context, strings.songAlbum, albumCtrl),
            _field(context, strings.songGenre, genreCtrl),
            const SizedBox(height: AppTokens.spaceL),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: AppTokens.spaceS),
                TextButton(
                  onPressed: () {
                    ref.read(mediaRepositoryProvider).updateSongs(
                          ids,
                          title: _blankToNull(titleCtrl.text),
                          artist: _blankToNull(artistCtrl.text),
                          album: _blankToNull(albumCtrl.text),
                          genre: _blankToNull(genreCtrl.text),
                        );
                    Navigator.of(context).pop();
                  },
                  child: Text(strings.save),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 删除二次确认弹窗。
Future<void> showDeleteConfirm(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final strings = context.strings;
  final confirmed = await showCenterPopup<bool>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      padding: const EdgeInsets.all(AppTokens.spaceL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.deleteConfirmTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceM),
          Text(strings.deleteConfirmMessage,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSecondary)),
          const SizedBox(height: AppTokens.spaceL),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              const SizedBox(width: AppTokens.spaceS),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(strings.delete,
                    style: const TextStyle(color: AppTokens.favorite)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) {
    await ref.read(mediaRepositoryProvider).deleteSong(song.id);
  }
}

/// 编辑歌曲信息弹窗。
Future<void> showEditSongDialog(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final strings = context.strings;
  final titleCtrl = TextEditingController(text: song.title);
  final artistCtrl = TextEditingController(text: song.artist ?? '');
  final albumCtrl = TextEditingController(text: song.album ?? '');
  final genreCtrl = TextEditingController(text: song.genre ?? '');

  await showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      padding: const EdgeInsets.all(AppTokens.spaceL),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.edit, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceM),
            _field(context, strings.songTitle, titleCtrl),
            _field(context, strings.songArtist, artistCtrl),
            _field(context, strings.songAlbum, albumCtrl),
            _field(context, strings.songGenre, genreCtrl),
            const SizedBox(height: AppTokens.spaceL),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: AppTokens.spaceS),
                TextButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    ref.read(mediaRepositoryProvider).updateSong(
                          song.id,
                          title: title,
                          artist: _blankToNull(artistCtrl.text),
                          album: _blankToNull(albumCtrl.text),
                          genre: _blankToNull(genreCtrl.text),
                        );
                    Navigator.of(context).pop();
                  },
                  child: Text(strings.save),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

Widget _field(BuildContext context, String label, TextEditingController ctrl) {
  return Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceM),
    child: TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

/// 打标签选择面板（居中弹窗）：显示全部标签，点击切换打标状态。
/// [songIds] 支持单曲（1 个 id）与批量（多个 id，勾选状态取交集）。
Future<void> showTagPicker(BuildContext context, WidgetRef ref, Song song) async {
  await showCenterPopup<void>(
    context,
    child: _TagPickerSheet(songIds: [song.id]),
  );
}

/// 批量打标签面板。
Future<void> showBatchTagPicker(
  BuildContext context,
  WidgetRef ref, {
  required List<int> songIds,
}) async {
  await showCenterPopup<void>(
    context,
    child: _TagPickerSheet(songIds: songIds),
  );
}

class _TagPickerSheet extends ConsumerWidget {
  const _TagPickerSheet({required this.songIds});

  final List<int> songIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final tagRepo = ref.read(tagRepositoryProvider);
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final map = ref.watch(songTagMapProvider).value ?? const <int, List<int>>{};
    // 当前所有选中歌曲都打上的标签（交集）；为空集合则全部未勾选。
    final Set<int> current;
    {
      var shared = <int>{};
      for (var i = 0; i < songIds.length; i++) {
        final ids = map[songIds[i]] ?? const <int>[];
        shared = i == 0
            ? ids.toSet()
            : shared.intersection(ids.toSet());
      }
      current = shared;
    }

    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceM),
              child: Row(
                children: [
                  Text(strings.tagSong,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  _tagActionButton(
                    icon: CupertinoIcons.add,
                    label: strings.newTag,
                    onPressed: () async {
                      await showCreateTagDialog(context, ref);
                    },
                  ),
                ],
              ),
            ),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceM),
                child: Text(strings.empty,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in tags)
                      CheckboxListTile(
                        value: current.contains(tag.id),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Color(tag.color).withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppTokens.spaceS),
                            Text(tag.name),
                          ],
                        ),
                        onChanged: (checked) async {
                          await tagRepo.setTagOnSongs(songIds, tag.id,
                              assign: checked ?? false);
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceS),
          ],
        ),
      ),
    );
  }
}

/// 「标签 ▾」筛选面板：返回选中的标签 id（null 表示取消选择）。
Future<int?> showTagFilterSheet(
  BuildContext context,
  WidgetRef ref, {
  int? selectedTagId,
}) {
  return showCenterPopup<int>(
    context,
    child: _TagFilterSheet(selectedTagId: selectedTagId),
  );
}

class _TagFilterSheet extends ConsumerWidget {
  const _TagFilterSheet({this.selectedTagId});

  final int? selectedTagId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];

    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceM),
              child: Row(
                children: [
                  Text(strings.tabTags,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  _tagActionButton(
                    icon: CupertinoIcons.gear_alt,
                    label: strings.manageTags,
                    onPressed: () async {
                      await showManageTagsDialog(context, ref);
                    },
                  ),
                  const SizedBox(width: AppTokens.spaceXs),
                  _tagActionButton(
                    icon: CupertinoIcons.add,
                    label: strings.newTag,
                    onPressed: () async {
                      await showCreateTagDialog(context, ref);
                    },
                  ),
                ],
              ),
            ),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceM),
                child: Text(strings.empty,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      dense: true,
                      leading: Icon(
                        selectedTagId == null
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color: selectedTagId == null
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSecondary,
                      ),
                      title: Text(strings.tabAll),
                      onTap: () => Navigator.of(context).pop(-1),
                    ),
                    for (final tag in tags)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          selectedTagId == tag.id
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          color: selectedTagId == tag.id
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSecondary,
                        ),
                        title: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Color(tag.color).withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppTokens.spaceS),
                            Text(tag.name),
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop(tag.id),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceS),
          ],
        ),
      ),
    );
  }
}

/// 弹框头部紧凑操作按钮：居中弹框宽度有限，避免长文本溢出。
Widget _tagActionButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
    ),
  );
}

/// 新建标签弹窗。
Future<void> showCreateTagDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final nameCtrl = TextEditingController();
  final colors = [0xFF2E7D32, 0xFFF57C00, 0xFF9C27B0, 0xFF0A84FF, 0xFFFF2D55];
  var pickedColor = colors.first;

  await showCenterPopup<void>(
    context,
    child: StatefulBuilder(
      builder: (dialogCtx, setState) => GlassOverlay(
        radius: AppTokens.radiusL,
        padding: const EdgeInsets.all(AppTokens.spaceL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.newTag, style: Theme.of(dialogCtx).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceM),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(isDense: true),
            ),
            const SizedBox(height: AppTokens.spaceM),
            Row(
              children: [
                for (final c in colors)
                  GestureDetector(
                    onTap: () => setState(() => pickedColor = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: AppTokens.spaceS),
                      decoration: BoxDecoration(
                        color: Color(c).withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: pickedColor == c
                            ? Border.all(color: Theme.of(dialogCtx).colorScheme.onSurface, width: 2)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceL),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: AppTokens.spaceS),
                TextButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    ref.read(tagRepositoryProvider).createTag(name, color: pickedColor);
                    Navigator.of(dialogCtx).pop();
                  },
                  child: Text(strings.save),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 管理标签弹窗：重命名 / 删除。
Future<void> showManageTagsDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await showCenterPopup<void>(
    context,
    child: const _ManageTagsSheet(),
  );
}

class _ManageTagsSheet extends ConsumerWidget {
  const _ManageTagsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final tagRepo = ref.read(tagRepositoryProvider);
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];

    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceM),
              child: Text(strings.manageTags,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceM),
                child: Text(strings.empty,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in tags)
                      ListTile(
                        dense: true,
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(tag.color).withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(tag.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(CupertinoIcons.pencil, size: 18),
                              onPressed: () async {
                                final newName =
                                    await _promptRename(context, tag.name, strings);
                                if (newName != null && newName.trim().isNotEmpty) {
                                  await tagRepo.renameTag(tag.id, newName.trim());
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.trash, size: 18,
                                  color: AppTokens.favorite),
                              onPressed: () => tagRepo.deleteTag(tag.id),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceS),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptRename(
  BuildContext context,
  String initial,
  AppStrings strings,
) async {
  final controller = TextEditingController(text: initial);
  return showCenterPopup<String>(
    context,
    child: GlassOverlay(
      radius: AppTokens.radiusL,
      padding: const EdgeInsets.all(AppTokens.spaceL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(isDense: true),
          ),
          const SizedBox(height: AppTokens.spaceM),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(strings.save),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}