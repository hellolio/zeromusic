import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';

/// 播放页面（空白占位，全屏）。
/// 后续由其他 AI 填充：节拍变色背景、播放控制、队列、歌词。
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: strings.cancel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(strings.navPlayer),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
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
