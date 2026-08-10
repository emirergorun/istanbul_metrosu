import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';

/// Oyun ekranının üst bilgi alanı: skor, hedef, combo, pause.
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.score,
    required this.targetScore,
    required this.combo,
    required this.targetProgress,
    required this.accent,
    required this.onPause,
    required this.onUndo,
    required this.canUndo,
    required this.undoLeft,
  });

  final int score;
  final int targetScore;
  final int combo;
  final double targetProgress;
  final Color accent;
  final VoidCallback onPause;
  final VoidCallback onUndo;
  final bool canUndo;
  final int undoLeft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'SKOR',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        Formatters.score(score),
                        style: const TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          '/ ${Formatters.score(targetScore)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (combo >= 2) _ComboChip(combo: combo, accent: accent),
            if (undoLeft > 0) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              _HudButton(
                icon: Icons.undo_rounded,
                tooltip: 'Geri al ($undoLeft)',
                onPressed: canUndo ? onUndo : null,
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            _HudButton(
              icon: Icons.pause_rounded,
              tooltip: 'Duraklat',
              onPressed: onPause,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: targetProgress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.surfaceHigh,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }
}

class _ComboChip extends StatelessWidget {
  const _ComboChip({required this.combo, required this.accent});

  final int combo;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.bolt_rounded, size: 15, color: accent),
            const SizedBox(width: 2),
            Text(
              'x$combo',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: enabled ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
