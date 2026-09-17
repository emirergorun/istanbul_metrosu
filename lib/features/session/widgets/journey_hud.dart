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

  /// Rozetlerin satırdan alabileceği en büyük pay.
  ///
  /// Üstünde [FittedBox] devreye girer ve rozetleri küçültür. Skorun
  /// okunur kalması rozetlerden önce gelir.
  static const double _maxChipShare = 0.58;

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
        // Üst satır: skor solda, rozetler ve düğmeler sağda.
        //
        // Rozetler **esnek değil ama sınırlı**: kendi genişliklerini
        // alırlar, skor kalanı doldurur ve duraklatma düğmesi her zaman sağ
        // kenarda kalır. Satırın yarısını aşarlarsa [FittedBox] küçültür —
        // üç haneli bir combo bile satırı taşıramaz.
        LayoutBuilder(
          builder: (context, constraints) {
            final trailing = <Widget>[
              if (run.isSprint) const SprintChip(),
              ...chips,
            ];

            return Row(
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
                            // etiket ölçeğinde, skorun kendisiyle
                            // yarışmamalı.
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
                            style: AppText.stat.copyWith(
                              fontSize: 28,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing.isNotEmpty) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * _maxChipShare,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (var i = 0; i < trailing.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: AppSpacing.sm),
                            trailing[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
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
            );
          },
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
/// Combo ve seri rozetlerinin ortak rengi ve metni.
///
/// İkisi de aynı hat renginde ve yalnızca sayıyla gösteriliyordu; oyuncu
/// hangisinin ne olduğunu ayırt edemiyordu. Artık her birinin kendi rengi,
/// kendi adı ve basılı tutunca çıkan kendi açıklaması var.
///
/// Renkler bilinçli: combo **sarı** (anlık, hızlı, dikkat çeken), seri
/// **yeşil** (uzun soluklu, sağlıklı gidiş), risk altındaki seri
/// **kırmızı** (bu hamlede kopabilir).
class _ChipStyle {
  const _ChipStyle._();

  static const Color combo = AppColors.warning;
  static const Color streak = AppColors.success;
  static const Color streakAtRisk = AppColors.danger;
}

/// HUD'daki combo rozeti.
///
/// Sayının yanında **hazırlık payı** da gösterilir: combo, temizlemeyen
/// hamlelerle hemen sönmüyor artık, ama oyuncu kaç hakkı kaldığını
/// göremezse kural görünmez bir şans oyununa dönüşür. Dolu nokta kalan
/// hakkı, boş nokta harcanmış hakkı gösterir.
///
/// Sayı her değiştiğinde rozet kısa bir sıçrama yapar — combo'nun arttığı
/// gözden kaçmasın diye.
///
/// Basılı tutunca kuralı anlatan kısa bir açıklama çıkar. Oyunda başka
/// yerde öğretilmiyor; rozetin kendisi kendini anlatmalı.
class ComboChip extends StatelessWidget {
  const ComboChip({
    super.key,
    required this.combo,
    this.graceLeft,
    this.graceTotal,
  });

  final int combo;

  /// Combo sönmeden önce kalan hazırlık hamlesi. `null` ise nokta çizilmez.
  final int? graceLeft;

  /// Toplam hazırlık payı; nokta sayısı budur.
  final int? graceTotal;

  String get _explanation {
    final left = graceLeft;
    final base = 'COMBO: art arda sıra temizledikçe artar ve puanı katlar.';
    if (left == null) return base;
    return left > 0
        ? '$base Temizlemeyen $left hamle hakkın kaldı.'
        : '$base Sıradaki temizliksiz hamle combo’yu bitirir.';
  }

  @override
  Widget build(BuildContext context) {
    const color = _ChipStyle.combo;
    final total = graceTotal ?? 0;
    final left = graceLeft ?? 0;

    return Tooltip(
      message: _explanation,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        label: 'Combo $combo. $_explanation',
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            // Anahtar combo'ya bağlı: her artışta animasyon baştan başlar.
            key: ValueKey<int>(combo),
            tween: Tween<double>(begin: 1.35, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.bolt_rounded, size: 14, color: color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'COMBO',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: AppText.label.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'x$combo',
                    style: AppText.statSmall.copyWith(color: color),
                  ),
                  if (total > 0) ...<Widget>[
                    const SizedBox(width: 5),
                    for (var i = 0; i < total; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: _GraceDot(filled: i < left, color: color),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Combo rozetindeki hazırlık noktası.
class _GraceDot extends StatelessWidget {
  const _GraceDot({required this.filled, required this.color});

  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(
          color: color.withValues(alpha: filled ? 1 : 0.45),
          width: 1,
        ),
      ),
    );
  }
}

/// HUD'daki seri rozeti.
///
/// Combo'dan ayrı bir şey ölçer: combo son birkaç hamleyi, seri bütün
/// koşunun temposunu. Bu yüzden ayrı bir rozet, ayrı bir renk ve ayrı bir
/// ad — aynı renkte iki sayı göstermek ikisini de okunmaz yapıyordu.
///
/// [atRisk] açıkken rozet kırmızıya döner: açık tepside henüz temizlik yok
/// ve son parça kaldı, yani bu hamle seriyi ya sürdürecek ya bitirecek.
class StreakChip extends StatelessWidget {
  const StreakChip({
    super.key,
    required this.streak,
    this.atRisk = false,
    this.piecesLeft,
  });

  final int streak;
  final bool atRisk;

  /// Açık tepside kalan parça sayısı; açıklamada kullanılır.
  final int? piecesLeft;

  String get _explanation {
    const base =
        'SERİ: her üç parçada en az bir sıra temizlersen büyür, '
        'temizliksiz geçen tepside sıfırlanır.';
    if (!atRisk) return base;
    final left = piecesLeft ?? 1;
    return '$base Bu tepside henüz temizlik yok, $left parça kaldı.';
  }

  @override
  Widget build(BuildContext context) {
    final color = atRisk ? _ChipStyle.streakAtRisk : _ChipStyle.streak;

    return Tooltip(
      message: _explanation,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        label: 'Seri $streak. $_explanation',
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  atRisk
                      ? Icons.warning_amber_rounded
                      : Icons.trending_up_rounded,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    'SERİ',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: AppText.label.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$streak',
                  style: AppText.statSmall.copyWith(color: color),
                ),
              ],
            ),
          ),
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
