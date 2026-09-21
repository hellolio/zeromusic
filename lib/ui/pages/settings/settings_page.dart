import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/localizations_delegate.dart';
import '../../../core/platform/device_type.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/audio/equalizer_controller.dart';
import '../../../services/desktop_lyrics/lyric_window_api.dart';
import '../../../services/preferences/preferences_controller.dart';
import '../../scaffold/content_bottom_inset.dart';
import 'equalizer_sheet.dart';
import 'settings_sheets.dart';

/// 设置页面：主题、语言（中/英/日）、默认音量、背景效果、关于。
///
/// - 移动端 / 桌面端共用同一列表布局；选项统一窗口居中弹框弹出。
/// - 桌面端内容限制最大宽度并居中，避免「设置项 ↔ 修改元素」相隔过远。
/// - 全部设置由 [preferencesProvider] 驱动并即时持久化。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 与 pubspec 保持一致的版本号。
  static const appVersion = '1.0.0';

  /// 桌面端列表内容最大宽度。
  static const double desktopContentMaxWidth = 560;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();
    final language = AppLanguage.fromLocale(Localizations.localeOf(context))
        .label;
    final motionReduced = MediaQuery.disableAnimationsOf(context);
    // 桌面端限制内容宽度并居中，避免设置项与修改元素相隔过远。
    final desktop =
        deviceTypeOfSize(MediaQuery.sizeOf(context)) == DeviceType.desktop;

    final body = ListView(
      // 底部预留悬浮玻璃（迷你条+底栏）高度，最后一项可滚到玻璃之上。
      padding: EdgeInsets.only(
        bottom: AppTokens.spaceL + ContentBottomInset.of(context),
      ),
      children: [
        _SectionLabel(strings.settingsAppearance),
        _SettingsTile(
          key: const ValueKey('settings-theme'),
          icon: CupertinoIcons.sun_max,
          label: strings.settingsTheme,
          value: themeLabel(strings, prefs.themeMode),
          onTap: () => showThemePicker(context, ref),
        ),
        _SectionLabel(strings.settingsLanguage),
        _SettingsTile(
          key: const ValueKey('settings-language'),
          icon: CupertinoIcons.globe,
          label: strings.settingsLanguage,
          value: language,
          onTap: () => showLanguagePicker(context, ref),
        ),
        _SectionLabel(strings.settingsPlayback),
        const _VolumeTile(),
        _SettingsTile(
          key: const ValueKey('settings-equalizer'),
          icon: CupertinoIcons.slider_horizontal_3,
          label: strings.settingsEqualizer,
          value: equalizerValueLabel(
            strings,
            ref.watch(equalizerControllerProvider),
          ),
          onTap: () => showEqualizerSheet(context),
        ),
        _SettingsTile(
          key: const ValueKey('settings-background-effect'),
          icon: CupertinoIcons.wand_stars,
          label: strings.settingsBackground,
          value: backgroundEffectLabel(strings, prefs.backgroundEffect),
          onTap: () => showBackgroundPicker(context, ref),
        ),
        // ---- 桌面（仅桌面端显示，需求 §4）----
        if (desktop) ...[
          _SectionLabel(strings.settingsDesktop),
          const _DesktopLyricsTile(),
          _SettingsTile(
            key: const ValueKey('settings-desktop-lyrics-font'),
            icon: CupertinoIcons.textformat,
            label: strings.desktopLyricsFontSize,
            value: desktopFontSizeLabel(strings, prefs.desktopLyricsFontSize),
            onTap: () => showDesktopFontSizePicker(context, ref),
          ),
          _SettingsTile(
            key: const ValueKey('settings-desktop-lyrics-reset'),
            icon: CupertinoIcons.arrow_counterclockwise,
            label: strings.desktopLyricsResetPosition,
            onTap: () => ref
                .read(preferencesProvider.notifier)
                .clearDesktopLyricsOffset(),
          ),
        ],
        _SectionLabel(strings.settingsAbout),
        _SettingsTile(
          key: const ValueKey('settings-version'),
          icon: CupertinoIcons.info_circle,
          label: strings.settingsVersion,
          value: appVersion,
        ),
        _SettingsTile(
          key: const ValueKey('settings-licenses'),
          icon: CupertinoIcons.doc_plaintext,
          label: strings.settingsOpenSourceLicenses,
          onTap: () => showLicensePage(context: context),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(strings.navSettings)),
      // 列表项进入：淡入 + 位移动画；
      body: TweenAnimationBuilder<double>(
        duration: motionReduced ? Duration.zero : AppCurves.standardMotion,
        curve: AppCurves.standard,
        tween: Tween(begin: 0, end: 1),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * AppTokens.spaceM),
            child: child,
          ),
        ),
        child: desktop
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: desktopContentMaxWidth,
                  ),
                  child: body,
                ),
              )
            : body,
      ),
    );
  }
}

/// 默认音量行：滑杆（0–100%）即时应用到引擎并持久化。
class _VolumeTile extends ConsumerWidget {
  const _VolumeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final volume = ref.watch(preferencesProvider).value?.defaultVolume ?? 1.0;
    return Padding(
      key: const ValueKey('settings-volume'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceM,
        vertical: AppTokens.spaceXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.speaker_2_fill,
                size: 20,
                color: theme.colorScheme.onSecondary,
              ),
              const SizedBox(width: AppTokens.spaceM),
              Expanded(
                child: Text(
                  strings.settingsDefaultVolume,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Text(
                '${(volume * 100).round()}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondary,
                ),
              ),
            ],
          ),
          Slider(
            value: volume.clamp(0.0, 1.0),
            onChanged: (v) =>
                ref.read(preferencesProvider.notifier).setDefaultVolume(v),
          ),
        ],
      ),
    );
  }
}

/// 设置行：图标 + 标签 +（值 + 箭头）。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSecondary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM),
      leading: Icon(icon, size: 20, color: muted),
      title: Text(label, style: theme.textTheme.bodyLarge),
      trailing: value == null
          ? const SizedBox(width: 16)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceXs),
                const Icon(CupertinoIcons.chevron_right, size: 14),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// 分组小标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceM,
        AppTokens.spaceM,
        AppTokens.spaceM,
        AppTokens.spaceS,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
      ),
    );
  }
}

/// 桌面歌词开关行：开关即时开合歌词条窗口并持久化。
///
/// 编排（创建/隐藏窗口、状态推送）由 [DesktopLyricsController] 完成，
/// 这里只写偏好。开启且当前平台点击会抳焦点时，附降级提示文案。
class _DesktopLyricsTile extends ConsumerWidget {
  const _DesktopLyricsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final enabled = ref.watch(
      preferencesProvider.select((p) => p.value?.desktopLyricsEnabled ?? false),
    );
    final stealsFocus = ref.watch(lyricWindowApiProvider).stealsFocusOnClick;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const ValueKey('settings-desktop-lyrics'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceM,
          ),
          leading: Icon(
            CupertinoIcons.text_quote,
            size: 20,
            color: theme.colorScheme.onSecondary,
          ),
          title: Text(strings.desktopLyrics, style: theme.textTheme.bodyLarge),
          trailing: Switch(
            value: enabled,
            onChanged: (v) => ref
                .read(preferencesProvider.notifier)
                .setDesktopLyricsEnabled(v),
          ),
        ),
        if (enabled && stealsFocus)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceL,
              0,
              AppTokens.spaceM,
              AppTokens.spaceS,
            ),
            child: Text(
              strings.desktopLyricsFocusHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
