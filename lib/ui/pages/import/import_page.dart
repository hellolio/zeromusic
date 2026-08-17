import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/platform/device_type.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/import/import_providers.dart';
import '../../../services/import/import_source.dart';
import '../../../services/import/import_task.dart';
import '../../components/top_notification.dart';
import 'import_source_card.dart';
import 'import_source_sheet.dart';
import 'import_task_tile.dart';

/// 导入页：来源入口卡片网格 + 进行中/失败任务列表。
/// 「本地文件」为真实导入，「云端/蓝牙/WiFi/Mac/Win」为即将支持占位。
///
/// 全部导入完成后不再显示常驻横幅/任务行，改弹一个位于页面顶部的
/// 下滑式通知卡片（toast 样式），完成的任务行随之从列表移除。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  /// 当前显示中的「全部导入完成」通知（可再次触发时先移除旧的）。
  OverlayEntry? _activeNotice;

  /// 页面根节点 key，用于读取页面渲染盒中心，让通知相对页面而不是整个窗口居中。
  final GlobalKey _pageKey = GlobalKey();

  @override
  void dispose() {
    _activeNotice?.remove();
    _activeNotice = null;
    super.dispose();
  }

  void _showAllDoneNotice() {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    _activeNotice?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (entryCtx) {
        // 桌面端左侧栏不计入：以页面渲染盒中心为基准，把通知横向平移过去，
        // 移动端页面与窗口同宽，偏移为 0，行为不变。
        final box = _pageKey.currentContext?.findRenderObject();
        final pageCenterDx = box is RenderBox
            ? box.localToGlobal(box.size.center(Offset.zero)).dx
            : MediaQuery.sizeOf(entryCtx).width / 2;
        final shiftX = pageCenterDx - MediaQuery.sizeOf(entryCtx).width / 2;
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: Transform.translate(
              offset: Offset(shiftX, 0),
              child: TopNotification(
                key: const ValueKey('allDoneNotice'),
                message: entryCtx.strings.importAllDone,
                duration: const Duration(seconds: 3),
                onDismissed: () {
                  if (identical(_activeNotice, entry)) {
                    _activeNotice = null;
                  }
                  entry.remove();
                },
              ),
            ),
          ),
        );
      },
    );
    _activeNotice = entry;
    overlay.insert(entry);
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
      key: _pageKey,
      appBar: AppBar(title: Text(strings.importTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppTokens.spaceL),
        children: [
          _SectionLabel(strings.importSourcesHeader),
          _buildSourceGrid(context, ref, sources, device),
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