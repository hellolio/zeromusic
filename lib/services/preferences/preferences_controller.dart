import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用偏好：主题模式、语言、减弱动效。
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.reduceMotion = false,
  });

  final ThemeMode themeMode;
  final Locale? locale;
  final bool reduceMotion;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool? reduceMotion,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }
}

class PreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => const AppPreferences();
}

/// 全局偏好 Provider。
final preferencesProvider =
    NotifierProvider<PreferencesController, AppPreferences>(PreferencesController.new);
