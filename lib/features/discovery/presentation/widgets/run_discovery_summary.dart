import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../application/journey_discovery.dart';
import '../../domain/discovery_catalog.dart';
import 'discovery_progress_track.dart';

/// Sonuç panelinin keşif bölümü.
///
/// İki şey söyler: bu yolculukta neresi yeni keşfedildi ve İstanbul keşfi
/// nereye geldi. Yeni keşif yoksa üstteki bölüm hiç çizilmez — boş bir
/// "Yeni Keşifler" başlığı paneli uzatmaktan başka bir şey yapmaz.
class RunDiscoverySummary extends StatelessWidget {
  const RunDiscoverySummary({
    super.key,
    required this.run,
    required this.accent,
  });

  final JourneyDiscovery run;

  /// Hattın okunabilir rengi.
  final Color accent;

  /// Ad olarak yazılacak en fazla durak sayısı.
  ///
  /// On beş durak alt alta yazılırsa panel ekrana sığmaz ve "tekrar oyna"
  /// düğmesi kaybolur. Üçü yazılır, kalanı sayılır.
  static const int _maxNames = 3;

  @override
  Widget build(BuildContext context) {
    final discovery = run.discovery;
    final fresh = run.newStations;
    final total = discovery.totalCount;
    if (total == 0) return const SizedBox.shrink();

    final gain = fresh.length / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (fresh.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.stack),
          Text('YENİ KEŞİFLER', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          _StationChips(stations: fresh, limit: _maxNames),
          if (run.completedLines.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _CompletedLines(lineIds: run.completedLines, accent: accent),
          ],
        ],
        // Yeniden başlatma koşu defterini sıfırlar; önceki denemede
        // kazanılan duraklar kalıcı kalır ama yukarıdaki listede görünmez.
        // Oyuncu ekrandan ayrılırken eksik bir sayı görmesin.
        if (run.hasHiddenSessionDiscoveries) ...<Widget>[
          const SizedBox(height: AppSpacing.stack),
          Text(
            'Bu oturumda toplam ${run.sessionStationCount} yeni istasyon',
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.stack),
        Semantics(
          label:
              '$total durağın ${discovery.discoveredCount} tanesi keşfedildi'
              '${fresh.isEmpty ? '' : ', bu yolculukta ${fresh.length} yeni'}',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('İstanbul keşfi', style: AppText.caption),
                      const SizedBox(height: 6),
                      DiscoveryProgressTrack(
                        value: discovery.progress,
                        gain: gain,
                        color: AppColors.outline,
                        background: AppColors.boardBackground,
                        thickness: 4,
                        animate: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                ExcludeSemantics(
                  child: Text.rich(
                    TextSpan(
                      text: '${discovery.discoveredCount}',
                      style: AppText.statSmall,
                      children: <InlineSpan>[
                        TextSpan(
                          text: ' / $total',
                          style: AppText.micro.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StationChips extends StatelessWidget {
  const _StationChips({required this.stations, required this.limit});

  final List<CanonicalStation> stations;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final shown = stations.take(limit).toList();
    final rest = stations.length - shown.length;

    return Wrap(
      spacing: AppSpacing.xs + 2,
      runSpacing: AppSpacing.xs + 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final station in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
            ),
            child: Text(
              station.name,
              style: AppText.captionStrong.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        if (rest > 0) Text('+$rest diğer', style: AppText.caption),
      ],
    );
  }
}

class _CompletedLines extends StatelessWidget {
  const _CompletedLines({required this.lineIds, required this.accent});

  final List<String> lineIds;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(Icons.check_circle_rounded, size: 15, color: accent),
        const SizedBox(width: AppSpacing.xs + 2),
        Expanded(
          child: Text(
            '${lineIds.join(", ")} tamamlandı',
            style: AppText.captionStrong.copyWith(color: accent),
          ),
        ),
      ],
    );
  }
}
