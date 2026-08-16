import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/localizations_delegate.dart';
import 'core/theme/app_theme.dart';
import 'services/preferences/preferences_controller.dart';
import 'ui/scaffold/adaptive_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

/// 应用根组件：注入主题与本地化。
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final appStrings = AppLanguage.fromLocale(prefs.locale).strings;
    return MaterialApp(
      title: appStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: prefs.themeMode,
      locale: prefs.locale,
      supportedLocales: AppLanguage.values.map((l) => l.locale),
      localizationsDelegates: appLocalizationsDelegates,
      home: const AdaptiveScaffold(),
    );
  }
}
