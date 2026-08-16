import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/audio_engine_provider.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';

import 'support/fake_audio_engine.dart';
import 'support/in_memory_preferences_store.dart';

void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  Track t(String id, {String title = ''}) {
    return Track(
      id: id,
      title: title.isEmpty ? id : title,
      filePath: '/test/$id.mp3',
    );
  }

  AudioController controller() =>
      container.read(audioControllerProvider.notifier);

  PlaybackState state() => container.read(audioControllerProvider);

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        preferencesStoreProvider
            .overrideWithValue(InMemoryPreferencesStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('play：替换队列为单曲并置为播放中，驱动引擎加载', () {
    final c = controller();
    c.play(t('1', title: '一'));

    final s = state();
    expect(s.queue, hasLength(1));
    expect(s.currentIndex, 0);
    expect(s.isPlaying, isTrue);
    expect(s.currentTrack?.title, '一');
    expect(engine.playedTracks, hasLength(1));
    expect(engine.lastPlayed?.id, '1');
  });

  test('playQueue：按给定顺序整列入队并从指定位置开始播放', () {
    final c = controller();
    c.playQueue([t('a'), t('b'), t('c')], startIndex: 1);

    final s = state();
    expect(s.queue.map((q) => q.id), ['a', 'b', 'c']);
    expect(s.currentIndex, 1);
    expect(s.currentTrack?.id, 'b');
    expect(s.isPlaying, isTrue);
    expect(engine.lastPlayed?.id, 'b');
  });

  test('playQueue：空列表为 no-op，越界索引被钳制', () {
    final c = controller();
    c.playQueue(const []);
    expect(state().queue, isEmpty);
    expect(state().isPlaying, isFalse);

    c.playQueue([t('一整首')], startIndex: -5);
    expect(state().currentIndex, 0);
    c.playQueue([t('一'), t('二')], startIndex: 99);
    expect(state().currentIndex, 1);
  });

  test('playQueue：从中间开始可 next/previous 遍历整列', () {
    final c = controller();
    c.playQueue([t('a'), t('b'), t('c')], startIndex: 1);
    expect(state().currentTrack?.id, 'b');

    c.next();
    expect(state().currentIndex, 2);
    expect(state().currentTrack?.id, 'c');
    expect(engine.lastPlayed?.id, 'c');

    c.previous();
    expect(state().currentIndex, 1);
    expect(state().currentTrack?.id, 'b');

    c.previous();
    expect(state().currentIndex, 0);
    expect(state().currentTrack?.id, 'a');
  });

  test('enqueue：追加到队尾且不打断当前播放', () {
    final c = controller();
    c.play(t('1'));

    c.enqueue(t('2'));
    c.enqueue(t('3'));

    final s = state();
    expect(s.queue, hasLength(3));
    expect(s.currentIndex, 0);
    expect(engine.playedTracks, hasLength(1), reason: '仅 play 会驱动引擎');
  });

  test('togglePlay：播放中暂停，暂停中恢复，且驱动引擎', () {
    final c = controller();
    c.play(t('1'));
    expect(state().isPlaying, isTrue);

    c.togglePlay();
    expect(state().isPlaying, isFalse);
    expect(engine.pauseCount, 1);

    c.togglePlay();
    expect(state().isPlaying, isTrue);
    expect(engine.resumeCount, 1);
  });

  test('togglePlay：无曲目时为 no-op', () {
    controller().togglePlay();
    expect(state().isPlaying, isFalse);
    expect(engine.pauseCount, 0);
    expect(engine.resumeCount, 0);
  });

  test('next/previous：环绕队列切换并重新加载引擎', () {
    final c = controller();
    c.play(t('a'));
    c.enqueue(t('b'));
    c.enqueue(t('c'));

    c.next();
    expect(state().currentIndex, 1);
    expect(state().currentTrack?.id, 'b');
    expect(engine.lastPlayed?.id, 'b');

    c.next();
    expect(state().currentIndex, 2);

    // 到队尾环绕回队首。
    c.next();
    expect(state().currentIndex, 0);
    expect(state().currentTrack?.id, 'a');

    // previous 从队首环绕到队尾。
    c.previous();
    expect(state().currentIndex, 2);
    expect(state().currentTrack?.id, 'c');
  });

  test('完成事件：自动切到下一首', () async {
    final c = controller();
    c.play(t('a'));
    c.enqueue(t('b'));

    engine.emitCompleted();
    await pumpEventQueue();
    expect(state().currentIndex, 1);
    expect(state().currentTrack?.id, 'b');
    expect(engine.lastPlayed?.id, 'b');
  });

  test('position/duration：引擎流实时镜像进状态', () async {
    final c = controller();
    c.play(t('1'));

    engine.emitDuration(const Duration(seconds: 200));
    await pumpEventQueue();
    expect(state().duration, const Duration(seconds: 200));

    engine.emitPosition(const Duration(seconds: 50));
    await pumpEventQueue();
    expect(state().position, const Duration(seconds: 50));
  });

  test('引擎错误：回退为暂停，不崩溃', () async {
    final c = controller();
    c.play(t('1'));
    expect(state().isPlaying, isTrue);

    engine.emitError(const FormatException('unsupported codec'));
    await pumpEventQueue();
    expect(state().isPlaying, isFalse);
  });

  test('seek：同步更新进度并驱动引擎', () {
    final c = controller();
    c.play(t('1'));

    c.seek(const Duration(seconds: 30));
    expect(state().position, const Duration(seconds: 30));
    expect(engine.seekCount, 1);
    expect(engine.lastSeek, const Duration(seconds: 30));
  });

  test('引擎播放源无法加载（抛错）时状态回退为暂停', () async {
    final failingEngine = _FailingEngine();
    final c = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(failingEngine),
        preferencesStoreProvider
            .overrideWithValue(InMemoryPreferencesStore()),
      ],
    );
    addTearDown(c.dispose);

    c.read(audioControllerProvider.notifier).play(t('1'));
    await Future<void>.delayed(Duration.zero);

    final s = c.read(audioControllerProvider);
    expect(s.currentTrack?.id, '1');
    expect(s.isPlaying, isFalse);
    expect(failingEngine.errorReported, isNotNull);
  });

  test('cyclePlaybackMode：顺序→循环→单曲→随机循环切换', () {
    final c = controller();
    c.play(t('1'));
    expect(state().playbackMode, PlaybackMode.loopAll);

    c.cyclePlaybackMode();
    expect(state().playbackMode, PlaybackMode.loopOne);
    c.cyclePlaybackMode();
    expect(state().playbackMode, PlaybackMode.shuffle);
    c.cyclePlaybackMode();
    expect(state().playbackMode, PlaybackMode.sequential);
    c.cyclePlaybackMode();
    expect(state().playbackMode, PlaybackMode.loopAll);
  });

  test('loopOne：播放完成自动重播本曲', () async {
    final c = controller();
    c.play(t('a'));
    c.cyclePlaybackMode();
    expect(state().playbackMode, PlaybackMode.loopOne);

    engine.emitCompleted();
    await pumpEventQueue();

    expect(state().currentIndex, 0);
    expect(state().currentTrack?.id, 'a');
    expect(state().isPlaying, isTrue);
    expect(engine.playedTracks, hasLength(2));
    expect(engine.lastPlayed?.id, 'a');
  });

  test('sequential：手动下一首不环绕，队尾停止', () async {
    final c = controller();
    c.play(t('a'));
    c.enqueue(t('b'));
    for (var i = 0; i < 3; i++) {
      c.cyclePlaybackMode();
    }
    expect(state().playbackMode, PlaybackMode.sequential);

    c.next();
    expect(state().currentIndex, 1);

    // 已到队尾：不再环绕。
    c.next();
    expect(state().currentIndex, 1);
    expect(state().currentTrack?.id, 'b');
    // 冲刷 reload 产生的 delay 中的 playing 事件，避免其后续覆盖完成事件处理结果。
    await pumpEventQueue();

    // 队尾播放完成：停止，不再切歌。
    engine.emitCompleted();
    await pumpEventQueue();
    expect(state().currentIndex, 1);
    expect(state().isPlaying, isFalse);
  });

  test('sequential：播放到队尾前完成事件仍自动切歌', () async {
    final c = controller();
    c.play(t('a'));
    c.enqueue(t('b'));
    for (var i = 0; i < 3; i++) {
      c.cyclePlaybackMode();
    }

    engine.emitCompleted();
    await pumpEventQueue();
    expect(state().currentIndex, 1);
    expect(state().currentTrack?.id, 'b');
  });

  test('shuffle：注入随机源，切换索引在界内且不等于当前', () {
    final seededContainer = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        preferencesStoreProvider
            .overrideWithValue(InMemoryPreferencesStore()),
        audioControllerProvider.overrideWith(_SeededAudioController.new),
      ],
    );
    addTearDown(seededContainer.dispose);

    final c = seededContainer.read(audioControllerProvider.notifier);
    c.playQueue([t('a'), t('b'), t('c')]);
    c.cyclePlaybackMode();
    c.cyclePlaybackMode();
    expect(
      seededContainer.read(audioControllerProvider).playbackMode,
      PlaybackMode.shuffle,
    );

    final previousIndex =
        seededContainer.read(audioControllerProvider).currentIndex;
    c.next();
    final s = seededContainer.read(audioControllerProvider);
    expect(s.currentIndex, inInclusiveRange(0, 2));
    expect(s.currentIndex, isNot(previousIndex));
  });
}

/// 固定随机种子（Random(7)）的控制器，用于确定性验证随机播放。
class _SeededAudioController extends AudioController {
  _SeededAudioController() : super(random: Random(7));
}

/// 模拟靶向平台解码失败的引擎（如 APE 在纯 just_audio 下）。
class _FailingEngine extends FakeAudioEngine {
  Object? errorReported;

  @override
  Future<void> playSource(Track track) async {
    errorReported = UnsupportedError('codec not supported');
    emitError(errorReported!);
    throw errorReported!;
  }
}