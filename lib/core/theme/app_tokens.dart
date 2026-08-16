import 'package:flutter/material.dart';

/// 设计令牌：颜色、间距、圆角、字号统一在此定义，禁止硬编码。
abstract final class AppTokens {
  // ---- 间距 ----
  static const double spaceXs = 4;
  static const double spaceS = 8;
  static const double spaceM = 16;
  static const double spaceL = 24;
  static const double spaceXl = 32;

  // ---- 圆角 ----
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 20;
  static const double radiusPill = 999;

  // ---- 字号 ----
  static const double fontSizeCaption = 12;
  static const double fontSizeBody = 14;
  static const double fontSizeTitle = 17;
  static const double fontSizeHeadline = 22;
  static const double fontSizeDisplay = 34;

  // ---- 语义色（跟随主题的明亮色） ----
  static const Color accent = Color(0xFF0A84FF);
  static const Color favorite = Color(0xFFFF2D55);
  static const Color lyricsHighlight = Color(0xFF0A84FF);

  // ---- 浅色 ----
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceDim = Color(0xFFE5E5EA);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF8E8E93);

  // ---- 深色 ----
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceDim = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);
}
