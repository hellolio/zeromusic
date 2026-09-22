import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeromusic/services/audio/equalizer_controller.dart';
import 'package:zeromusic/services/desktop_lyrics/lyric_window_api.dart';
import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/components/center_popup.dart';
import 'package:zeromusic/ui/pages/settings/equalizer_sheet.dart';
import 'package:zeromusic/ui/pages/settings/settings_page.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/fake_equalizer.dart';
import 'support/fake_lyric_window_api.dart';
import 'support/in_memory_preferences_store.dart';

void main() {
  group('SharedPreferencesStore 持久化层', () {
    test('save/load 往返保真', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesStore();

      const prefs = AppPreferences(
        themeMode: ThemeMode.dark,
        locale: Locale('ja'),
        defaultVolume: 0.35,
        backgroundEffect: BackgroundEffectLevel.vivid,
        equalizerEnabled: true,
        equalizerGains: [1.5, -2.0],
      );
      await store.save(prefs);

      final loaded = await store.load();
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.locale?.languageCode, 'ja');
      expect(loaded.defaultVolume, closeTo(0.35, 1e-9));
      expect(loaded.backgroundEffect, BackgroundEffectLevel.vivid);
      expect(loaded.equalizerEnabled, isTrue);
      expect(loaded.equalizerGains, [1.5, -2.0]);
    });

    test('空库读默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesStore();

      final loaded = await store.load();
      expect(loaded.themeMode, ThemeMode.system);
      expect(loaded.locale, isNull);
      expect(loaded.defaultVolume, 1.0);
      expect(loaded.backgroundEffect, BackgroundEffectLevel.balanced);
      expect(loaded.equalizerEnabled, isFalse);
      expect(loaded.equalizerGains, isEmpty);
    });

    test('TC-EQ-09 损坏 gains JSON 回退空列表', () async {
      SharedPreferences.setMockInitialValues({
        'prefs.equalizer.gains': '{broken',
      });
      final store = SharedPreferencesStore();

      final loaded = await store.load();
      expect(loaded.equalizerGains, isEmpty);
    });
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    InMemoryPreferencesStore? store,
    FakeAudioEngine? engine,
    Size size = const Size(800, 1200),
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapApp(
        overrides: [
          ...fakeDataLayerOverrides(FakeDataLayer()),
          ...extraOverrides,
        ],
        preferencesStore: store,
        audioEngine: engine,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  AppPreferences prefsAt(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    return container.read(preferencesProvider).value ?? const AppPreferences();
  }

  testWidgets('TC-01 设置页渲染分组与当前值', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(SettingsPage), findsOneWidget);
    for (final label in [
      'Appearance',
      'Theme',
      'Language',
      'Playback',
      'Default Volume',
      'Equalizer',
      'Background Effect',
      'About',
      'Version',
      'Open Source Licenses',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('System'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    // 均衡器：默认 FakeAudioEngine 无均衡器（不支持平台），行值降级展示。
    // 行内断言：'Coming soon' 仍被导入页使用，不能全局断言消失。
    final eqRow = find.byKey(const ValueKey('settings-equalizer'));
    expect(
      find.descendant(of: eqRow, matching: find.text('Not supported')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: eqRow, matching: find.text('Coming soon')),
      findsNothing,
    );
  });

  testWidgets('TC-02/03 主题浅色/深色切换即时生效并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    // 浅色。
    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(prefsAt(tester).themeMode, ThemeMode.light);
    expect(store.lastSaved.themeMode, ThemeMode.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    // 深色。
    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(prefsAt(tester).themeMode, ThemeMode.dark);
    expect(store.lastSaved.themeMode, ThemeMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('TC-04 桌面端主题选择用居中弹框', (tester) async {
    await pumpSettings(tester, size: const Size(1400, 900));

    await tester.tap(find.byKey(const ValueKey('settings-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(prefsAt(tester).themeMode, ThemeMode.dark);
  });

  testWidgets('TC-05 语言切中文全部文案变化并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('设置')),
      findsOneWidget,
    );
    expect(prefsAt(tester).locale?.languageCode, 'zh');
    expect(store.lastSaved.locale?.languageCode, 'zh');
  });

  testWidgets('TC-06 语言切日本語全部文案变化并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();

    expect(find.text('外観'), findsOneWidget);
    expect(find.text('既定音量'), findsOneWidget);
    expect(find.text('バージョン'), findsOneWidget);
    expect(prefsAt(tester).locale?.languageCode, 'ja');
    expect(store.lastSaved.locale?.languageCode, 'ja');
  });

  testWidgets('TC-07 启动即载入已持久化偏好', (tester) async {
    final store = InMemoryPreferencesStore(
      const AppPreferences(
        themeMode: ThemeMode.dark,
        locale: Locale('ja'),
        defaultVolume: 0.6,
      ),
    );
    await pumpSettings(tester, store: store);

    expect(find.text('ダーク'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('TC-09 默认音量滑杆联动引擎', (tester) async {
    final engine = FakeAudioEngine();
    await pumpSettings(tester, engine: engine);

    // 启动后即把默认音量应用到引擎。
    expect(engine.lastVolume, 1.0);

    final before = prefsAt(tester).defaultVolume;
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(Slider),
      const Offset(-200, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final after = prefsAt(tester).defaultVolume;
    expect(after, lessThan(before));
    expect(engine.lastVolume!, closeTo(after, 1e-9));
  });

  testWidgets('TC-10 背景效果档位切换并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    expect(prefsAt(tester).backgroundEffect, BackgroundEffectLevel.balanced);
    expect(find.text('Balanced'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-background-effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vivid'));
    await tester.pumpAndSettle();

    expect(prefsAt(tester).backgroundEffect, BackgroundEffectLevel.vivid);
    expect(store.lastSaved.backgroundEffect, BackgroundEffectLevel.vivid);
    expect(find.text('Vivid'), findsOneWidget);
  });

  testWidgets('TC-11 启动即载入已持久化背景效果档位', (tester) async {
    final store = InMemoryPreferencesStore(
      const AppPreferences(backgroundEffect: BackgroundEffectLevel.powerSaver),
    );
    await pumpSettings(tester, store: store);

    expect(find.text('Power Saving'), findsOneWidget);
    expect(prefsAt(tester).backgroundEffect, BackgroundEffectLevel.powerSaver);
  });

  group('均衡器', () {
    /// 弹层内的滑杆（避开设置页底层的音量滑杆）。
    Finder bandSlider(int index) => find.descendant(
      of: find.byType(EqualizerSheet),
      matching: find.byKey(ValueKey('equalizer-band-$index')),
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('settings-equalizer')));
      await tester.pumpAndSettle();
      expect(find.byType(EqualizerSheet), findsOneWidget);
    }

    testWidgets('TC-EQ-12 弹窗宽度与其他弹窗一致（不被短文案收窄）', (tester) async {
      await pumpSettings(tester);
      await openSheet(tester);

      // 不支持分支只有短文案：宽度仍应为统一弹窗宽 440
      // （viewport 800 → 80% 钳制 640，不生效）。
      expect(
        tester.getSize(find.byType(EqualizerSheet)).width,
        centerPopupWidth,
      );
    });

    testWidgets('TC-EQ-01 不支持平台降级：行值与弹层说明', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Not supported'), findsOneWidget);
      await openSheet(tester);

      expect(
        find.text('Equalizer is not supported on this platform'),
        findsOneWidget,
      );
      expect(find.byType(CupertinoSwitch), findsNothing);
      expect(
        find.descendant(
          of: find.byType(EqualizerSheet),
          matching: find.byType(Slider),
        ),
        findsNothing,
      );
    });

    testWidgets('TC-EQ-02 未就绪：开关可用并提示先播放', (tester) async {
      final eq = FakeEqualizer(autoReady: false);
      final store = InMemoryPreferencesStore();
      await pumpSettings(
        tester,
        engine: FakeAudioEngine(equalizer: eq),
        store: store,
      );

      expect(find.text('Off'), findsOneWidget);
      await openSheet(tester);

      expect(find.text('Start playback to adjust bands'), findsOneWidget);
      expect(bandSlider(0), findsNothing);

      await tester.tap(find.byKey(const ValueKey('equalizer-switch')));
      await tester.pumpAndSettle();

      expect(prefsAt(tester).equalizerEnabled, isTrue);
      expect(store.lastSaved.equalizerEnabled, isTrue);
      expect(eq.enabled, isTrue);
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('TC-EQ-03 就绪：渲染滑杆，拖动写偏好并同步引擎', (tester) async {
      final eq = FakeEqualizer();
      final store = InMemoryPreferencesStore(
        const AppPreferences(equalizerEnabled: true),
      );
      await pumpSettings(
        tester,
        engine: FakeAudioEngine(equalizer: eq),
        store: store,
      );
      await openSheet(tester);

      // 5 条频段滑杆 + 预设 + 重置渲染。
      for (var i = 0; i < 5; i++) {
        expect(bandSlider(i), findsOneWidget);
      }
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('60Hz'), findsOneWidget);
      expect(find.text('14kHz'), findsOneWidget);

      await tester.drag(bandSlider(0), const Offset(60, 0));
      await tester.pumpAndSettle();

      final gains = prefsAt(tester).equalizerGains;
      expect(gains, hasLength(5));
      expect(gains[0], greaterThan(0));
      expect(eq.bands[0].gain, closeTo(gains[0], 1e-9));
    });

    testWidgets('TC-EQ-04 预设一键应用', (tester) async {
      final eq = FakeEqualizer();
      await pumpSettings(
        tester,
        engine: FakeAudioEngine(equalizer: eq),
        store: InMemoryPreferencesStore(
          const AppPreferences(equalizerEnabled: true),
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('equalizer-preset-rock')));
      await tester.pumpAndSettle();

      expect(prefsAt(tester).equalizerGains, EqualizerPreset.rock.curve);
      expect([for (final b in eq.bands) b.gain], EqualizerPreset.rock.curve);
    });

    testWidgets('TC-EQ-05 重置为平直', (tester) async {
      final eq = FakeEqualizer();
      await pumpSettings(
        tester,
        engine: FakeAudioEngine(equalizer: eq),
        store: InMemoryPreferencesStore(
          const AppPreferences(
            equalizerEnabled: true,
            equalizerGains: [3, 2, -1, 2, 4],
          ),
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const ValueKey('equalizer-reset')));
      await tester.pumpAndSettle();

      expect(prefsAt(tester).equalizerGains, List.filled(5, 0.0));
      expect([for (final b in eq.bands) b.gain], List.filled(5, 0.0));
    });

    testWidgets('TC-EQ-06 启动即应用已持久化设置（不开弹层）', (tester) async {
      final eq = FakeEqualizer();
      await pumpSettings(
        tester,
        engine: FakeAudioEngine(equalizer: eq),
        store: InMemoryPreferencesStore(
          const AppPreferences(
            equalizerEnabled: true,
            equalizerGains: [1, 2, 3, 4, 5],
          ),
        ),
      );

      expect(eq.enabled, isTrue);
      expect([for (final b in eq.bands) b.gain], [1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(find.text('On'), findsOneWidget);
    });
  });

  group('桌面歌词（仅桌面端）', () {
    testWidgets('TC-24 移动断点不显示桌面分组', (tester) async {
      await pumpSettings(tester); // 800 宽 < 桌面断点 840

      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-font')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-reset')),
        findsNothing,
      );
    });

    testWidgets('TC-25/26 桌面断点显示分组；开关切换生效并持久化', (tester) async {
      final api = FakeLyricWindowApi()..stealsFocus = true;
      final store = InMemoryPreferencesStore();
      await pumpSettings(
        tester,
        store: store,
        size: const Size(1200, 900),
        extraOverrides: [lyricWindowApiProvider.overrideWithValue(api)],
      );

      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics')),
        findsOneWidget,
      );
      // 关闭态：字号/恢复位置子项不展示（渐进披露）。
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-font')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-reset')),
        findsNothing,
      );

      // 开 → 窗口打开 + 持久化 + 子项出现 + 抢焦点平台提示出现。
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(prefsAt(tester).desktopLyricsEnabled, isTrue);
      expect(store.lastSaved.desktopLyricsEnabled, isTrue);
      expect(api.openState, isTrue);
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-font')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-reset')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Clicking the lyrics bar may bring this app to the front '
          'on this platform',
        ),
        findsOneWidget,
      );

      // 关 → 窗口关闭，提示与子项消失。
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(prefsAt(tester).desktopLyricsEnabled, isFalse);
      expect(api.openState, isFalse);
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-font')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('settings-desktop-lyrics-reset')),
        findsNothing,
      );
      expect(
        find.text(
          'Clicking the lyrics bar may bring this app to the front '
          'on this platform',
        ),
        findsNothing,
      );
    });

    testWidgets('TC-27 字号档位选择持久化', (tester) async {
      // 字号入口仅在开启后显示：存储遗留的开关=开在启动时被强制归零
      // （TC-07），先手动打开开关模拟用户操作。
      await pumpSettings(
        tester,
        store: InMemoryPreferencesStore(
          const AppPreferences(desktopLyricsEnabled: true),
        ),
        size: const Size(1200, 900),
      );

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('settings-desktop-lyrics-font')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();

      expect(
        prefsAt(tester).desktopLyricsFontSize,
        DesktopLyricsFontSize.large,
      );
    });

    testWidgets('TC-28 恢复默认位置清空自定义偏移', (tester) async {
      final store = InMemoryPreferencesStore(
        const AppPreferences(
          desktopLyricsEnabled: true,
          desktopLyricsOffset: Offset(12, 34),
        ),
      );
      await pumpSettings(tester, store: store, size: const Size(1200, 900));

      // 启动强制归零（TC-07）：先手动打开开关让恢复位置入口出现。
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('settings-desktop-lyrics-reset')),
      );
      await tester.pumpAndSettle();

      expect(prefsAt(tester).desktopLyricsOffset, isNull);
      expect(store.lastSaved.desktopLyricsOffset, isNull);
    });
  });
}
