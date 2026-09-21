import 'package:flutter/material.dart' show Offset, Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/audio_engine_provider.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/services/desktop_lyrics/desktop_lyrics_controller.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_bar_messenger.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_window_api.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_window_desktop.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/fake_lyric_window_api.dart';
import 'support/in_memory_preferences_store.dart';

void main() {
  group('LyricBarMessenger 编解码', () {
    test('TC-01 状态消息往返保真', () {
      const msg = LyricBarStateMessage(
        hasTrack: true,
        title: 'T',
        artist: 'A',
        currentText: '行',
        nextText: 'next',
      );
      final decoded = LyricBarMessenger.decodeState(
        LyricBarMessenger.encodeState(msg),
      );
      expect(decoded, msg);
    });

    test('TC-01 缺字段解码回默认值', () {
      final decoded = LyricBarMessenger.decodeState({'hasTrack': true});
      expect(decoded.hasTrack, isTrue);
      expect(decoded.title, '');
      expect(decoded.currentText, isNull);
      // 非法参数整体回退「未在播放」。
      expect(
        LyricBarMessenger.decodeState('bad'),
        const LyricBarStateMessage(hasTrack: false),
      );
    });

    test('TC-02 回传事件编解码', () {
      expect(
        LyricBarMessenger.decodeHostEvent('closed', null),
        isA<LyricBarClosedEvent>(),
      );
      // 引擎就绪事件（无参数）。
      expect(
        LyricBarMessenger.decodeHostEvent('ready', null),
        isA<LyricBarReadyEvent>(),
      );
      final pos = LyricBarMessenger.decodeHostEvent('position', {
        'x': 1.0,
        'y': 2.0,
      });
      expect((pos as LyricBarPositionSavedEvent).position, const Offset(1, 2));
      // 非法 / 未知消息返回 null。
      expect(
        LyricBarMessenger.decodeHostEvent('position', {'x': 'bad'}),
        isNull,
      );
      expect(LyricBarMessenger.decodeHostEvent('other', null), isNull);
    });

    test('TC-03 窗口配置往返保真；损坏输入回退默认', () {
      const cfg = LyricWindowConfig(
        localeCode: 'ja',
        dark: true,
        fontTier: DesktopLyricsFontSize.large,
        offset: Offset(5, 6),
        initialState: LyricBarStateMessage(hasTrack: true, title: 'x'),
      );
      final decoded = LyricBarMessenger.decodeConfig(
        LyricBarMessenger.encodeConfig(cfg),
      );
      expect(decoded, cfg);
      expect(
        LyricBarMessenger.decodeConfig('{broken'),
        const LyricWindowConfig(),
      );
    });
  });

  group('歌词条几何', () {
    test('TC-04 尺寸随字号档位单调递增', () {
      final small = lyricBarWindowSize(DesktopLyricsFontSize.small);
      final medium = lyricBarWindowSize(DesktopLyricsFontSize.medium);
      final large = lyricBarWindowSize(DesktopLyricsFontSize.large);
      expect(small.width, lessThan(medium.width));
      expect(medium.width, lessThan(large.width));
      expect(small.height, lessThan(medium.height));
      expect(medium.height, lessThan(large.height));
    });

    test('TC-05 默认位置：底部居中偏下', () {
      final p = defaultLyricBarPosition(
        const Size(720, 96),
        const Size(1920, 1080),
      );
      expect(p.dx, 600); // (1920-720)/2 水平居中
      expect(p.dy, 1080 - 96 - 96); // 贴底偏上
    });

    test('TC-06 位置钳制：出屏拉回可见区域', () {
      final p = clampLyricBarPosition(
        const Offset(-50, 2000),
        const Size(720, 96),
        const Size(1920, 1080),
      );
      expect(p.dx, 0);
      expect(p.dy, 1080 - 96);
      // 小屏容错：窗口大于屏幕时不产生负偏移。
      final q = clampLyricBarPosition(
        const Offset(10, 10),
        const Size(720, 96),
        const Size(500, 80),
      );
      expect(q, Offset.zero);
    });
  });

  group('DesktopLyricsController 编排', () {
    const lrc =
        '[00:01] First line\n[00:05] Second line\n'
        '[00:09] \n[00:13] Last line\n';

    // 冲刷异步链（偏好载入 / 引擎流 / Riverpod 调度级联）。
    // pump() 只等当前 pendingFuture，不级联刷新，因此循环冲刷。
    Future<void> settle(ProviderContainer container) async {
      for (var i = 0; i < 8; i++) {
        await container.pump();
        await Future<void>.delayed(Duration.zero);
      }
    }

    Track track(String id, {String? title, String? artist}) => Track(
      id: id,
      title: title ?? 'Song $id',
      artist: artist,
      filePath: '/test/$id.mp3',
    );

    ProviderContainer makeContainer({
      AppPreferences prefs = const AppPreferences(desktopLyricsEnabled: true),
      FakeDataLayer? db,
      required FakeAudioEngine engine,
      required InMemoryPreferencesStore store,
      required FakeLyricWindowApi api,
    }) {
      final container = ProviderContainer(
        overrides: [
          ...fakeDataLayerOverrides(db ?? FakeDataLayer()),
          audioEngineProvider.overrideWithValue(engine),
          preferencesStoreProvider.overrideWithValue(store),
          lyricWindowApiProvider.overrideWithValue(api),
        ],
      );
      // Riverpod 3 默认 autoDispose：挂持久 listener 保活控制器
      // （对应生产中 MyApp 的 ref.watch）。
      container.listen(desktopLyricsControllerProvider, (_, _) {});
      return container;
    }

    test('TC-07 开关=开：启动自动恢复并携带字号/位置/初始态', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(
          desktopLyricsEnabled: true,
          desktopLyricsFontSize: DesktopLyricsFontSize.large,
          desktopLyricsOffset: Offset(30, 40),
        ),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      expect(api.openState, isTrue);
      expect(api.openedConfigs, hasLength(1));
      final config = api.openedConfigs.single;
      expect(config.fontTier, DesktopLyricsFontSize.large);
      expect(config.offset, const Offset(30, 40));
      expect(config.initialState.hasTrack, isFalse); // 未播放
      expect(api.closeCount, 0);
      // 启动恢复即推当前状态（不依赖子引擎就绪后才有首帧数据）。
      expect(api.pushedStates, isNotEmpty);
      expect(api.pushedStates.first, config.initialState);
    });

    test('TC-08 开关=关：不打开窗口', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore();
      final container = makeContainer(
        prefs: const AppPreferences(desktopLyricsEnabled: false),
        engine: engine,
        store: store,
        api: api,
      );
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      expect(api.openState, isFalse);
      expect(api.openedConfigs, isEmpty);
    });

    test('TC-08 偏好置关 → 关闭窗口', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);
      expect(api.openState, isTrue);

      await container
          .read(preferencesProvider.notifier)
          .setDesktopLyricsEnabled(false);
      await settle(container);

      expect(api.openState, isFalse);
      expect(api.closeCount, 1);
      expect(store.lastSaved.desktopLyricsEnabled, isFalse);
    });

    test('TC-09 偏好置开 → 打开窗口', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore();
      final container = makeContainer(
        prefs: const AppPreferences(desktopLyricsEnabled: false),
        engine: engine,
        store: store,
        api: api,
      );
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      await container
          .read(preferencesProvider.notifier)
          .setDesktopLyricsEnabled(true);
      await settle(container);

      expect(api.openState, isTrue);
      expect(store.lastSaved.desktopLyricsEnabled, isTrue);
      // open 完成即推当前状态（TC-29 前半：不依赖行变化）。
      expect(api.pushedStates, isNotEmpty);
    });

    test('TC-29 ready 握手：引擎就绪后补推当前态；关闭后不再推送', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);
      expect(api.openState, isTrue);

      // 引擎就绪 → 恰好补推一次（覆盖冷启动窗口期被丢弃的推送）。
      final before = api.pushedStates.length;
      api.emitReady();
      await settle(container);
      expect(api.pushedStates.length, before + 1);
      expect(api.pushedStates.last.hasTrack, isFalse); // 未播放占位

      // 开关已关 → ready 不再触发推送。
      await container
          .read(preferencesProvider.notifier)
          .setDesktopLyricsEnabled(false);
      await settle(container);
      expect(api.openState, isFalse);

      final afterClose = api.pushedStates.length;
      api.emitReady();
      await settle(container);
      expect(api.pushedStates.length, afterClose);
    });

    test('TC-10 ✕ 回传 → 偏好置关并关闭窗口', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);
      expect(api.openState, isTrue);

      api.emitClosed();
      await settle(container);

      expect(store.lastSaved.desktopLyricsEnabled, isFalse);
      expect(api.openState, isFalse);
      expect(api.closeCount, greaterThanOrEqualTo(1));
    });

    test('TC-11 位置回传 → 写入偏好', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      api.emitPosition(const Offset(12, 34));
      await settle(container);

      expect(store.lastSaved.desktopLyricsOffset, const Offset(12, 34));
    });

    test('TC-12/13 行变化推送当前句+下一句；同行进度不推送', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final db = FakeDataLayer();
      await db.lyricsRepository.saveLyrics(1, lrc);
      final container = makeContainer(
        engine: engine,
        store: store,
        api: api,
        db: db,
      );
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      // 播放曲目 1（id 数字 ↔ songId 1）。
      container.read(audioControllerProvider.notifier).play(track('1'));
      await settle(container);
      // 切歌即推送一次（hasTrack 变化，尚未到首行）。
      expect(api.pushedStates, isNotEmpty);
      expect(api.pushedStates.last.hasTrack, isTrue);
      expect(api.pushedStates.last.currentText, isNull);

      // 推进到第 1 行。
      engine.emitPosition(const Duration(seconds: 2));
      await settle(container);
      expect(api.pushedStates.last.currentText, 'First line');
      expect(api.pushedStates.last.nextText, 'Second line');

      // 同行内多次推进 → 消息 == 去重，不推送。
      final before = api.pushedStates.length;
      engine.emitPosition(const Duration(milliseconds: 2500));
      await settle(container);
      expect(api.pushedStates.length, before);

      // seek 到第 2 行 → 立即推送。
      engine.emitPosition(const Duration(seconds: 6));
      await settle(container);
      expect(api.pushedStates.length, before + 1);
      expect(api.pushedStates.last.currentText, 'Second line');
    });

    test('TC-14/15 无歌词 → current=null 且携带歌名/歌手；切歌立即切换', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final container = makeContainer(engine: engine, store: store, api: api);
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      container
          .read(audioControllerProvider.notifier)
          .play(track('9', title: 'No Lyrics Song', artist: 'Artist X'));
      await settle(container);

      final last = api.pushedStates.last;
      expect(last.hasTrack, isTrue);
      expect(last.title, 'No Lyrics Song');
      expect(last.artist, 'Artist X');
      expect(last.currentText, isNull);
    });

    test('TC-17 空文本行 → 间奏占位（current=""）', () async {
      final api = FakeLyricWindowApi();
      final engine = FakeAudioEngine();
      final store = InMemoryPreferencesStore(
        const AppPreferences(desktopLyricsEnabled: true),
      );
      final db = FakeDataLayer();
      await db.lyricsRepository.saveLyrics(1, lrc);
      final container = makeContainer(
        engine: engine,
        store: store,
        api: api,
        db: db,
      );
      addTearDown(container.dispose);

      container.read(desktopLyricsControllerProvider);
      await settle(container);

      container.read(audioControllerProvider.notifier).play(track('1'));
      await settle(container);
      engine.emitPosition(const Duration(seconds: 10));
      await settle(container);

      expect(api.pushedStates.last.currentText, '');
      // 下一句回到歌词行。
      expect(api.pushedStates.last.nextText, 'Last line');
    });
  });
}
