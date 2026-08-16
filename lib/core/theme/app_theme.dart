import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 主题扩展：把设计令牌注入 [ThemeData]，供全局复用。
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.surfaceDim,
    required this.textSecondary,
  });

  /// 次级表面（如分隔、占位背景）。
  final Color surfaceDim;

  /// 次级文字颜色。
  final Color textSecondary;

  @override
  AppThemeExtension copyWith({
    Color? surfaceDim,
    Color? textSecondary,
  }) {
    return AppThemeExtension(
      surfaceDim: surfaceDim ?? this.surfaceDim,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

/// 从当前 ThemeData 读取扩展。
extension AppThemeX on BuildContext {
  AppThemeExtension get appTheme => Theme.of(this).extension<AppThemeExtension>()!;
}

abstract final class AppTheme {
  /// 统一 iOS 风格圆角与排版。
  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: AppTokens.lightBackground,
        surface: AppTokens.lightSurface,
        surfaceDim: AppTokens.lightSurfaceDim,
        textPrimary: AppTokens.lightTextPrimary,
        textSecondary: AppTokens.lightTextSecondary,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: AppTokens.darkBackground,
        surface: AppTokens.darkSurface,
        surfaceDim: AppTokens.darkSurfaceDim,
        textPrimary: AppTokens.darkTextPrimary,
        textSecondary: AppTokens.darkTextSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceDim,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.accent,
      brightness: brightness,
    );

    final base = ThemeData(brightness: brightness, colorScheme: scheme);
    final textTheme = base.textTheme.apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: scheme.copyWith(
        primary: AppTokens.accent,
        surface: surface,
        onSurface: textPrimary,
        onSecondary: textSecondary,
      ),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusM)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
        thickness: 0.5,
        space: 1,
      ),
      extensions: [
        AppThemeExtension(surfaceDim: surfaceDim, textSecondary: textSecondary),
      ],
    );
  }
}
