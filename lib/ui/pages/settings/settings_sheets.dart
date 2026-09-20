import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/localizations_delegate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/preferences/preferences_controller.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';

/// 主题模式的中/英/日标签（页面行值与选择弹层共用）。
String themeLabel(AppStrings strings, ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return strings.settingsThemeLight;
    case ThemeMode.dark:
      return strings.settingsThemeDark;
    case ThemeMode.system:
      return strings.settingsThemeSystem;
  }
}

/// 背景效果档位的三语标签（页面行值与选择弹层共用）。
String backgroundEffectLabel(
    AppStrings strings, BackgroundEffectLevel level) {
  switch (level) {
    case BackgroundEffectLevel.powerSaver:
      return strings.bgEffectPowerSaver;
    case BackgroundEffectLevel.balanced:
      return strings.bgEffectBalanced;
    case BackgroundEffectLevel.vivid:
      return strings.bgEffectVivid;
  }
}

/// 背景效果档位三态选择：居中弹窗（桌面/移动一致）。
Future<void> showBackgroundPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final current = ref.read(preferencesProvider).value?.backgroundEffect ??
      BackgroundEffectLevel.balanced;

  Future<void> onPick(BackgroundEffectLevel level) async {
    await ref.read(preferencesProvider.notifier).setBackgroundEffect(level);
  }

  await showCenterPopup<void>(
    context,
    child: _ChoiceSheet(
      title: strings.settingsBackground,
      options: [
        for (final level in BackgroundEffectLevel.values)
          _ChoiceOption(
            label: backgroundEffectLabel(strings, level),
            checked: level == current,
            onTap: () async {
              await onPick(level);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    ),
  );
}

/// 主题三态选择：居中弹窗（桌面/移动一致）。
Future<void> showThemePicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final current =
      ref.read(preferencesProvider).value?.themeMode ?? ThemeMode.system;

  Future<void> onPick(ThemeMode mode) async {
    await ref.read(preferencesProvider.notifier).setThemeMode(mode);
  }

  await showCenterPopup<void>(
    context,
    child: _ChoiceSheet(
      title: strings.settingsTheme,
      options: [
        for (final mode in ThemeMode.values)
          _ChoiceOption(
            label: themeLabel(strings, mode),
            checked: mode == current,
            onTap: () async {
              await onPick(mode);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    ),
  );
}

/// 语言三态选择：居中弹窗（桌面/移动一致）。
Future<void> showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final current = AppLanguage.fromLocale(Localizations.localeOf(context));

  Future<void> onPick(AppLanguage lang) async {
    await ref.read(preferencesProvider.notifier).setLocale(lang.locale);
  }

  await showCenterPopup<void>(
    context,
    child: _ChoiceSheet(
      title: strings.settingsLanguage,
      options: [
        for (final lang in AppLanguage.values)
          _ChoiceOption(
            label: lang.label,
            checked: lang == current,
            onTap: () async {
              await onPick(lang);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    ),
  );
}

/// 选择弹窗：窗口居中展示（桌面/移动一致）。
class _ChoiceOption {
  const _ChoiceOption({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;
}

/// 居中选择弹窗：毛玻璃容器承载选项列表。
class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.options});

  final String title;
  final List<_ChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceM,
              AppTokens.spaceM,
              AppTokens.spaceM,
              AppTokens.spaceS,
            ),
            child: Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final option in options)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                option.checked
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: option.checked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSecondary,
              ),
              title: Text(
                option.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: option.checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight:
                      option.checked ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              onTap: option.onTap,
            ),
          const SizedBox(height: AppTokens.spaceS),
        ],
      ),
    );
  }
}