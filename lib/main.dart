import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/localizations_delegate.dart';
import 'core/theme/app_theme.dart';
import 'services/desktop_lyrics/desktop_lyrics_controller.dart';
import 'services/desktop_lyrics/lyric_bar_messenger.dart';
import 'services/preferences/preferences_controller.dart';
import 'ui/desktop_lyrics/lyric_bar_app.dart';
import 'ui/scaffold/adaptive_scaffold.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面歌词子窗口入口（desktop_multi_window：args = ['multi_window', id, json]）。
  if (args.firstOrNull == kMultiWindowEntryArg &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await runLyricBarWindow();
    return;
  }

  runApp(const ProviderScope(child: MyApp()));
}

/// 应用根组件：注入主题与本地化。
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 桌面歌词编排器保活：行推送 / 窗口开关同步依赖它常驻。
    ref.watch(desktopLyricsControllerProvider);
    // 偏好异步载入，首帧用默认值（跟随系统 / 中文），载入后即时生效。
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();
    final appStrings = AppLanguage.fromLocale(prefs.locale).strings;

    // 保留环境已有的 disableAnimations（系统减弱动态效果 / 测试包装层），
    // 全应用动画据此统一降级；不提供应用内减弱动效开关。
    final existing = MediaQuery.maybeOf(context);
    final base = existing ?? MediaQueryData.fromView(View.of(context));

    return MediaQuery(
      data: base,
      child: MaterialApp(
        title: appStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: prefs.themeMode,
        locale: prefs.locale,
        supportedLocales: AppLanguage.values.map((l) => l.locale),
        localizationsDelegates: appLocalizationsDelegates,
        home: const AdaptiveScaffold(),
      ),
    );
  }
}
