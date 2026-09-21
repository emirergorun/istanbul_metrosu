import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/pressable.dart';
import 'discovery_progress_track.dart';

/// Ana ekrandaki kalıcı keşif girişi.
///
/// Kart değil **şerit**: birincil eylem her zaman oyuna başlamak. Keşif
/// aynı ağırlıkta bir kart olsaydı iki eşit blok çıkar ve oyuncu bir an
/// ne yapacağını düşünürdü. Tek satır, oyuna başlamanın hemen üstünde.
///
/// Keşif kapalıysa (testler, veri yok) hiç çizilmez.
class DiscoveryEntryStrip extends StatelessWidget {
  const DiscoveryEntryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final discovery = AppScope.of(context).discovery;
    if (discovery == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: discovery,
      builder: (BuildContext context, _) {
        final discovered = discovery.discoveredCount;
        final total = discovery.totalCount;
        if (total == 0) return const SizedBox.shrink();

        return Pressable(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.discovery),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          semanticLabel:
              'İstanbul keşfi: $total durağın $discovered tanesi keşfedildi. '
              'Keşfi gör',
          child: Container(
            // Dokunma alanı 44 piksel altına inmesin diye dikey dolgu
            // metne değil kutuya veriliyor.
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            // Etiket tabela fontunda ve gerçek bir başlık
                            // puntosunda: 11 puntoluk rozet yazısıyken
                            // ekranda hiç görünmüyordu.
                            Expanded(
                              child: Text(
                                'İSTANBUL KEŞFİ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.sectionTitle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text.rich(
                              TextSpan(
                                text: '$discovered',
                                style: AppText.stat,
                                children: <InlineSpan>[
                                  TextSpan(
                                    text: ' / $total',
                                    style: AppText.captionStrong.copyWith(
                                      color: AppColors.textMuted,
                                      fontFeatures: kTabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Zemin `outline`: 143 durağın 2'sinde dolu pay
                        // birkaç piksel ve çubuğun geri kalanı kartın
                        // zemininden ayrışmıyordu. Boş çubuk görünür olunca
                        // "ne kadar yol var" sorusu da cevaplanıyor.
                        DiscoveryProgressTrack(
                          value: discovery.progress,
                          background: AppColors.outline,
                          thickness: 5,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
