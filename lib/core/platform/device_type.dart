import 'package:flutter/widgets.dart';

/// 设备类型：决定导航骨架与迷你条位置。
enum DeviceType { mobile, desktop }

/// 桌面端与移动端切换的宽度断点（横向）。
abstract final class AppBreakpoints {
  static const double desktop = 840;
}

/// 根据可用宽度判断当前设备类型。
DeviceType deviceTypeOf(BoxConstraints constraints) {
  if (constraints.maxWidth >= AppBreakpoints.desktop) return DeviceType.desktop;
  return DeviceType.mobile;
}

/// 便捷：传入 MediaQuery 尺寸。
DeviceType deviceTypeOfSize(Size size) {
  if (size.width >= AppBreakpoints.desktop) return DeviceType.desktop;
  return DeviceType.mobile;
}
