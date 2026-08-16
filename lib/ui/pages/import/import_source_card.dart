import 'package:flutter/material.dart';

import '../../../core/anim/app_curves.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../services/import/import_source.dart';

/// 来源入口卡片：iOS 风渐变卡片 + CupertinoIcons + 按压缩放反馈 + 桌面悬停。
class ImportSourceCard extends StatefulWidget {
  const ImportSourceCard({super.key, required this.source, required this.onTap});

  final ImportSource source;
  final VoidCallback onTap;

  @override
  State<ImportSourceCard> createState() => _ImportSourceCardState();
}

class _ImportSourceCardState extends State<ImportSourceCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final source = widget.source;
    final available = source.isAvailable;
    final animate = !MediaQuery.disableAnimationsOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: animate ? AppCurves.quickMotion : Duration.zero,
          curve: AppCurves.spring,
          child: AnimatedContainer(
            duration: animate ? AppCurves.quickMotion : Duration.zero,
            curve: AppCurves.standard,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  for (final c in source.gradient)
                    c.withValues(alpha: available ? 1 : 0.45),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.18 : 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  bottom: -22,
                  child: Icon(
                    source.icon,
                    size: 92,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.spaceS),
                          child: Icon(
                            source.icon,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              source.label(strings),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (!available) ...[
                            const SizedBox(width: AppTokens.spaceS),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.spaceS,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                              ),
                              child: Text(
                                strings.importComingSoon,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}