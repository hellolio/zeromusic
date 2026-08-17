import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../services/import/import_source.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';

/// 「即将支持」来源弹层：占位说明 + 关闭。
/// 后续接入真实传输（云盘/蓝牙/WiFi/局域网）时替换为选文件/授权界面。
Future<void> showImportComingSoonSheet(
  BuildContext context, {
  required ImportSource source,
}) {
  final strings = context.strings;
  return showCenterPopup<void>(
    context,
    child: GlassOverlay(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 36),
          const SizedBox(height: 12),
          Text(
            source.label(context.strings),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            strings.importComingSoon,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.confirm),
          ),
        ],
      ),
    ),
  );
}