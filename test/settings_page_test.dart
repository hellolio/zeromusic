import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeromusic/services/preferences/preferences_controller.dart';
import 'package:zeromusic/ui/pages/settings/settings_page.dart';

import 'helpers.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_data_layer.dart';
import 'support/in_memory_preferences_store.dart';

void main() {
  group('SharedPreferencesStore 持久化层', () {
    test('save/load 往返保真', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesStore();

      const prefs = AppPreferences(
        themeMode: ThemeMode.dark,
        locale: Locale('ja'),
        reduceMotion: true,
        defaultVolume: 0.35,
        backgroundEffect: BackgroundEffectLevel.vivid,
      );
      await store.save(prefs);

      final loaded = await store.load();
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.locale?.languageCode, 'ja');
      expect(loaded.reduceMotion, isTrue);
      expect(loaded.defaultVolume, closeTo(0.35, 1e-9));
      expect(loaded.backgroundEffect, BackgroundEffectLevel.vivid);
    });

    test('空库读默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesStore();

      final loaded = await store.load();
      expect(loaded.themeMode, ThemeMode.system);
      expect(loaded.locale, isNull);
      expect(loaded.reduceMotion, isFalse);
      expect(loaded.defaultVolume, 1.0);
      expect(loaded.backgroundEffect, BackgroundEffectLevel.balanced);
    });
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    InMemoryPreferencesStore? store,
    FakeAudioEngine? engine,
    Size size = const Size(800, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrapApp(
      overrides: fakeDataLayerOverrides(FakeDataLayer()),
      preferencesStore: store,
      audioEngine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  AppPreferences prefsAt(WidgetTester tester) {
    final container =
        ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
    return container.read(preferencesProvider).value ?? const AppPreferences();
  }

  testWidgets('TC-01 设置页渲染分组与当前值', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(SettingsPage), findsOneWidget);
    for (final label in [
      'Appearance',
      'Theme',
      'Reduce Motion',
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
    expect(find.text('Coming soon'), findsOneWidget);
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

  testWidgets('TC-04 桌面端主题选择用锚点菜单', (tester) async {
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
    expect(find.text('减弱动态效果'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('设置'),
      ),
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
        reduceMotion: true,
        defaultVolume: 0.6,
      ),
    );
    await pumpSettings(tester, store: store);

    expect(find.text('ダーク'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    final switchValue = tester.widget<CupertinoSwitch>(
      find.byType(CupertinoSwitch),
    );
    expect(switchValue.value, isTrue);
  });

  testWidgets('TC-08 减弱动效开关翻转并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    final toggle = find.byType(CupertinoSwitch);
    expect(tester.widget<CupertinoSwitch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefsAt(tester).reduceMotion, isTrue);
    expect(store.lastSaved.reduceMotion, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefsAt(tester).reduceMotion, isFalse);
    expect(store.lastSaved.reduceMotion, isFalse);
  });

  testWidgets('TC-09 默认音量滑杆联动引擎', (tester) async {
    final engine = FakeAudioEngine();
    await pumpSettings(tester, engine: engine);

    // 启动后即把默认音量应用到引擎。
    expect(engine.lastVolume, 1.0);

    final before = prefsAt(tester).defaultVolume;
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-200, 0),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    final after = prefsAt(tester).defaultVolume;
    expect(after, lessThan(before));
    expect(engine.lastVolume!, closeTo(after, 1e-9));
  });

  testWidgets('TC-10 背景效果档位切换并持久化', (tester) async {
    final store = InMemoryPreferencesStore();
    await pumpSettings(tester, store: store);

    expect(
      prefsAt(tester).backgroundEffect,
      BackgroundEffectLevel.balanced,
    );
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
      const AppPreferences(
        backgroundEffect: BackgroundEffectLevel.powerSaver,
      ),
    );
    await pumpSettings(tester, store: store);

    expect(find.text('Power Saving'), findsOneWidget);
    expect(prefsAt(tester).backgroundEffect, BackgroundEffectLevel.powerSaver);
  });
}