import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/data/app_providers.dart';
import 'package:zeromusic/services/import/import_io.dart';
import 'package:zeromusic/services/import/import_providers.dart';
import 'package:zeromusic/services/import/import_service.dart';
import 'package:zeromusic/services/import/import_source.dart';
import 'package:zeromusic/services/import/import_task.dart';

import 'support/fake_data_layer.dart';

/// 选择器：返回预先给定的文件列表。
class _FakePicker implements ImportFilePicker {
  _FakePicker(this.files);

  final List<PickedAudioFile> files;
  int calls = 0;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    calls++;
    return files;
  }
}

/// 存储：模拟拷贝/保存封面，记录调用顺序。
class _FakeStore implements ImportFileStore {
  final List<String> copiedNames = [];
  String? savedExtension;

  @override
  Future<String> copy(PickedAudioFile file) async {
    copiedNames.add(file.name);
    return '/imported/${file.name}';
  }

  @override
  Future<String?> saveCover(Uint8List bytes, String extension) async {
    savedExtension = extension;
    return '/covers/cover.png';
  }
}

/// 立即完成的元数据读取器。
class _FakeExtractor implements ImportMetadataExtractor {
  _FakeExtractor(this.meta);

  final ImportAudioMetadata meta;
  final List<String> paths = [];

  @override
  Future<ImportAudioMetadata> extract(String filePath) async {
    paths.add(filePath);
    return meta;
  }
}

/// 门控读取器：首个调用需要手动完成，用于观测「第二首排队」。
class _GatedExtractor implements ImportMetadataExtractor {
  final Completer<ImportAudioMetadata> gate = Completer();

  @override
  Future<ImportAudioMetadata> extract(String filePath) async {
    return gate.future;
  }
}

/// 首次拷贝失败、重试成功。
class _FlakyStore implements ImportFileStore {
  int copies = 0;

  @override
  Future<String> copy(PickedAudioFile file) async {
    copies++;
    if (copies == 1) throw const ImportException('disk full');
    return '/imported/${file.name}';
  }

  @override
  Future<String?> saveCover(Uint8List bytes, String extension) async => null;
}

void main() {
  late FakeDataLayer layer;
  late ProviderContainer container;

  const defaultMeta =
      ImportAudioMetadata(title: '示例歌曲', artist: '歌手', durationMs: 180000);

  List<Override> overrides({
    ImportFilePicker? picker,
    ImportFileStore? store,
    ImportMetadataExtractor? extractor,
  }) {
    return [
      importFilePickerProvider.overrideWithValue(picker ?? _FakePicker(const [])),
      importFileStoreProvider.overrideWithValue(store ?? _FakeStore()),
      importMetadataExtractorProvider
          .overrideWithValue(extractor ?? _FakeExtractor(defaultMeta)),
      mediaRepositoryProvider.overrideWithValue(layer.mediaRepository),
      tagRepositoryProvider.overrideWithValue(layer.tagRepository),
    ];
  }

  setUp(() {
    layer = FakeDataLayer(seed: const []);
  });

  void startContainer(List<Override> ov) {
    container = ProviderContainer(overrides: ov);
    addTearDown(container.dispose);
  }

  ImportState state() => container.read(importControllerProvider);
  ImportService service() => container.read(importControllerProvider.notifier);

  test('本机导入：拷贝→读元数据→入库并打「来源:本地文件」标签', () async {
    final picker = _FakePicker(
      const [PickedAudioFile(name: 'a.mp3', path: '/src/a.mp3')],
    );
    final store = _FakeStore();
    final extractor = _FakeExtractor(defaultMeta);
    startContainer(overrides(picker: picker, store: store, extractor: extractor));

    await service().startLocalImport();
    final queued = state();
    expect(queued.tasks, hasLength(1));
    expect(queued.tasks.first.source, ImportSource.localFile);
    expect(queued.tasks.first.sourcePath, '/src/a.mp3');

    await pumpEventQueue();

    final done = state().tasks.single;
    expect(done.status, ImportTaskStatus.completed);
    expect(done.targetPath, '/imported/a.mp3');
    expect(done.progress, 1);
    expect(state().allDone, isTrue);
    expect(store.copiedNames, ['a.mp3']);
    expect(extractor.paths, ['/imported/a.mp3']);

    // 入库 + 来源标签关联。
    final songs = layer.mediaRepository.songs;
    expect(songs, hasLength(1));
    final song = songs.single;
    expect(song.title, '示例歌曲');
    expect(song.artist, '歌手');
    expect(song.durationMs, 180000);
    expect(song.filePath, '/imported/a.mp3');
    final tagIndex = layer.tagRepository.tags
        .indexWhere((t) => t.name == ImportSource.localFile.sourceTag);
    expect(tagIndex, isNot(-1));
    final tagId = layer.tagRepository.tags[tagIndex].id;
    expect(layer.songTagLinks[song.id], contains(tagId));
  });

  test('用户取消选择：不产生任何任务', () async {
    startContainer(overrides(picker: _FakePicker(const [])));

    await service().startLocalImport();

    expect(state().tasks, isEmpty);
    expect(layer.mediaRepository.songs, isEmpty);
  });

  test('批量按顺序处理：一次仅一个，前一个完成后才开始下一个', () async {
    final picker = _FakePicker(const [
      PickedAudioFile(name: 'a.mp3', path: '/src/a.mp3'),
      PickedAudioFile(name: 'b.mp3', path: '/src/b.mp3'),
    ]);
    final store = _FakeStore();
    final gated = _GatedExtractor();
    startContainer(overrides(picker: picker, store: store, extractor: gated));

    await service().startLocalImport();

    // 第一个导入中（门控未放行），第二个排队，拷贝只发生了第一次。
    final mid = state();
    expect(mid.tasks[0].status, ImportTaskStatus.importing);
    expect(mid.tasks[1].status, ImportTaskStatus.queued);
    expect(store.copiedNames, ['a.mp3']);

    gated.gate.complete(defaultMeta);
    await pumpEventQueue();

    final end = state();
    expect(end.tasks.every((t) => t.status == ImportTaskStatus.completed), isTrue);
    expect(store.copiedNames, ['a.mp3', 'b.mp3']);
    expect(layer.mediaRepository.songs, hasLength(2));
  });

  test('失败置为 failed 保留源路径，重试后成功入库', () async {
    final picker = _FakePicker(
      const [PickedAudioFile(name: 'a.mp3', path: '/src/a.mp3')],
    );
    final store = _FlakyStore();
    startContainer(overrides(picker: picker, store: store));

    await service().startLocalImport();
    await pumpEventQueue();

    final failed = state().tasks.single;
    expect(failed.status, ImportTaskStatus.failed);
    expect(failed.error, contains('disk full'));
    expect(failed.sourcePath, '/src/a.mp3'); // 供重试
    expect(failed.targetPath, isNull);
    expect(state().allDone, isFalse);

    service().retry(failed.id);
    // 重试立即进入导入中（无其他占用）。
    expect(state().tasks.single.status, ImportTaskStatus.importing);
    await pumpEventQueue();

    final done = state().tasks.single;
    expect(done.status, ImportTaskStatus.completed);
    expect(layer.mediaRepository.songs, hasLength(1));
    expect(state().allDone, isTrue);
  });

  test('封面写入磁盘并随歌曲入库', () async {
    final extractor = _FakeExtractor(
      ImportAudioMetadata(
        title: '带封面',
        coverBytes: Uint8List.fromList([1, 2, 3, 4]),
        coverMime: 'image/png',
      ),
    );
    final picker = _FakePicker(
      const [PickedAudioFile(name: 'a.mp3', path: '/src/a.mp3')],
    );
    final store = _FakeStore();
    startContainer(
      overrides(picker: picker, store: store, extractor: extractor),
    );

    await service().startLocalImport();
    await pumpEventQueue();

    final task = state().tasks.single;
    expect(task.status, ImportTaskStatus.completed);
    expect(task.coverPath, '/covers/cover.png');
    expect(store.savedExtension, 'png');
    expect(layer.mediaRepository.songs.single.coverPath, '/covers/cover.png');
  });
}