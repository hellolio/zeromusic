import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_strings.dart';
import 'strings_en.dart';
import 'strings_ja.dart';
import 'strings_zh.dart';

/// 应用支持的语言与对应字符串。
enum AppLanguage {
  zh(Locale('zh', 'CN'), '中文', AppStringsZh()),
  en(Locale('en'), 'English', AppStringsEn()),
  ja(Locale('ja'), '日本語', AppStringsJa());

  const AppLanguage(this.locale, this.label, this.strings);

  final Locale locale;
  final String label;
  final AppStrings strings;

  static AppLanguage fromLocale(Locale? locale) {
    if (locale == null) return zh;
    for (final lang in values) {
      if (lang.locale.languageCode == locale.languageCode) return lang;
    }
    return zh;
  }
}

/// AppStrings 的 LocalizationsDelegate。
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.fromLocale(locale).locale == locale ||
      AppLanguage.values.any((l) => l.locale.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppLanguage.fromLocale(locale).strings;

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

/// 组装 MaterialApp 需要的全部 delegates。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppStringsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
