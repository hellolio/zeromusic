import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';

/// 设置页面（空白占位）。
/// 后续由其他 AI 填充：主题、语言（中/英/日）、减弱动效等。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.navSettings)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
            const SizedBox(height: AppTokens.spaceM),
            Text(
              strings.empty,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
