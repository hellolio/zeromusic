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
    // 偏好异步载入，首帧用默认值（跟随系统 / 中文），载入后即时生效。
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();
    final appStrings = AppLanguage.fromLocale(prefs.locale).strings;

    // 合并环境已有的 disableAnimations（系统减弱动态效果 / 测试包装层）
    // 与偏好开关，保证全应用动画统一降级。
    final existing = MediaQuery.maybeOf(context);
    final base = existing ?? MediaQueryData.fromView(View.of(context));
    final reduced =
        (existing?.disableAnimations ?? false) || prefs.reduceMotion;

    return MediaQuery(
      data: base.copyWith(disableAnimations: reduced),
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
