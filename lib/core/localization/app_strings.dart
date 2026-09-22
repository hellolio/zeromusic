import 'package:flutter/widgets.dart';

/// 应用内字符串基类，各语言实现 getter。
abstract class AppStrings {
  const AppStrings();

  // ---- 导航 ----
  String get navPlaylist;
  String get navImport;
  String get navSettings;
  String get navPlayer;

  // ---- 通用 ----
  String get appName;
  String get cancel;
  String get confirm;
  String get delete;
  String get edit;
  String get save;
  String get empty;

  // ---- 播放列表页 ----
  String get libraryTitle;
  String get search;
  String get tabAll;
  String get tabArtists;
  String get tabFavorites;
  String get tabRecent;
  String get tabTags;
  String get favorite;
  String get unfavorite;
  String get tagSong;
  String get newTag;
  String get manageTags;
  String get addToQueue;
  String get batchEdit;
  String get selectAll;
  String get deselectAll;
  String get selectedCount;
  String get batchEditHint;
  String get songTitle;
  String get songArtist;
  String get songAlbum;
  String get songGenre;
  String get deleteConfirmTitle;
  String get deleteConfirmMessage;
  String get noResult;

  // ---- 播放页 ----
  String get playerUpNext;
  String get playerLyrics;
  String get playerNoLyrics;
  String get lyricsAdd;
  String get lyricsEdit;
  String get lyricsHint;
  String get lyricsInvalid;
  String get lyricsBackToPlayer;
  String get playerQueue;
  String get playerComingSoon;
  String get playerRepeatOff;
  String get playerRepeatAll;
  String get playerRepeatOne;
  String get playerShuffle;
  String get playerVolume;
  String get playerSleepTimer;
  String get playerSleepOff;
  String sleepTimerMinutes(int minutes);

  // ---- 迷你播放条 ----
  String get miniPrevious;
  String get miniNext;
  String get miniPlayPause;

  // ---- 导入页 ----
  String get importCloud;
  String get importBluetooth;
  String get importWifi;
  String get importMac;
  String get importWindows;
  String get importLocalFile;
  String get importTitle;
  String get importSourcesHeader;
  String get importTasksHeader;
  String get importEmpty;
  String get importQueued;
  String get importImporting;
  String get importDone;
  String get importFailed;
  String get importRetry;
  String get importAllDone;
  String get importComingSoon;

  // ---- 设置页 ----
  String get settingsAppearance;
  String get settingsTheme;
  String get settingsThemeLight;
  String get settingsThemeDark;
  String get settingsThemeSystem;
  String get settingsLanguage;
  String get settingsPlayback;
  String get settingsDefaultVolume;
  String get settingsEqualizer;
  String get eqEnable;
  String get eqOn;
  String get eqOff;
  String get eqUnsupported;
  String get eqUnsupportedHint;
  String get eqPlayToEnable;
  String get eqReset;
  String get eqPresetFlat;
  String get eqPresetPop;
  String get eqPresetRock;
  String get eqPresetJazz;
  String get eqPresetClassical;
  String get eqPresetElectronic;
  String get settingsBackground;
  String get bgEffectPowerSaver;
  String get bgEffectBalanced;
  String get bgEffectVivid;
  String get settingsVersion;
  String get settingsOpenSourceLicenses;
  String get settingsAbout;

  // ---- 视频 ----
  String get videoPlayer;

  // ---- 桌面歌词（桌面端专属） ----
  String get settingsDesktop;
  String get desktopLyricsFontSize;
  String get desktopLyricsFontSmall;
  String get desktopLyricsFontMedium;
  String get desktopLyricsFontLarge;
  String get desktopLyricsResetPosition;
  String get desktopLyricsNotPlaying;
  String get desktopLyricsInterlude;
}

/// 通过 BuildContext 访问当前语言字符串。
extension AppStringsX on BuildContext {
  AppStrings get strings => Localizations.of<AppStrings>(this, AppStrings)!;
}
