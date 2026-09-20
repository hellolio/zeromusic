import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/app_providers.dart';
import '../../../services/lyrics/lrc_parser.dart';
import '../../components/center_popup.dart';
import '../../components/glass_overlay.dart';

/// 添加/编辑歌词弹窗：粘贴 LRC 文本，保存前校验可解析性。
///
/// 校验通过后写入 [LyricsRepository]；无有效歌词行时内联提示且不关闭。
Future<void> showLyricsEditor(
  BuildContext context,
  WidgetRef ref,
  int songId, {
  String? initial,
}) async {
  final result = await showCenterPopup<String>(
    context,
    child: _LyricsEditorBody(initial: initial),
  );
  if (result == null) return;
  await ref
      .read(lyricsRepositoryProvider)
      .saveLyrics(songId, result);
}

class _LyricsEditorBody extends StatefulWidget {
  const _LyricsEditorBody({this.initial});

  final String? initial;

  @override
  State<_LyricsEditorBody> createState() => _LyricsEditorBodyState();
}

class _LyricsEditorBodyState extends State<_LyricsEditorBody> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (parseLrc(text).isEmpty) {
      setState(() => _error = context.strings.lyricsInvalid);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isEdit = (widget.initial ?? '').isNotEmpty;
    return GlassOverlay(
      radius: AppTokens.radiusL,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceL,
              AppTokens.spaceM,
              AppTokens.spaceL,
              AppTokens.spaceS,
            ),
            child: Text(
              isEdit ? strings.lyricsEdit : strings.lyricsAdd,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceL,
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 8,
              minLines: 4,
              decoration: InputDecoration(
                hintText: strings.lyricsHint,
                errorText: _error,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusM),
                ),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceL,
              AppTokens.spaceM,
              AppTokens.spaceL,
              AppTokens.spaceM,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                const SizedBox(width: AppTokens.spaceS),
                FilledButton(
                  key: const ValueKey('lyrics-editor-save'),
                  onPressed: _save,
                  child: Text(strings.save),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}