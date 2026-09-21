import 'package:flutter/material.dart';

/// 设计令牌：颜色、间距、圆角、字号统一在此定义，禁止硬编码。
abstract final class AppTokens {
  // ---- 间距 ----
  static const double spaceXs = 4;

  /// 微间距：介于 xs 与 s 之间，用于迷你条等紧凑容器的纵向内边距。
  static const double spaceXxs = 6;
  static const double spaceS = 8;
  static const double spaceM = 16;
  static const double spaceL = 24;
  static const double spaceXl = 32;

  // ---- 移动端底部控件 ----
  /// 移动端底栏高度。
  static const double mobileBottomControlHeight = 62;

  /// 迷你播放条略小于底栏，作为轻量的播放状态入口。
  static const double mobileMiniPlayerHeight = 50;

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

  // ---- 玻璃（液态玻璃水感） ----
  /// 玻璃雾化基色：中性灰（iOS systemGray）。浅/深两模式共用同一基色，
  /// 靠透明度合成出「把背景压缩向灰」的水雾：深色上读作柔灰玻璃，浅色上
  /// 读作浅灰玻璃（对标 Apple Music 迷你条），不靠提白发亮。
  static const Color glassFog = Color(0xFF8E8E93);

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
