import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../journey_run.dart';
import '../../../core/widgets/pressable.dart';

/// Oyun ekranlarının üst bilgi alanı — **her oyun için ortak**.
///
/// Skor, **rota rekoru** ve son durak sprinti burada; hangi oyun oynanırsa
/// oynansın aynı yerde ve aynı biçimde görünür. Oyuna özgü göstergeler
/// [chips], oyuna özgü butonlar [actions] ile eklenir.
///
/// Rekorun her oyunda görünmesi şart: oyunun amacı o rotadaki kendi rekorunu
/// geçmek, ama rekor ekranda değilse oyuncu ne kadar yaklaştığını bilemez.
class JourneyHud extends StatelessWidget {
  const JourneyHud({
    super.key,
    required this.run,
    required this.accent,
    required this.onPause,
    this.chips = const <Widget>[],
    this.actions = const <Widget>[],
  });

  final JourneyRun run;
  final Color accent;
  final VoidCallback onPause;

  /// Oyuna özgü rozetler (combo, hat seviyesi, sıradaki parça…).
  final List<Widget> chips;

  /// Oyuna özgü butonlar (geri al…). Duraklatma zaten eklenir.
  final List<Widget> actions;

  String get _recordLine => run.isFirstRun
      ? 'SKOR · İLK YOLCULUK'
      : run.recordBeaten
      ? 'SKOR · REKOR GEÇİLDİ'
      : 'SKOR · REKOR ${Formatters.score(run.recordToBeat)}';

  String get _semanticLabel => run.isFirstRun
      ? 'Skor ${Formatters.score(run.score)}, bu rotada ilk yolculuk'
      : run.recordBeaten
      ? 'Skor ${Formatters.score(run.score)}, rekor geçildi'
      : 'Skor ${Formatters.score(run.score)}, '
            'rekor ${Formatters.score(run.recordToBeat)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: _semanticLabel,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _recordLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Skorun üstündeki künye satırı: büyük harf
                        // etiket ölçeğinde, skorun kendisiyle yarışmamalı.
                        style: AppText.label.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          fontFeatures: kTabularFigures,
                          color: run.recordBeaten
                              ? accent
                              : AppColors.textMuted,
                        ),
                      ),
                      Text(
                        Formatters.score(run.score),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Skor sık değişir: iri başlık fontu değil,
                        // sabit genişlikli rakamlarla Plus Jakarta Sans.
                        style: AppText.stat.copyWith(fontSize: 28, height: 1.1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (run.isSprint) ...<Widget>[
              const SprintChip(),
              const SizedBox(width: AppSpacing.sm),
            ],
            for (final chip in chips) ...<Widget>[
              chip,
              const SizedBox(width: AppSpacing.sm),
            ],
            for (final action in actions) ...<Widget>[
              action,
              const SizedBox(width: AppSpacing.sm),
            ],
            HudButton(
              icon: Icons.pause_rounded,
              tooltip: 'Duraklat',
              onPressed: onPause,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Çubuk rekora doğru dolar; rekor yoksa boş kalır.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: run.recordProgress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.surfaceHigh,
            valueColor: AlwaysStoppedAnimation<Color>(
              run.recordBeaten ? AppColors.success : accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Son durak sprinti göstergesi: sprint sürdüğü sürece üstte kalır.
class SprintChip extends StatelessWidget {
  const SprintChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.flag_rounded, size: 15, color: AppColors.warning),
          SizedBox(width: 3),
          Text(
            'SON DURAK ×2',
            style: AppText.label.copyWith(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

/// Ardışık temizlik göstergesi. Oyunlar `chips` ile ekler.
class ComboChip extends StatelessWidget {
  const ComboChip({super.key, required this.combo, required this.accent});

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
            Text('x$combo', style: AppText.statSmall.copyWith(color: accent)),
          ],
        ),
      ),
    );
  }
}

/// HUD'daki kare ikon butonu.
class HudButton extends StatelessWidget {
  const HudButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
  });

  final IconData icon;
  final String tooltip;

  /// İkonun yanında görünen kısa metin — geri alma hakkı gibi sayılar için.
  /// `null` ise düğme kare kalır.
  final String? label;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label == null ? tooltip : '$tooltip, $label hak',
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: label == null ? 44 : 66,
              height: 44,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 22,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    if (label != null) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        label!,
                        style: AppText.statSmall.copyWith(
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
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
