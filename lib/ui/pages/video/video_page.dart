import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';

/// 视频播放（空白占位，暂不加入导航，仅留文件）。
/// 后续由其他 AI 填充：视频播放能力。
class VideoPage extends StatelessWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.videoPlayer)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_outlined,
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
