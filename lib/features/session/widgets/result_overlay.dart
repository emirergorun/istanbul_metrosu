import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import 'overlay_panel.dart';

/// Oyun sonu paneli — **her oyun için ortak**.
///
/// İki bitiş vardır ve tonları bilinçli olarak farklıdır:
///
/// - **Varış** (`isArrival`) yolculuğun finalidir ve her zaman kutlanır;
///   rota rekoru da geçildiyse ayrıca rozet çıkar.
/// - **Oyun bitişi** sade ve nötrdür. Varışın değerli olması için varamama
///   ihtimalinin görünür kalması gerekir.
///
/// Oyuna özgü istatistikler [extraStats] ile verilir; panel bunların ne
/// olduğunu bilmez. Blok oyunu "temizlenen satır/sütun" ve "en iyi combo"
/// gönderir, başka bir oyun bambaşka satırlar gönderebilir.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.isArrival,
    required this.destinationName,
    required this.score,
    required this.recordToBeat,
    required this.isFirstRun,
    required this.recordBeaten,
    required this.accent,
    required this.isNewBest,
    required this.onRestart,
    required this.onExit,
    this.extraStats = const <Widget>[],
    this.gameOverTitle = 'Oyun bitti',
    this.gameOverSubtitle = 'Durağa varamadan oyun bitti.',
    this.showBackdrop = true,
  });

  /// Varış mı, yoksa oyunun kendi kurallarıyla mı bitti?
  final bool isArrival;

  final String destinationName;
  final int score;
  final int recordToBeat;
  final bool isFirstRun;
  final bool recordBeaten;
  final Color accent;
  final bool isNewBest;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  /// Oyuna özgü istatistik satırları ([StatRow] beklenir).
  final List<Widget> extraStats;

  /// Varış dışı bitişin metni. Her oyunun kendi kaybetme koşulu var:
  /// blok oyununda "hamle kalmadı", başka bir oyunda başka bir şey.
  final String gameOverTitle;
  final String gameOverSubtitle;

  /// Varış sahnesi kendi karartmasını çizer.
  final bool showBackdrop;

  @override
  Widget build(BuildContext context) {
    return OverlayPanel(
      showBackdrop: showBackdrop,
      icon: isArrival ? Icons.where_to_vote_rounded : Icons.grid_off_rounded,
      accent: isArrival ? accent : AppColors.textSecondary,
      title: isArrival ? 'DURAĞA GELDİN' : gameOverTitle,
      subtitle: isArrival
          ? '$destinationName durağındasın. Yolculuğu tamamladın.'
          : gameOverSubtitle,
      children: <Widget>[
        if (recordBeaten) ...<Widget>[
          _ChallengeBadge(accent: accent),
          const SizedBox(height: AppSpacing.md),
        ],
        StatRow(
          label: 'Skor',
          value: Formatters.score(score),
          highlight: true,
          accent: isArrival ? accent : AppColors.textPrimary,
        ),
        StatRow(
          label: isFirstRun ? 'Bu rotada' : 'Rota rekoru',
          value: isFirstRun ? 'İlk yolculuk' : Formatters.score(recordToBeat),
        ),
        ...extraStats,
        if (!recordBeaten && !isFirstRun)
          StatRow(
            label: 'Rekora kalan',
            value: Formatters.score(
              (recordToBeat - score).clamp(0, recordToBeat),
            ),
          ),
        if (isNewBest) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          const _NewRecordBadge(),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onRestart,
          style: FilledButton.styleFrom(
            backgroundColor: isArrival ? accent : AppColors.brandNavy,
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
  const _NewRecordBadge();

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
