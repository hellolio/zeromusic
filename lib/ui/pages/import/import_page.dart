import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/platform/device_type.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/import/import_providers.dart';
import '../../../services/import/import_source.dart';
import '../../../services/import/import_task.dart';
import 'import_source_card.dart';
import 'import_source_sheet.dart';
import 'import_task_tile.dart';

/// 导入页：来源入口卡片网格 + 进行中/失败任务列表。
/// 「本地文件」为真实导入，「云端/蓝牙/WiFi/Mac/Win」为即将支持占位。
///
/// 全部导入完成后不再显示常驻横幅/任务行，改弹一个 3 秒自动消失的通知，
/// 完成的任务行随之从列表移除（仅保留排队/导入中/失败可重试）。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  /// 全部导入完成通知显示的时长，之后自动隐藏。
  static const noticeDuration = Duration(seconds: 3);

  Timer? _noticeTimer;
  bool _noticeVisible = false;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _showAllDoneNotice() {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _noticeVisible = true);
    _noticeTimer = Timer(noticeDuration, () {
      if (mounted) setState(() => _noticeVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 事件驱动：仅在「部分完成 → 全部完成」的这次状态迁移时弹一次通知，
    // 不依赖持久状态，因此从其它页面切回不会重新出现。
    ref.listen(importControllerProvider, (prev, next) {
      if (prev != null && !prev.allDone && next.allDone) {
        _showAllDoneNotice();
      }
    });

    final strings = context.strings;
    final state = ref.watch(importControllerProvider);
    final device = deviceTypeOfSize(MediaQuery.sizeOf(context));
    final sources = ImportSourceX.sourcesFor(device);
    // 已完成的任务不再展示，仅保留排队/导入中/失败可重试。
    final visibleTasks =
        state.tasks.where((t) => !t.isCompleted).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(strings.importTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppTokens.spaceL),
        children: [
          _SectionLabel(strings.importSourcesHeader),
          _buildSourceGrid(context, ref, sources, device),
          if (_noticeVisible) const _AllDoneNotice(),
          if (visibleTasks.isNotEmpty) ...[
            _SectionLabel(strings.importTasksHeader),
            for (final task in visibleTasks) _buildTaskTile(ref, task),
          ] else
            _buildEmpty(context, strings),
        ],
      ),
    );
  }

  Widget _buildSourceGrid(
    BuildContext context,
    WidgetRef ref,
    List<ImportSource> sources,
    DeviceType device,
  ) {
    final crossAxisCount = device == DeviceType.desktop ? 4 : 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceM),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppTokens.spaceM,
        crossAxisSpacing: AppTokens.spaceM,
        childAspectRatio: 1.35,
        children: [
          for (final source in sources)
            ImportSourceCard(
              source: source,
              onTap: () => _onSourceTap(context, ref, source),
            ),
        ],
      ),
    );
  }

  void _onSourceTap(BuildContext context, WidgetRef ref, ImportSource source) {
    if (source.isAvailable) {
      ref.read(importControllerProvider.notifier).startLocalImport();
    } else {
      showImportComingSoonSheet(context, source: source);
    }
  }

  Widget _buildTaskTile(WidgetRef ref, ImportTask task) {
    return ImportTaskTile(
      task: task,
      onRetry: () => ref.read(importControllerProvider.notifier).retry(task.id),
    );
  }

  Widget _buildEmpty(BuildContext context, AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.cloud_download,
            size: 48,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
          const SizedBox(height: AppTokens.spaceM),
          Text(
            strings.importEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// 「全部导入完成」瞬时通知：淡入 + 微弹，3 秒后自动消失。
class _AllDoneNotice extends StatelessWidget {
  const _AllDoneNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animate = !MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: animate ? AppCurves.standardMotion : Duration.zero,
      switchInCurve: AppCurves.spring,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Padding(
        key: const ValueKey('allDoneNotice'),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceM,
          0,
          AppTokens.spaceM,
          AppTokens.spaceS,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.spaceM),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                size: 20,
                color: Color(0xFF30D158),
              ),
              const SizedBox(width: AppTokens.spaceS),
              Text(
                context.strings.importAllDone,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组小标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceM,
        AppTokens.spaceM,
        AppTokens.spaceM,
        AppTokens.spaceS,
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
      ),
    );
  }
}