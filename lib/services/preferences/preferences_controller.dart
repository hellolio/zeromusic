import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放页背景效果档位：效果与能耗的权衡（3 档）。
///
/// 省电：光斑少、模糊轻、色相漂移弱；均衡：默认；绚彩：最多光斑 + 重模糊。
enum BackgroundEffectLevel { powerSaver, balanced, vivid }

/// 应用偏好：主题模式、语言、减弱动效、默认音量、背景效果档位。
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.reduceMotion = false,
    this.defaultVolume = 1.0,
    this.backgroundEffect = BackgroundEffectLevel.balanced,
  });

  final ThemeMode themeMode;
  final Locale? locale;
  final bool reduceMotion;

  /// 默认播放音量（0.0–1.0），播放前应用到引擎。
  final double defaultVolume;

  /// 播放页背景变色效果档位。
  final BackgroundEffectLevel backgroundEffect;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool? reduceMotion,
    double? defaultVolume,
    BackgroundEffectLevel? backgroundEffect,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      backgroundEffect: backgroundEffect ?? this.backgroundEffect,
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
  static const _kReduceMotion = 'prefs.reduceMotion';
  static const _kDefaultVolume = 'prefs.defaultVolume';
  static const _kBackgroundEffect = 'prefs.backgroundEffect';

  @override
  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeRaw = prefs.getString(_kLocale);
    return AppPreferences(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: localeRaw == null ? null : Locale(localeRaw),
      reduceMotion: prefs.getBool(_kReduceMotion) ?? false,
      defaultVolume: prefs.getDouble(_kDefaultVolume) ?? 1.0,
      backgroundEffect:
          _parseBackgroundEffect(prefs.getString(_kBackgroundEffect)),
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
    await store.setBool(_kReduceMotion, prefs.reduceMotion);
    await store.setDouble(_kDefaultVolume, prefs.defaultVolume.clamp(0.0, 1.0));
    await store.setString(_kBackgroundEffect, prefs.backgroundEffect.name);
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
}

/// 偏好存储注入点（测试用内存实现覆盖）。
final preferencesStoreProvider =
    Provider<PreferencesStore>((ref) => SharedPreferencesStore());

/// 全局偏好控制器：启动时从 [preferencesStoreProvider] 载入，更改即持久化。
class PreferencesController extends AsyncNotifier<AppPreferences> {
  @override
  Future<AppPreferences> build() =>
      ref.watch(preferencesStoreProvider).load();

  Future<void> setThemeMode(ThemeMode mode) =>
      _mutate((p) => p.copyWith(themeMode: mode));

  Future<void> setLocale(Locale? locale) =>
      _mutate((p) => p.copyWith(locale: locale));

  Future<void> setReduceMotion(bool enabled) =>
      _mutate((p) => p.copyWith(reduceMotion: enabled));

  Future<void> setDefaultVolume(double volume) => _mutate(
      (p) => p.copyWith(defaultVolume: volume.clamp(0.0, 1.0)));

  Future<void> setBackgroundEffect(BackgroundEffectLevel level) =>
      _mutate((p) => p.copyWith(backgroundEffect: level));

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
        PreferencesController.new);