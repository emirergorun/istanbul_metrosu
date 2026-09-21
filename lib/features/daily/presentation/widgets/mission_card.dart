import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../discovery/presentation/widgets/discovery_progress_track.dart';
import '../../domain/daily_mission.dart';

/// Tek bir günlük görev.
///
/// Onay kutusu **yok**: görev listesi bir yapılacaklar defteri değil. Her
/// görev kendi ilerleme çubuğunu taşıyor ve sayı çubuğun üstünde duruyor —
/// oyuncu "ne kadar kaldı" sorusunu tek bakışta cevaplıyor.
///
/// Renk tek başına durum taşımıyor: biten görev hem yeşile dönüyor hem de
/// başına damga geliyor.
class MissionCard extends StatelessWidget {
  const MissionCard({
    super.key,
    required this.mission,
    required this.progress,
    required this.accent,
  });

  final DailyMission mission;

  /// Kaç birim ilerlendi. [DailyMission.target] ile karşılaştırılır.
  final int progress;

  /// Günün hattından gelen vurgu rengi.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final complete = progress >= mission.target;
    final color = complete ? AppColors.success : accent;

    return Semantics(
      container: true,
      label:
          '${mission.title}. $progress bölü ${mission.target}'
          '${complete ? ', tamamlandı' : ''}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: complete
                  ? AppColors.success.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Damga **yalnızca tamamlanınca** çizilir.
                  //
                  // Boş kutu her satırın başında dururken liste bir
                  // yapılacaklar defterine benziyordu; oyun görevi onay
                  // kutusuyla değil, kazanıldığında basılan bir damgayla
                  // anlatılır. Bitmemiş görevde satır metinle başlıyor,
                  // durum ilerleme çubuğundan okunuyor.
                  if (complete) ...<Widget>[
                    _MissionStamp(color: color),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      mission.title,
                      style: complete
                          ? AppText.body.copyWith(color: AppColors.textPrimary)
                          : AppText.body,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$progress / ${mission.target}',
                    style: AppText.statSmall.copyWith(
                      color: complete
                          ? AppColors.success
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Zemin `outline`, `surfaceHigh` değil: kart zaten `surface`
              // ve iki ton arasındaki fark ekranda görünmüyordu — ilerleme
              // sıfırken çubuğun kendisi kayboluyor, görev "ölçülmüyor" gibi
              // duruyordu. Boş çubuk da bir bilgi: hedef burada.
              DiscoveryProgressTrack(
                value: mission.target == 0 ? 0 : progress / mission.target,
                color: color,
                background: AppColors.outline,
                thickness: 5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Görev damgası — bilet turnikesinden geçmiş gibi.
///
/// Yalnız tamamlanmış görevde çizilir; bkz. [MissionCard].
class _MissionStamp extends StatelessWidget {
  const _MissionStamp({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.check_rounded, size: 14, color: color),
    );
  }
}
