import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/game_state.dart';
import 'overlay_panel.dart';

/// Oyun sonu paneli: hedefe ulaşma, varış veya hamle bitişi.
///
/// Ton nötr tutulur; kaybetme durumunda kullanıcıyı suçlayan/aşırı esprili
/// dil kullanılmaz.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.session,
    required this.accent,
    required this.bestScore,
    required this.isNewBest,
    required this.onRestart,
    required this.onExit,
    required this.onContinue,
  });

  final GameSession session;
  final Color accent;
  final int bestScore;
  final bool isNewBest;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  /// Sadece hedefe ulaşıldığında (endless devam) gösterilir.
  final VoidCallback? onContinue;

  ({String title, String subtitle, IconData icon, Color color}) get _content {
    switch (session.status) {
      case GameStatus.victory:
        return (
          title: 'Challenge tamamlandı',
          subtitle:
              'Hedef skora yolculuk bitmeden ulaştın. İstersen devam edebilirsin.',
          icon: Icons.emoji_events_rounded,
          color: AppColors.success,
        );
      case GameStatus.arrived:
        return (
          title: 'Durağına yaklaştın!',
          subtitle: session.targetReached
              ? 'Yolculuk tamamlandı ve hedefi de geçtin.'
              : 'Yolculuk tamamlandı. Hedefe bu sefer ulaşamadın.',
          icon: Icons.place_rounded,
          color: accent,
        );
      case GameStatus.gameOver:
      default:
        return (
          title: 'Hamle kalmadı',
          subtitle: 'Tahtaya sığacak parça kalmadı. Tekrar deneyebilirsin.',
          icon: Icons.grid_off_rounded,
          color: AppColors.textSecondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;

    return OverlayPanel(
      icon: content.icon,
      accent: content.color,
      title: content.title,
      subtitle: content.subtitle,
      children: <Widget>[
        StatRow(
          label: 'Skor',
          value: Formatters.score(session.score),
          highlight: true,
          accent: content.color,
        ),
        StatRow(label: 'Hedef', value: Formatters.score(session.targetScore)),
        StatRow(
          label: 'Temizlenen satır / sütun',
          value: '${session.clearedRows} / ${session.clearedColumns}',
        ),
        StatRow(
          label: 'En iyi combo',
          value: session.bestCombo > 0 ? 'x${session.bestCombo}' : '—',
        ),
        StatRow(
          label: '${session.journey.difficulty.label} rekoru',
          value: Formatters.score(bestScore),
        ),
        if (isNewBest) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'Yeni rekor!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (onContinue != null) ...<Widget>[
          FilledButton(
            onPressed: onContinue,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Yolculuğa devam et'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onRestart, child: const Text('Tekrar oyna')),
        ] else ...<Widget>[
          FilledButton(
            onPressed: onRestart,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Tekrar oyna'),
          ),
        ],
        TextButton(onPressed: onExit, child: const Text('Yeni rota seç')),
      ],
    );
  }
}
