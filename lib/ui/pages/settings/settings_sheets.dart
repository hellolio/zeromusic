import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/localizations_delegate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/preferences/preferences_controller.dart';
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

/// 背景效果档位三态选择：桌面端锚点菜单，移动端毛玻璃底部弹层。
Future<void> showBackgroundPicker(
  BuildContext context,
  WidgetRef ref,
  Offset anchor,
) async {
  final strings = context.strings;
  final current = ref.read(preferencesProvider).value?.backgroundEffect ??
      BackgroundEffectLevel.balanced;

  Future<void> onPick(BackgroundEffectLevel level) async {
    await ref.read(preferencesProvider.notifier).setBackgroundEffect(level);
  }

  if (MediaQuery.sizeOf(context).width >= 840) {
    final result = await showMenu<BackgroundEffectLevel>(
      context: context,
      position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
      items: [
        for (final level in BackgroundEffectLevel.values)
          PopupMenuItem(
            value: level,
            child: _OptionRow(
              icon: level == current
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              label: backgroundEffectLabel(strings, level),
              checked: level == current,
            ),
          ),
      ],
    );
    if (result != null) await onPick(result);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ChoiceSheet(
      title: strings.settingsBackground,
      options: [
        for (final level in BackgroundEffectLevel.values)
          _ChoiceOption(
            label: backgroundEffectLabel(sheetCtx.strings, level),
            checked: level == current,
            onTap: () async {
              await onPick(level);
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            },
          ),
      ],
    ),
  );
}

/// 主题三态选择：桌面端锚点菜单，移动端毛玻璃底部弹层。
/// [anchor] 为触发行的屏幕坐标（桌面端菜单定位用）。
Future<void> showThemePicker(
  BuildContext context,
  WidgetRef ref,
  Offset anchor,
) async {
  final strings = context.strings;
  final current =
      ref.read(preferencesProvider).value?.themeMode ?? ThemeMode.system;

  Future<void> onPick(ThemeMode mode) async {
    await ref.read(preferencesProvider.notifier).setThemeMode(mode);
  }

  if (MediaQuery.sizeOf(context).width >= 840) {
    final result = await showMenu<ThemeMode>(
      context: context,
      position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
      items: [
        for (final mode in ThemeMode.values)
          PopupMenuItem(
            value: mode,
            child: _OptionRow(
              icon: mode == current
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              label: themeLabel(strings, mode),
              checked: mode == current,
            ),
          ),
      ],
    );
    if (result != null) await onPick(result);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ChoiceSheet(
      title: strings.settingsTheme,
      options: [
        for (final mode in ThemeMode.values)
          _ChoiceOption(
            label: themeLabel(sheetCtx.strings, mode),
            checked: mode == current,
            onTap: () async {
              await onPick(mode);
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            },
          ),
      ],
    ),
  );
}

/// 语言三态选择：桌面端锚点菜单，移动端毛玻璃底部弹层。
Future<void> showLanguagePicker(
  BuildContext context,
  WidgetRef ref,
  Offset anchor,
) async {
  final strings = context.strings;
  final current = AppLanguage.fromLocale(Localizations.localeOf(context));

  Future<void> onPick(AppLanguage lang) async {
    await ref.read(preferencesProvider.notifier).setLocale(lang.locale);
  }

  if (MediaQuery.sizeOf(context).width >= 840) {
    final result = await showMenu<AppLanguage>(
      context: context,
      position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
      items: [
        for (final lang in AppLanguage.values)
          PopupMenuItem(
            value: lang,
            child: _OptionRow(
              icon: lang == current
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.square,
              label: lang.label,
              checked: lang == current,
            ),
          ),
      ],
    );
    if (result != null) await onPick(result);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ChoiceSheet(
      title: strings.settingsLanguage,
      options: [
        for (final lang in AppLanguage.values)
          _ChoiceOption(
            label: lang.label,
            checked: lang == current,
            onTap: () async {
              await onPick(lang);
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            },
          ),
      ],
    ),
  );
}

/// 桌面端菜单行：图标 + 文案。
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.checked,
  });

  final IconData icon;
  final String label;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color:
              checked ? theme.colorScheme.primary : theme.colorScheme.onSecondary,
        ),
        const SizedBox(width: AppTokens.spaceS),
        Text(label),
      ],
    );
  }
}

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

/// 移动端选择弹层：自下而上 + 毛玻璃（对照需求「语言弹窗」）。
class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.options});

  final String title;
  final List<_ChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceM),
              child: Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final option in options)
              ListTile(
                dense: true,
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
      ),
    );
  }
}