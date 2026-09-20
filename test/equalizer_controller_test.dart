import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/services/audio/audio_engine_provider.dart';
import 'package:zeromusic/services/audio/equalizer_controller.dart';
import 'package:zeromusic/services/audio/track.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';

import 'support/fake_audio_engine.dart';
import 'support/fake_equalizer.dart';
import 'support/in_memory_preferences_store.dart';

void main() {
  late FakeAudioEngine engine;
  late InMemoryPreferencesStore store;
  late ProviderContainer container;

  EqualizerState state() => container.read(equalizerControllerProvider);

  EqualizerController controller() =>
      container.read(equalizerControllerProvider.notifier);

  AppPreferences prefs() =>
      container.read(preferencesProvider).value ?? const AppPreferences();

  /// 让异步链路（偏好加载 / 参数就绪 / 引擎镜像）全部走完。
  Future<void> flush([int rounds = 3]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void pump({FakeEqualizer? equalizer, AppPreferences? initialPrefs}) {
    engine = FakeAudioEngine(equalizer: equalizer);
    store = InMemoryPreferencesStore(initialPrefs ?? const AppPreferences());
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        preferencesStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    // Provider 是懒加载：先触发 build（等同 App 启动时 AudioController 保活），
    // 否则后续的 flush 空转、异步链路从未开始。
    container.read(equalizerControllerProvider);
  }

  group('三态与降级', () {
    test('引擎无均衡器：supported=false，其余字段保持默认', () async {
      pump();
      expect(state().supported, isFalse);
      expect(state().ready, isFalse);
      expect(state().centerFrequencies, isEmpty);
      await flush();
      expect(state().supported, isFalse);
    });

    test('autoReady：参数就绪，频段与范围进入状态', () async {
      pump(equalizer: FakeEqualizer());
      await flush();

      final s = state();
      expect(s.supported, isTrue);
      expect(s.ready, isTrue);
      expect(s.minDecibels, -15);
      expect(s.maxDecibels, 15);
      expect(s.centerFrequencies, [60.0, 230.0, 910.0, 3600.0, 14000.0]);
      expect(s.gains, List.filled(5, 0.0));
    });

    test('autoReady=false：保持未就绪，gains 不触达 band', () async {
      final eq = FakeEqualizer(autoReady: false);
      pump(equalizer: eq);
      await flush();

      expect(state().ready, isFalse);
      for (final band in eq.bands) {
        expect(band.setGainCount, 0);
      }
    });
  });

  group('偏好 → 引擎镜像（单路径）', () {
    test('TC-EQ-06 启动即应用已持久化 enabled 与 gains', () async {
      final eq = FakeEqualizer();
      pump(
        equalizer: eq,
        initialPrefs: const AppPreferences(
          equalizerEnabled: true,
          equalizerGains: [1, 2, 3, 4, 5],
        ),
      );
      await flush();

      expect(eq.enabled, isTrue);
      expect([for (final b in eq.bands) b.gain], [1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(state().enabled, isTrue);
      expect(state().gains, [1.0, 2.0, 3.0, 4.0, 5.0]);
    });

    test('TC-EQ-11 就绪前开关缓冲、就绪后补应用 gains', () async {
      final eq = FakeEqualizer(autoReady: false);
      pump(
        equalizer: eq,
        initialPrefs: const AppPreferences(
          equalizerEnabled: true,
          equalizerGains: [5, 4, 3, 2, 1],
        ),
      );
      await flush();

      // 就绪前：enabled 已镜像（引擎激活时生效），gains 未触达 band。
      expect(eq.enabled, isTrue);
      expect(state().ready, isFalse);
      for (final band in eq.bands) {
        expect(band.setGainCount, 0);
      }

      eq.completeParameters();
      await flush();

      expect(state().ready, isTrue);
      expect([for (final b in eq.bands) b.gain], [5.0, 4.0, 3.0, 2.0, 1.0]);
    });

    test('setEnabled 只写偏好，监听器镜像引擎并回写状态', () async {
      final eq = FakeEqualizer();
      pump(equalizer: eq);
      await flush();

      await controller().setEnabled(true);
      await flush();

      expect(prefs().equalizerEnabled, isTrue);
      expect(store.lastSaved.equalizerEnabled, isTrue);
      expect(eq.enabled, isTrue);
      expect(state().enabled, isTrue);
    });

    test('setBandGain 更新偏好并镜像对应 band', () async {
      final eq = FakeEqualizer();
      pump(equalizer: eq);
      await flush();

      await controller().setBandGain(2, 7.5);
      await flush();

      expect(prefs().equalizerGains, [0.0, 0.0, 7.5, 0.0, 0.0]);
      expect(eq.bands[2].gain, 7.5);
      expect(state().gains[2], 7.5);
    });

    test('未就绪时 setBandGain 为 no-op', () async {
      pump(equalizer: FakeEqualizer(autoReady: false));
      await flush();

      await controller().setBandGain(0, 9);
      await flush();

      expect(prefs().equalizerGains, isEmpty);
    });
  });

  group('对齐与 clamp', () {
    test('TC-EQ-07 gains 短于设备段数：缺位补 0', () async {
      final eq = FakeEqualizer();
      pump(
        equalizer: eq,
        initialPrefs: const AppPreferences(equalizerGains: [1, 2, 3]),
      );
      await flush();

      expect([for (final b in eq.bands) b.gain], [1.0, 2.0, 3.0, 0.0, 0.0]);
      expect(state().gains, [1.0, 2.0, 3.0, 0.0, 0.0]);
    });

    test('TC-EQ-07 gains 长于设备段数：超长截断不越界', () async {
      final eq = FakeEqualizer();
      pump(
        equalizer: eq,
        initialPrefs:
            const AppPreferences(equalizerGains: [1, 2, 3, 4, 5, 6, 7]),
      );
      await flush();

      expect([for (final b in eq.bands) b.gain], [1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(state().gains, hasLength(5));
    });

    test('TC-EQ-08 超范围增益 clamp 到设备范围', () async {
      final eq = FakeEqualizer();
      pump(
        equalizer: eq,
        initialPrefs: const AppPreferences(equalizerGains: [100, -100]),
      );
      await flush();

      expect(eq.bands[0].gain, 15.0);
      expect(eq.bands[1].gain, -15.0);
      expect(state().gains[0], 15.0);
      expect(state().gains[1], -15.0);
    });
  });

  group('预设与重置', () {
    test('TC-EQ-04 5 段设备应用预设返回原曲线并同步引擎', () async {
      final eq = FakeEqualizer();
      pump(equalizer: eq);
      await flush();

      await controller().applyPreset(EqualizerPreset.rock);
      await flush();

      expect(prefs().equalizerGains, EqualizerPreset.rock.curve);
      expect([for (final b in eq.bands) b.gain], EqualizerPreset.rock.curve);
    });

    test('TC-EQ-05 重置为平直', () async {
      final eq = FakeEqualizer();
      pump(
        equalizer: eq,
        initialPrefs: const AppPreferences(equalizerGains: [3, 2, -1, 2, 4]),
      );
      await flush();

      await controller().reset();
      await flush();

      expect(prefs().equalizerGains, List.filled(5, 0.0));
      expect([for (final b in eq.bands) b.gain], List.filled(5, 0.0));
    });

    test('未就绪时预设/重置为 no-op', () async {
      pump(equalizer: FakeEqualizer(autoReady: false));
      await flush();

      await controller().applyPreset(EqualizerPreset.pop);
      await controller().reset();
      await flush();

      expect(prefs().equalizerGains, isEmpty);
    });
  });

  group('TC-EQ-13 预设插值（log 频率轴）', () {
    test('锚点频段返回原曲线', () {
      for (final preset in EqualizerPreset.values) {
        expect(presetGains(preset, kEqualizerPresetAnchors), preset.curve);
      }
    });

    test('单中频锚点采样命中对应曲线点', () {
      final gains = presetGains(EqualizerPreset.rock, [910]);
      expect(gains, hasLength(1));
      expect(gains.single, closeTo(EqualizerPreset.rock.curve[2], 0.05));
    });

    test('低于首锚点的频率 clamp 到首点', () {
      expect(presetGains(EqualizerPreset.rock, [30]), [3.0]);
      expect(presetGains(EqualizerPreset.rock, [20000]), [4.0]);
    });

    test('非 5 段设备：长度保持且值介于相邻曲线点之间', () {
      final gains = presetGains(
        EqualizerPreset.rock,
        [30, 60, 230, 910, 3600, 14000],
      );
      expect(gains, hasLength(6));
      expect(gains[0], 3.0); // clamp 到首点
      expect(gains[1], 3.0); // 恰在 60Hz 锚点
      // 60→230Hz 之间按 log 轴插值，结果介于 curve[0] 与 curve[1] 之间。
      final mid = presetGains(EqualizerPreset.rock, [117]).single;
      expect(mid, inInclusiveRange(2.0, 3.0));
    });
  });

  group('AudioController 保活链路', () {
    Track track(String id) =>
        Track(id: id, title: id, filePath: '/test/$id.mp3');

    test('TC-EQ-16 均衡器状态变化不得清空播放队列', () async {
      final eq = FakeEqualizer(autoReady: false);
      pump(equalizer: eq);
      final audio = container.read(audioControllerProvider.notifier);
      audio.playQueue([track('1'), track('2')], startIndex: 1);
      expect(container.read(audioControllerProvider).queue, hasLength(2));

      // 模拟 Android 首次播放后参数就绪：均衡器状态变化。
      eq.completeParameters();
      await flush();

      final s = container.read(audioControllerProvider);
      expect(container.read(equalizerControllerProvider).ready, isTrue);
      expect(s.queue, hasLength(2));
      expect(s.currentIndex, 1);

      // 播放中拨开关同样不得清队。
      await controller().setEnabled(true);
      await flush();
      expect(container.read(audioControllerProvider).queue, hasLength(2));
    });

    test('TC-EQ-17 仅经 AudioController 保活即应用持久化均衡器设置', () async {
      final eq = FakeEqualizer();
      engine = FakeAudioEngine(equalizer: eq);
      store = InMemoryPreferencesStore(
        const AppPreferences(
          equalizerEnabled: true,
          equalizerGains: [1, 2, 3, 4, 5],
        ),
      );
      container = ProviderContainer(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          preferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      // 只触发 AudioController：均衡器控制器必须经保活链路间接实例化，
      // 不得直接 read equalizerControllerProvider（否则测不到保活）。
      container.read(audioControllerProvider);
      await flush();

      expect(eq.enabled, isTrue);
      expect([for (final b in eq.bands) b.gain], [1.0, 2.0, 3.0, 4.0, 5.0]);
    });
  });

  group('生命周期守卫', () {
    test('TC-EQ-12 provider dispose 后参数完成不炸', () async {
      final eq = FakeEqualizer(autoReady: false);
      pump(equalizer: eq);
      container.dispose();

      eq.completeParameters();
      await flush();
      // 无未捕获异步异常即通过。
    });

    test('引擎替换后旧参数回调不写脏 state', () async {
      // 注入点返回可变实例，invalidate 模拟「换引擎」重建链路。
      final eq1 = FakeEqualizer(autoReady: false);
      late FakeAudioEngine currentEngine;
      currentEngine = FakeAudioEngine(equalizer: eq1);
      store = InMemoryPreferencesStore();
      container = ProviderContainer(
        overrides: [
          audioEngineProvider.overrideWith((ref) => currentEngine),
          preferencesStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await flush();
      expect(state().supported, isTrue);
      expect(state().ready, isFalse);

      // 换成不支持均衡器的新引擎并触发重建。
      currentEngine = FakeAudioEngine();
      container.invalidate(audioEngineProvider);
      await flush();
      expect(state().supported, isFalse);

      // 旧引擎迟到的参数完成不得写脏新状态。
      eq1.completeParameters();
      await flush();
      expect(state().supported, isFalse);
      expect(state().ready, isFalse);
    });
  });
}
