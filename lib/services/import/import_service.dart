import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_providers.dart';
import 'import_io.dart';
import 'import_source.dart';
import 'import_task.dart';

/// 导入页整体状态：任务列表 + 派生标志位。
class ImportState {
  const ImportState({this.tasks = const []});

  final List<ImportTask> tasks;

  /// 是否有正在导入的任务（正在处理中，排队的不算）。
  bool get hasActive =>
      tasks.any((t) => t.status == ImportTaskStatus.importing);

  /// 至少有一条任务，且全部完成（驱动「全部导入完成」动画）。
  bool get allDone => tasks.isNotEmpty && tasks.every((t) => t.isCompleted);

  ImportState copyWith({List<ImportTask>? tasks}) {
    return ImportState(tasks: tasks ?? this.tasks);
  }
}

/// 导入统一调度：顺序队列，一次处理一个文件。
///
/// 流水线：拷贝文件 → 读取元数据 → 保存封面 → 写入媒体库 → 打「来源:xxx」内置标签。
/// 文件层 IO 经 [importFilePickerProvider] / [importFileStoreProvider] /
/// [importMetadataExtractorProvider] 注入，测试可整体替换为内存假实现。
class ImportService extends Notifier<ImportState> {
  /// 已选择文件的登记（任务重试时仍需源路径）。
  final Map<String, PickedAudioFile> _pickedFiles = {};
  int _seq = 0;

  @override
  ImportState build() => const ImportState();

  String _newId() => 'import-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// 打开本机文件选择器并开始导入（选择多文件 → 批量入队）。
  Future<void> startLocalImport() async {
    final picked =
        await ref.read(importFilePickerProvider).pickAudioFiles();
    if (picked.isEmpty) return;
    _enqueue(picked);
  }

  void _enqueue(List<PickedAudioFile> files) {
    final tasks = List<ImportTask>.of(state.tasks);
    for (final f in files) {
      final id = _newId();
      _pickedFiles[id] = f;
      tasks.add(
        ImportTask(
          id: id,
          fileName: f.name,
          source: ImportSource.localFile,
          sourcePath: f.path,
        ),
      );
    }
    state = ImportState(tasks: tasks);
    _runNext();
  }

  /// 失败任务重试（重新排队并走完整流水线）。
  void retry(String id) {
    if (!ref.mounted) return;
    final idx = state.tasks.indexWhere((t) => t.id == id);
    if (idx < 0 || state.tasks[idx].status != ImportTaskStatus.failed) return;
    final tasks = List<ImportTask>.of(state.tasks);
    tasks[idx] = tasks[idx].copyWith(
      status: ImportTaskStatus.queued,
      progress: 0,
      error: null,
    );
    state = ImportState(tasks: tasks);
    _runNext();
  }

  Future<void> _runNext() async {
    if (!ref.mounted) return;
    if (state.hasActive) return;
    final idx = state.tasks.indexWhere((t) => t.status == ImportTaskStatus.queued);
    if (idx < 0) return;
    final tasks = List<ImportTask>.of(state.tasks);
    tasks[idx] = tasks[idx].copyWith(
      status: ImportTaskStatus.importing,
      progress: 0.05,
    );
    state = ImportState(tasks: tasks);
    unawaited(_process(tasks[idx].id));
  }

  void _update(
    String id, {
    double? progress,
    ImportTaskStatus? status,
    String? targetPath,
    String? coverPath,
    bool? clearPaths,
    String? error,
  }) {
    if (!ref.mounted) return;
    final idx = state.tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final tasks = List<ImportTask>.of(state.tasks);
    final task = tasks[idx];
    tasks[idx] = task.copyWith(
      progress: progress,
      status: status,
      targetPath: clearPaths == true ? null : targetPath,
      coverPath: clearPaths == true ? null : coverPath,
      error: error,
    );
    state = ImportState(tasks: tasks);
  }

  Future<void> _process(String id) async {
    try {
      final picked = _pickedFiles[id]!;
      final source =
          state.tasks.firstWhere((t) => t.id == id).source;
      final store = ref.read(importFileStoreProvider);

      _update(id, progress: 0.2);
      final targetPath = await store.copy(picked);

      _update(id, progress: 0.45);
      final meta = await ref
          .read(importMetadataExtractorProvider)
          .extract(targetPath);

      String? coverPath;
      final cover = meta.coverBytes;
      if (cover != null && cover.isNotEmpty) {
        _update(id, progress: 0.6);
        coverPath = await store.saveCover(cover, _coverExtension(meta.coverMime));
      }

      _update(id, progress: 0.8);
      final songId = await ref.read(mediaRepositoryProvider).addSong(
            title: meta.title ?? picked.name,
            artist: meta.artist,
            album: meta.album,
            genre: meta.genre,
            durationMs: meta.durationMs,
            filePath: targetPath,
            coverPath: coverPath,
          );
      final tagId = await ref.read(tagRepositoryProvider).createTag(source.sourceTag);
      await ref
          .read(tagRepositoryProvider)
          .setTagOnSong(songId, tagId, assign: true);

      _update(
        id,
        progress: 1,
        status: ImportTaskStatus.completed,
        targetPath: targetPath,
        coverPath: coverPath,
      );
    } catch (e) {
      // 失败：保留源路径供重试，清空此前的目标/封面路径。
      _update(
        id,
        progress: 1,
        status: ImportTaskStatus.failed,
        clearPaths: true,
        error: e.toString(),
      );
    } finally {
      _runNext();
    }
  }

  /// 封面 MIME → 文件扩展名。
  String _coverExtension(String? mime) {
    return switch (mime) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
  }
}