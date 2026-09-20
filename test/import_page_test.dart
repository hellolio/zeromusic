import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:zeromusic/services/import/import_io.dart';
import 'package:zeromusic/services/import/import_source.dart';
import 'package:zeromusic/ui/pages/import/import_source_card.dart';
import 'package:zeromusic/ui/pages/import/import_task_tile.dart';

import 'helpers.dart';
import 'support/fake_data_layer.dart';

class _ImmediatePicker implements ImportFilePicker {
  _ImmediatePicker([this.files = const []]);

  final List<PickedAudioFile> files;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => files;
}

class _ImmediateStore implements ImportFileStore {
  int copies = 0;

  @override
  Future<String> copy(PickedAudioFile file) async {
    copies++;
    return '/imported/${file.name}';
  }

  @override
  Future<String?> saveCover(Uint8List bytes, String extension) async => null;
}

/// 首次拷贝失败、重试成功的存储。
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

class _ImmediateExtractor implements ImportMetadataExtractor {
  const _ImmediateExtractor();

  @override
  Future<ImportAudioMetadata> extract(String filePath) async =>
      const ImportAudioMetadata(
        title: '导测试曲',
        artist: '测试歌手',
        durationMs: 120000,
      );
}

void main() {
  Future<void> pumpImportPage(
    WidgetTester tester, {
    FakeDataLayer? layer,
    ImportFilePicker? picker,
    ImportFileStore? store,
    ImportMetadataExtractor? extractor,
    Size size = const Size(800, 1400),
  }) async {
    final dataLayer = layer ?? FakeDataLayer();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final overrides = <Override>[
      importFilePickerProvider
          .overrideWithValue(picker ?? _ImmediatePicker()),
      importFileStoreProvider.overrideWithValue(store ?? _ImmediateStore()),
      importMetadataExtractorProvider
          .overrideWithValue(extractor ?? const _ImmediateExtractor()),
      ...fakeDataLayerOverrides(dataLayer),
    ];

    await tester.pumpWidget(wrapApp(overrides: overrides));
    await tester.pumpAndSettle();

    // 切到导入页（底栏第二项）。
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('移动端：来源卡片全部渲染', (tester) async {
    await pumpImportPage(tester);

    expect(find.byType(ImportSourceCard), findsNWidgets(6));
    for (final label in ['Local files', 'Cloud', 'Bluetooth', 'Wi-Fi', 'Mac', 'Windows']) {
      expect(find.text(label), findsOneWidget);
    }
    // 空态提示（云下载图标 + 文案）已按需求移除：无任务时不再显示占位内容。
    expect(find.text('Pick a source below to start importing'), findsNothing);
    expect(find.byIcon(CupertinoIcons.cloud_download), findsNothing);
  });

  testWidgets('桌面端：显示全部来源卡片', (tester) async {
    await pumpImportPage(tester, size: const Size(1400, 900));

    expect(find.byType(ImportSourceCard), findsNWidgets(6));
    for (final label in [
      'Local files',
      'Cloud',
      'Bluetooth',
      'Wi-Fi',
      'Mac',
      'Windows',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('未支持来源：点云端弹出「即将支持」', (tester) async {
    await pumpImportPage(tester);

    await tester.tap(find.text('Cloud'));
    await tester.pumpAndSettle();

    // 卡片角标 + 弹层文案都为 "Coming soon"，且出现 OK 关闭按钮。
    expect(find.text('Coming soon'), findsWidgets);
    expect(find.text('OK'), findsOneWidget);

    // 关闭弹层。
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('本机文件：真实导入端到端（选择→入库→全部完成通知）', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    await pumpImportPage(
      tester,
      layer: layer,
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    // 完成通知弹出；完成任务行不再残留。
    expect(find.text('All imports completed'), findsOneWidget);
    expect(find.text('test.mp3'), findsNothing);
    expect(find.byType(ImportTaskTile), findsNothing);

    // 已入库：媒体库多了一首歌 + 来源标签。
    final songs = layer.mediaRepository.songs;
    expect(songs, hasLength(1));
    expect(songs.single.title, '导测试曲');
    expect(songs.single.filePath, '/imported/test.mp3');
    expect(
      layer.tagRepository.tags
          .any((t) => t.name == ImportSource.localFile.sourceTag),
      isTrue,
    );
    // 无失败项。
    expect(find.text('Import failed'), findsNothing);
  });

  testWidgets('失败可重试：显示重试并再次成功后完成通知', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    await pumpImportPage(
      tester,
      layer: layer,
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
      store: _FlakyStore(),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    expect(find.text('Import failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(layer.mediaRepository.songs, isEmpty);
    expect(find.text('All imports completed'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('All imports completed'), findsOneWidget);
    expect(find.text('Import failed'), findsNothing);
    expect(find.text('test.mp3'), findsNothing);
    expect(layer.mediaRepository.songs, hasLength(1));
  });

  testWidgets('批量选择：多文件全部导入完成通知', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    await pumpImportPage(
      tester,
      layer: layer,
      picker: _ImmediatePicker(const [
        PickedAudioFile(name: 'a.mp3', path: '/src/a.mp3'),
        PickedAudioFile(name: 'b.flac', path: '/src/b.flac'),
      ]),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    expect(find.text('All imports completed'), findsOneWidget);
    expect(find.text('a.mp3'), findsNothing);
    expect(find.text('b.flac'), findsNothing);
    expect(layer.mediaRepository.songs, hasLength(2));
  });

  testWidgets('桌面端：完成通知相对页面水平居中（不计左侧栏）', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    await pumpImportPage(
      tester,
      layer: layer,
      size: const Size(1400, 900),
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    // 左侧栏 224px，导入页位于其右侧：页面中心 ≈ (224 + 1400)/2 = 812，
    // 而非整个窗口中心 700。
    final noticeCenter =
        tester.getCenter(find.byKey(const ValueKey('allDoneNotice')));
    expect(noticeCenter.dx, closeTo(812, 12));
    expect((noticeCenter.dx - 812).abs(), lessThan((noticeCenter.dx - 700).abs()));
  });

  testWidgets('完成通知 3 秒后自动消失', (tester) async {
    await pumpImportPage(
      tester,
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    expect(find.text('All imports completed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('All imports completed'), findsNothing);
  });

  testWidgets('完成任务行立即消失并回到空状态', (tester) async {
    await pumpImportPage(
      tester,
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();

    // 完成的任务行（文件名 + 进度条）不残留；
    // 空态提示已按需求移除，回到无任务态时不显示任何占位内容。
    expect(find.byKey(const ValueKey('taskProgressBar')), findsNothing);
    expect(find.text('test.mp3'), findsNothing);
    expect(find.text('Pick a source below to start importing'), findsNothing);
    expect(find.byType(ImportTaskTile), findsNothing);
  });

  testWidgets('完成通知切页后不重新出现', (tester) async {
    await pumpImportPage(
      tester,
      picker: _ImmediatePicker(
        const [PickedAudioFile(name: 'test.mp3', path: '/src/test.mp3')],
      ),
    );

    await tester.tap(find.text('Local files'));
    await tester.pumpAndSettle();
    expect(find.text('All imports completed'), findsOneWidget);

    // 等通知消失。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('All imports completed'), findsNothing);

    // 切到播放列表再切回导入页：通知不再出现。
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    expect(find.text('All imports completed'), findsNothing);
  });
}