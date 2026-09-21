import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../journey/models/journey.dart';

/// Oyun sırasındaki meydan okuma işareti.
///
/// Tek satır, HUD'un kenarında: hedef ve aradaki fark. Meydan okuma modu
/// **görünmeli** ama oyunun önüne geçmemeli — ekranın ortasına konan bir
/// sosyal panel, oynanan şeyi örter.
///
/// Fark canlı gösteriliyor çünkü oyuncunun asıl sorusu bu: *geçtim mi?*
/// Hedefin kendisi başta ve sonda zaten yazılı; oyun sırasında gereken
/// tek bilgi kalan mesafe.
///
/// Meydan okuma modunda değilse hiç çizilmiyor ve HUD bugünkü hâlinde
/// kalıyor.
class ChallengeHudBadge extends StatelessWidget {
  const ChallengeHudBadge({
    super.key,
    required this.journey,
    required this.gameId,
    required this.score,
  });

  final Journey journey;
  final String gameId;
  final int score;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).challengeSession;
    final target = session?.targetFor(gameId, journey);
    if (target == null) return const SizedBox.shrink();

    final ahead = score > target;
    final remaining = target - score;
    // Üç durum, üç renk ve **üç ayrı metin**: renk tek başına bilgi
    // taşımıyor.
    final (Color color, String text) = ahead
        ? (AppColors.success, 'ÖNDESİN')
        : remaining <= target * 0.1
        ? (AppColors.warning, '${Formatters.score(remaining)} kaldı')
        : (AppColors.textSecondary, 'HEDEF ${Formatters.score(target)}');

    return Semantics(
      liveRegion: true,
      label: ahead
          ? 'Meydan okuma: hedefi geçtin'
          : 'Meydan okuma: hedefe ${Formatters.score(remaining)} kaldı',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.flag_rounded, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                text,
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.display,
                  color: color,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
