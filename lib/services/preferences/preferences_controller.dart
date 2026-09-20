import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放页背景效果档位：效果与能耗的权衡（3 档）。
///
/// 省电：光斑少、模糊轻、色相漂移弱；均衡：默认；绚彩：最多光斑 + 重模糊。
enum BackgroundEffectLevel { powerSaver, balanced, vivid }

/// 应用偏好：主题模式、语言、默认音量、背景效果档位、均衡器。
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.defaultVolume = 1.0,
    this.backgroundEffect = BackgroundEffectLevel.balanced,
    this.equalizerEnabled = false,
    this.equalizerGains = const [],
  });

  final ThemeMode themeMode;
  final Locale? locale;

  /// 默认播放音量（0.0–1.0），播放前应用到引擎。
  final double defaultVolume;

  /// 播放页背景变色效果档位。
  final BackgroundEffectLevel backgroundEffect;

  /// 均衡器开关（引擎不支持时仅作偏好记录，UI 降级展示）。
  final bool equalizerEnabled;

  /// 均衡器各频段增益（dB），按频段下标排列；空列表 = 全 0（平直）。
  /// 与设备实际段数不一致时由均衡器控制器 pad 0 / 截断后应用。
  final List<double> equalizerGains;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    double? defaultVolume,
    BackgroundEffectLevel? backgroundEffect,
    bool? equalizerEnabled,
    List<double>? equalizerGains,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      backgroundEffect: backgroundEffect ?? this.backgroundEffect,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerGains: equalizerGains ?? this.equalizerGains,
    );
  }
}

/// 偏好持久化契约（同 import_io 模式：真实实现走平台存储，测试注入内存实现）。
abstract class PreferencesStore {
  Future<AppPreferences> load();

  Future<void> save(AppPreferences prefs);
}

/// 真实实现：shared_preferences。
class SharedPreferencesStore implements PreferencesStore {
  static const _kThemeMode = 'prefs.themeMode';
  static const _kLocale = 'prefs.locale';
  static const _kDefaultVolume = 'prefs.defaultVolume';
  static const _kBackgroundEffect = 'prefs.backgroundEffect';
  static const _kEqualizerEnabled = 'prefs.equalizer.enabled';
  static const _kEqualizerGains = 'prefs.equalizer.gains';

  @override
  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeRaw = prefs.getString(_kLocale);
    return AppPreferences(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: localeRaw == null ? null : Locale(localeRaw),
      defaultVolume: prefs.getDouble(_kDefaultVolume) ?? 1.0,
      backgroundEffect: _parseBackgroundEffect(
        prefs.getString(_kBackgroundEffect),
      ),
      equalizerEnabled: prefs.getBool(_kEqualizerEnabled) ?? false,
      equalizerGains: _parseEqualizerGains(prefs.getString(_kEqualizerGains)),
    );
  }

  @override
  Future<void> save(AppPreferences prefs) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(_kThemeMode, prefs.themeMode.name);
    final locale = prefs.locale;
    if (locale == null) {
      await store.remove(_kLocale);
    } else {
      await store.setString(_kLocale, locale.languageCode);
    }
    await store.setDouble(_kDefaultVolume, prefs.defaultVolume.clamp(0.0, 1.0));
    await store.setString(_kBackgroundEffect, prefs.backgroundEffect.name);
    await store.setBool(_kEqualizerEnabled, prefs.equalizerEnabled);
    await store.setString(_kEqualizerGains, jsonEncode(prefs.equalizerGains));
  }

  static ThemeMode _parseThemeMode(String? name) {
    for (final mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return ThemeMode.system;
  }

  static BackgroundEffectLevel _parseBackgroundEffect(String? name) {
    for (final level in BackgroundEffectLevel.values) {
      if (level.name == name) return level;
    }
    return BackgroundEffectLevel.balanced;
  }

  /// 解析持久化的频段增益；损坏 JSON / 非列表 / 非数字一律回退空列表（平直）。
  static List<double> _parseEqualizerGains(String? raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final e in decoded) (e as num).toDouble()];
    } catch (_) {
      return const [];
    }
  }
}

/// 偏好存储注入点（测试用内存实现覆盖）。
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => SharedPreferencesStore(),
);

/// 全局偏好控制器：启动时从 [preferencesStoreProvider] 载入，更改即持久化。
class PreferencesController extends AsyncNotifier<AppPreferences> {
  @override
  Future<AppPreferences> build() => ref.watch(preferencesStoreProvider).load();

  Future<void> setThemeMode(ThemeMode mode) =>
      _mutate((p) => p.copyWith(themeMode: mode));

  Future<void> setLocale(Locale? locale) =>
      _mutate((p) => p.copyWith(locale: locale));

  Future<void> setDefaultVolume(double volume) =>
      _mutate((p) => p.copyWith(defaultVolume: volume.clamp(0.0, 1.0)));

  Future<void> setBackgroundEffect(BackgroundEffectLevel level) =>
      _mutate((p) => p.copyWith(backgroundEffect: level));

  Future<void> setEqualizerEnabled(bool enabled) =>
      _mutate((p) => p.copyWith(equalizerEnabled: enabled));

  /// 写入整列频段增益（dB）。调用方（均衡器控制器）负责按设备段数对齐。
  Future<void> setEqualizerGains(List<double> gains) =>
      _mutate((p) => p.copyWith(equalizerGains: List.unmodifiable(gains)));

  /// 乐观更新状态并异步落盘；加载完成前变更以默认值为基。
  Future<void> _mutate(AppPreferences Function(AppPreferences) change) async {
    final next = change(state.value ?? const AppPreferences());
    state = AsyncValue.data(next);
    await ref.read(preferencesStoreProvider).save(next);
  }
}

/// 全局偏好 Provider。
final preferencesProvider =
    AsyncNotifierProvider<PreferencesController, AppPreferences>(
      PreferencesController.new,
    );
