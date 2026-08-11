import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/game_state.dart';
import 'overlay_panel.dart';

/// Oyun sonu paneli.
///
/// İki bitiş vardır ve tonları bilinçli olarak farklıdır:
///
/// - **Varış** (`arrived`) oyunun finalidir ve her zaman kutlanır; hedef de
///   geçildiyse ayrıca "Challenge tamamlandı" rozeti çıkar.
/// - **Hamle bitişi** (`gameOver`) sade ve nötrdür. Varışın değerli olması
///   için varamama ihtimalinin görünür kalması gerekir.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.session,
    required this.accent,
    required this.bestScore,
    required this.isNewBest,
    required this.onRestart,
    required this.onExit,
    this.showBackdrop = true,
  });

  final GameSession session;
  final Color accent;
  final int bestScore;
  final bool isNewBest;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  /// Varış sahnesi kendi karartmasını çizer.
  final bool showBackdrop;

  bool get _isArrival => session.status == GameStatus.arrived;

  @override
  Widget build(BuildContext context) {
    final title = _isArrival ? 'DURAĞA GELDİN' : 'Hamle kalmadı';
    final subtitle = _isArrival
        ? '${session.journey.destination.name} durağındasın. '
              'Yolculuğu tamamladın.'
        : 'Tahtaya sığacak parça kalmadı, durağa varamadın.';

    return OverlayPanel(
      showBackdrop: showBackdrop,
      icon: _isArrival ? Icons.where_to_vote_rounded : Icons.grid_off_rounded,
      accent: _isArrival ? accent : AppColors.textSecondary,
      title: title,
      subtitle: subtitle,
      children: <Widget>[
        if (session.recordBeaten) ...<Widget>[
          _ChallengeBadge(accent: accent),
          const SizedBox(height: AppSpacing.md),
        ],
        StatRow(
          label: 'Skor',
          value: Formatters.score(session.score),
          highlight: true,
          accent: _isArrival ? accent : AppColors.textPrimary,
        ),
        StatRow(
          label: session.isFirstRun ? 'Bu rotada' : 'Rota rekoru',
          value: session.isFirstRun
              ? 'İlk yolculuk'
              : Formatters.score(session.recordToBeat),
        ),
        StatRow(
          label: 'Temizlenen satır / sütun',
          value: '${session.clearedRows} / ${session.clearedColumns}',
        ),
        StatRow(
          label: 'En iyi combo',
          value: session.bestCombo > 0 ? 'x${session.bestCombo}' : '—',
        ),
        if (!session.recordBeaten && !session.isFirstRun)
          StatRow(
            label: 'Rekora kalan',
            value: Formatters.score(
              (session.recordToBeat - session.score).clamp(
                0,
                session.recordToBeat,
              ),
            ),
          ),
        if (isNewBest) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _NewRecordBadge(),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onRestart,
          style: FilledButton.styleFrom(
            backgroundColor: _isArrival ? accent : AppColors.brandNavy,
          ),
          child: const Text('TEKRAR OYNA'),
        ),
        TextButton(onPressed: onExit, child: const Text('Yeni rota seç')),
      ],
    );
  }
}

/// Rota rekoru geçildiyse eklenen ikinci katman.
class _ChallengeBadge extends StatelessWidget {
  const _ChallengeBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.check_circle_rounded, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Rekorunu geçtin',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewRecordBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
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
    );
  }
}
