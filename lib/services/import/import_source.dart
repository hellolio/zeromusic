import 'package:flutter/cupertino.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/device_type.dart';

/// 导入来源。真实传输能力逐个接入；当前仅 [localFile] 可用，其余为「即将支持」占位。
enum ImportSource {
  cloud,
  bluetooth,
  wifi,
  mac,
  windows,
  localFile,
}

extension ImportSourceX on ImportSource {
  /// 本地化名称。
  String label(AppStrings strings) {
    return switch (this) {
      ImportSource.cloud => strings.importCloud,
      ImportSource.bluetooth => strings.importBluetooth,
      ImportSource.wifi => strings.importWifi,
      ImportSource.mac => strings.importMac,
      ImportSource.windows => strings.importWindows,
      ImportSource.localFile => strings.importLocalFile,
    };
  }

  /// 是否已具备真实导入能力（仅本机文件）。
  bool get isAvailable => this == ImportSource.localFile;

  /// 入库时写入的内置来源标签（与《07_数据库设计》4.2 保持一致）。
  String get sourceTag {
    return '来源:${switch (this) {
          ImportSource.cloud => '云端',
          ImportSource.bluetooth => '蓝牙',
          ImportSource.wifi => 'WiFi',
          ImportSource.mac => 'Mac',
          ImportSource.windows => 'Windows',
          ImportSource.localFile => '本地文件',
        }}';
  }

  IconData get icon {
    return switch (this) {
      ImportSource.cloud => CupertinoIcons.cloud,
      ImportSource.bluetooth => CupertinoIcons.bluetooth,
      ImportSource.wifi => CupertinoIcons.wifi,
      ImportSource.mac => CupertinoIcons.desktopcomputer,
      ImportSource.windows => CupertinoIcons.square_grid_2x2,
      ImportSource.localFile => CupertinoIcons.folder,
    };
  }

  /// 卡片渐变配色（明亮色，深浅主题通用）。
  List<Color> get gradient {
    return switch (this) {
      ImportSource.cloud => const [Color(0xFF64D2FF), Color(0xFF0A84FF)],
      ImportSource.bluetooth => const [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
      ImportSource.wifi => const [Color(0xFF30D158), Color(0xFF64D2FF)],
      ImportSource.mac => const [Color(0xFF9C9CA1), Color(0xFF5E5CE6)],
      ImportSource.windows => const [Color(0xFF5E5CE6), Color(0xFFBF5AF2)],
      ImportSource.localFile => const [Color(0xFFFF9F0A), Color(0xFFFF6482)],
    };
  }

  /// 当前设备类型展示哪些来源。
  static List<ImportSource> sourcesFor(DeviceType device) {
    // 移动端与桌面端展示一致：云端/蓝牙/WiFi/Mac/Win + 本机文件
    // （桌面端不再裁剪，全部入口可见；仅 [localFile] 已接入真实导入）。
    if (device == DeviceType.desktop) {
      return const [
        ImportSource.cloud,
        ImportSource.bluetooth,
        ImportSource.wifi,
        ImportSource.mac,
        ImportSource.windows,
        ImportSource.localFile,
      ];
    }
    return const [
      ImportSource.cloud,
      ImportSource.bluetooth,
      ImportSource.wifi,
      ImportSource.mac,
      ImportSource.windows,
      ImportSource.localFile,
    ];
  }
}