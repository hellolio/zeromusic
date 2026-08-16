import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/import/import_task.dart';

/// 单条导入任务行：文件名 + 平滑进度条 + 状态图标（✓ 淡入微弹 / ⚠️ 可重试）。
/// 仅展示排队中 / 导入中 / 失败的任务；完成的任务由导入页在任务完成时立即
/// 从列表移除，改由全局 SnackBar 通知。
class ImportTaskTile extends StatelessWidget {
  const ImportTaskTile({
    super.key,
    required this.task,
    required this.onRetry,
  });

  final ImportTask task;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final progress = task.progress.clamp(0.0, 1.0);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceM,
        vertical: AppTokens.spaceS,
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: animate ? AppCurves.quickMotion : Duration.zero,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: _StatusIcon(task: task, animate: animate, accent: accent),
          ),
          const SizedBox(width: AppTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fileName(theme, strings),
                _progressArea(theme, progress, accent, animate),
                _statusRow(theme, strings, progress),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressArea(
    ThemeData theme,
    double progress,
    Color accent,
    bool animate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        ClipRRect(
          key: const ValueKey('taskProgressBar'),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          child: SizedBox(
            height: 6,
            width: double.infinity,
            child: Stack(
              children: [
                Container(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    duration: animate ? AppCurves.quickMotion : Duration.zero,
                    curve: AppCurves.standard,
                    child: Container(
                      color: task.isFailed ? AppTokens.favorite : accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _fileName(ThemeData theme, AppStrings strings) {
    return Row(
      children: [
        Flexible(
          child: Text(
            task.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(ThemeData theme, AppStrings strings, double progress) {
    final pct = (progress * 100).round();
    final text = task.isFailed
        ? strings.importFailed
        : task.isCompleted
            ? strings.importDone
            : task.isActive
                ? strings.importImporting
                : strings.importQueued;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: task.isFailed
                  ? AppTokens.favorite
                  : theme.colorScheme.onSecondary,
            ),
          ),
        ),
        if (task.isFailed)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 14),
            label: Text(strings.importRetry),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          )
        else
          Text(
            '$pct%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// 状态图标：导入中=进度圈，完成=✓ 微弹淡入，失败=⚠️。
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.task,
    required this.animate,
    required this.accent,
  });

  final ImportTask task;
  final bool animate;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    if (task.isCompleted) {
      icon = Icon(
        CupertinoIcons.checkmark_alt_circle_fill,
        size: 26,
        color: const Color(0xFF30D158),
      );
    } else if (task.isFailed) {
      icon = Icon(
        CupertinoIcons.exclamationmark_triangle_fill,
        size: 26,
        color: AppTokens.favorite,
      );
    } else {
      icon = CircularProgressIndicator(
        // 确定性进度圈：随任务进度变化，避免无限动画（尊重减弱动效）。
        value: task.progress.clamp(0.0, 1.0),
        strokeWidth: 3,
        color: accent,
      );
    }
    return SizedBox(
      width: 30,
      height: 30,
      child: Center(
        child: AnimatedScale(
          scale: animate && task.isCompleted ? 0.6 : 1,
          duration: animate ? AppCurves.standardMotion : Duration.zero,
          curve: AppCurves.spring,
          child: KeyedSubtree(key: ValueKey(task.status), child: icon),
        ),
      ),
    );
  }
}