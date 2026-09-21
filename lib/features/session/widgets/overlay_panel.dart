import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';

/// Oyun üstünde açılan modal panellerin ortak kabuğu.
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.children,
    this.icon,
    this.showBackdrop = true,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final List<Widget> children;
  final IconData? icon;

  /// Varış sahnesi kendi karartmasını çizdiği için orada kapatılır.
  final bool showBackdrop;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: AppConstants.overlayFadeDuration,
      child: ColoredBox(
        color: showBackdrop
            ? Colors.black.withValues(alpha: 0.72)
            : Colors.transparent,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 28, color: accent),
                      ),
                      const SizedBox(height: AppSpacing.stack),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    // Başlık grubu bitti, gövde başlıyor: tek bölüm
                    // boşluğu. Gövdedeki her blok arasında ise
                    // [AppSpacing.stack] var — bkz. `result_overlay.dart`.
                    const SizedBox(height: AppSpacing.sectionGap),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sonuç ekranındaki tek satır istatistik.
class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool highlight;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Satır dolgusu yığın boşluğunun yarısı: iki satır arasında tam
      // [AppSpacing.stack] kalıyor ve istatistik listesi panelin geri
      // kalanıyla aynı ritimde okunuyor. Önce 7'ydi — ölçekte olmayan,
      // elle seçilmiş bir sayı.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.stack / 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.body)),
          Text(
            value,
            // Vurgulu satır bir basamak yukarı çıkar; ikisi de ölçekten.
            style: highlight
                ? AppText.stat.copyWith(
                    fontSize: 18,
                    color: accent ?? AppColors.textPrimary,
                  )
                : AppText.statSmall.copyWith(),
          ),
        ],
      ),
    );
  }
}
