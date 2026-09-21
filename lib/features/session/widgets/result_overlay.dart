import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../discovery/application/journey_discovery.dart';
import '../../discovery/presentation/widgets/run_discovery_summary.dart';
import '../../journey/models/journey.dart';
import '../../social/presentation/widgets/challenge_result_section.dart';
import 'overlay_panel.dart';
import 'run_rewards_summary.dart';
import '../../../core/widgets/pressable.dart';

/// Oyun sonu paneli — **her oyun için ortak**.
///
/// İki bitiş vardır ve tonları bilinçli olarak farklıdır:
///
/// - **Varış** (`isArrival`) yolculuğun finalidir ve her zaman kutlanır;
///   rota rekoru da geçildiyse ayrıca rozet çıkar.
/// - **Oyun bitişi** sade ve nötrdür. Varışın değerli olması için varamama
///   ihtimalinin görünür kalması gerekir.
///
/// Yolculuk oyundan uzun yaşadığı için oyun bitişinin iki hâli var: yolculuk
/// sürüyorsa ([journeyContinues]) panel bir ara duraktır — puan ve kalan süre
/// durur, oyuncu aynı oyunu yeniden başlatır ya da başka oyuna geçer. Rekor
/// satırları o hâlde gösterilmez: rekor yolculuğun sonunda belli olur.
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
    this.discovery,
    this.journey,
    this.gameId,
    this.onShare,
    this.gameOverTitle = 'Oyun bitti',
    this.gameOverSubtitle = 'Durağa varamadan oyun bitti.',
    this.showBackdrop = true,
    this.journeyContinues = false,
    this.remainingSeconds,
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

  /// Bu yolculuğun keşif defteri. `null` ise keşif bölümü çizilmez.
  ///
  /// Yarım kalan yolculuk da keşif gösterir: ulaşılan duraklar kalıcıdır,
  /// oyunun nasıl bittiği bunu değiştirmez.
  final JourneyDiscovery? discovery;

  /// Oynanan rota ve oyun.
  ///
  /// İkisi birden verilirse sonuç paneli sosyal bölümü de çizer: meydan
  /// okuma oynandıysa karşılaştırma ve rövanş, normal koşuysa "arkadaşına
  /// meydan oku". Verilmezse panel bugünkü hâliyle kalır.
  final Journey? journey;
  final String? gameId;

  /// Sonucu paylaşma. Verilmezse düğme çizilmez.
  ///
  /// İkincil eylem olarak duruyor: birincil eylem her zaman "tekrar
  /// oyna" — paylaşmak oyuncunun değil ürünün isteği, o yüzden yolu
  /// kapatmıyor ama önüne de geçmiyor.
  final VoidCallback? onShare;

  /// Varış dışı bitişin metni. Her oyunun kendi kaybetme koşulu var:
  /// blok oyununda "hamle kalmadı", başka bir oyunda başka bir şey.
  final String gameOverTitle;
  final String gameOverSubtitle;

  /// Varış sahnesi kendi karartmasını çizer.
  final bool showBackdrop;

  /// Oyun bitti ama yolculuk sürüyor mu?
  final bool journeyContinues;

  /// Yolculukta kalan süre; yalnızca [journeyContinues] iken gösterilir.
  final int? remainingSeconds;

  @override
  Widget build(BuildContext context) {
    return OverlayPanel(
      showBackdrop: showBackdrop,
      icon: isArrival ? Icons.where_to_vote_rounded : Icons.grid_off_rounded,
      accent: isArrival ? accent : AppColors.textSecondary,
      title: isArrival ? 'DURAĞA GELDİN' : gameOverTitle,
      subtitle: isArrival
          ? '$destinationName durağındasın. Yolculuğu tamamladın.'
          : journeyContinues
          ? '$gameOverSubtitle Yolculuk sürüyor: skorun ve kalan süren duruyor.'
          : gameOverSubtitle,
      children: <Widget>[
        if (recordBeaten && !journeyContinues) ...<Widget>[
          _ChallengeBadge(accent: accent),
          const SizedBox(height: AppSpacing.stack),
        ],
        StatRow(
          label: journeyContinues ? 'Yolculuk skoru' : 'Skor',
          value: Formatters.score(score),
          highlight: true,
          accent: isArrival ? accent : AppColors.textPrimary,
        ),
        if (journeyContinues && remainingSeconds != null)
          StatRow(
            label: 'Kalan yolculuk',
            value: Formatters.remaining(remainingSeconds!),
          )
        else
          StatRow(
            label: isFirstRun ? 'Bu rotada' : 'Rota rekoru',
            value: isFirstRun ? 'İlk yolculuk' : Formatters.score(recordToBeat),
          ),
        ...extraStats,
        // Rekor yolculuğun sonunda belli olur; ara durakta rekor satırı
        // oyuncuyu yolculuk bitmiş sanmaya iter.
        if (!journeyContinues && !recordBeaten && !isFirstRun)
          StatRow(
            label: 'Rekora kalan',
            value: Formatters.score(
              (recordToBeat - score).clamp(0, recordToBeat),
            ),
          ),
        if (isNewBest && !journeyContinues) ...<Widget>[
          const SizedBox(height: AppSpacing.stack),
          const _NewRecordBadge(),
        ],
        if (discovery != null)
          RunDiscoverySummary(run: discovery!, accent: accent),
        // Günlük görev, seri ve başarım ödülleri **toplu** olarak burada.
        // Panel bunların ne olduğunu bilmez; ödül yoksa hiç çizilmez.
        RunRewardsSummary(accent: accent),
        // Sosyal çıkış: meydan okuma sonucu ya da yeni meydan okuma.
        if (journey != null && gameId != null)
          ChallengeResultSection(
            score: score,
            journey: journey!,
            gameId: gameId!,
            accent: accent,
          ),
        // Bilgi bitti, eylemler başlıyor.
        const SizedBox(height: AppSpacing.sectionGap),
        // Birincil eylem her hatta ve her bitişte aynı: `theme.dart`'taki
        // hiyerarşi kuralı gereği hat rengi kimliktir, aksiyon rengi değil.
        // Kutlama tonu butondan değil, yukarıdaki rozetlerden ve accent'li
        // skor satırından geliyor.
        // Üç eylem de aynı boşlukla ayrılıyor. Önce hiç boşluk yoktu ve
        // düğmeler birbirine yapışık duruyordu; hiyerarşi aralıktan değil
        // düğmenin kendi ağırlığından geliyor (dolu, çerçeveli, düz).
        FilledButton(
          onPressed: AppFeedback.onTap(context, onRestart),
          child: const Text('TEKRAR OYNA'),
        ),
        if (onShare != null && !journeyContinues) ...<Widget>[
          const SizedBox(height: AppSpacing.stack),
          OutlinedButton(
            onPressed: AppFeedback.onTap(context, onShare!),
            child: const Text('SONUCU PAYLAŞ'),
          ),
        ],
        const SizedBox(height: AppSpacing.stack),
        TextButton(
          onPressed: AppFeedback.onTap(context, onExit),
          child: const Text('Başka oyun seç'),
        ),
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
            style: AppText.bodyStrong.copyWith(color: accent),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
          SizedBox(width: AppSpacing.sm),
          Text(
            'Yeni rekor',
            style: AppText.bodyStrong.copyWith(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}
