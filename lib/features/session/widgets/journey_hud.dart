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
    this.gameScore,
    this.chips = const <Widget>[],
    this.actions = const <Widget>[],
  });

  final JourneyView run;
  final Color accent;
  final VoidCallback onPause;

  /// Bu oyunun **bu yolculukta** kazandırdığı puan.
  ///
  /// Skor artık yolculuğun toplamı: oyuncu Blok Metro'dan Hat Düşür'e
  /// geçtiğinde HUD 1.840'tan başlar. Yeni oyunun ne kattığı görünmezse
  /// bu bir hata gibi okunur. Yalnızca başka bir oyun da puan kattıysa
  /// gösterilir; tek oyun oynanıyorken iki kez aynı sayıyı yazmak gürültü.
  final int? gameScore;

  /// Oyuna özgü rozetler (combo, hat seviyesi, sıradaki parça…).
  final List<Widget> chips;

  /// Oyuna özgü butonlar (geri al…). Duraklatma zaten eklenir.
  final List<Widget> actions;

  /// Rozetlerin satırdan alabileceği en büyük pay.
  ///
  /// Üstünde [FittedBox] devreye girer ve rozetleri küçültür. Skorun
  /// okunur kalması rozetlerden önce gelir.
  static const double _maxChipShare = 0.58;

  /// Yolculuğun toplamı bu oyunun katkısından büyükse ayrım anlamlı.
  bool get _showGameScore {
    final value = gameScore;
    return value != null && value > 0 && value < run.score;
  }

  String get _recordLine => run.isFirstRun
      ? 'SKOR · İLK YOLCULUK'
      : run.recordBeaten
      ? 'SKOR · REKOR GEÇİLDİ'
      : 'SKOR · REKOR ${Formatters.score(run.recordToBeat)}';

  String get _semanticLabel {
    final base = run.isFirstRun
        ? 'Yolculuk skoru ${Formatters.score(run.score)}, '
              'bu rotada ilk yolculuk'
        : run.recordBeaten
        ? 'Yolculuk skoru ${Formatters.score(run.score)}, rekor geçildi'
        : 'Yolculuk skoru ${Formatters.score(run.score)}, '
              'rekor ${Formatters.score(run.recordToBeat)}';
    if (!_showGameScore) return base;
    return '$base, bu oyunda ${Formatters.score(gameScore!)} puan';
  }

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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  Formatters.score(run.score),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  // Skor sık değişir: iri başlık fontu
                                  // değil, sabit genişlikli rakamlarla
                                  // M PLUS Rounded 1c.
                                  style: AppText.stat.copyWith(
                                    fontSize: 28,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (_showGameScore) ...<Widget>[
                                const SizedBox(width: 6),
                                Text(
                                  'bu oyunda +${Formatters.score(gameScore!)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.label.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
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
/// Combo ve serinin HUD'daki okuması.
///
/// Önce iki ayrı hap rozetti: her biri ikon + büyük harf etiket + sayı +
/// nokta göstergesi taşıyordu, ikisi de aynı kenarlık ve dolguyla, biri
/// sarı biri yeşil. Üç sorun birdendi.
///
/// **Hiyerarşi yoktu.** Combo anlık ve gürültülü, seri uzun soluklu ve
/// sessiz; eşit ağırlıkta iki rozet ikisini de aynı şey gibi gösteriyordu.
///
/// **Hat kimliğinden kopuktu.** Ekrandaki her şey hattın renginde — rozet,
/// tren, ray, ilerleme — ama bu iki rozet sabit sarı ve yeşildi. M1A
/// oynarken ekranda üç ilgisiz renk oluyordu.
///
/// **Tekrardı.** Combo zaten patlama anında tahtanın üstünde, gözün
/// olduğu yerde, iri iri yazılıyor. Sağ üst köşe oyun sırasında en az
/// bakılan yer.
///
/// Şimdi tek bir okuma var: çarpan büyük ve hat renginde, seri onun
/// altında küçük ve sessiz. Kutu, kenarlık, dolgu ve ikon yok — biçimi
/// tipografi ve renk taşıyor.
class ComboReadout extends StatelessWidget {
  const ComboReadout({
    super.key,
    required this.combo,
    required this.streak,
    required this.accent,
    this.graceLeft,
    this.graceTotal,
    this.streakAtRisk = false,
  });

  /// Şu anki combo. 2'nin altındaysa çarpan yazılmaz.
  final int combo;

  /// Şu anki seri. 1'in altındaysa seri satırı yazılmaz.
  final int streak;

  /// Hattın rengi. Çarpan bu renkte yanar.
  final Color accent;

  /// Combo sönmeden önce kalan hazırlık hamlesi.
  final int? graceLeft;

  /// Toplam hazırlık payı.
  final int? graceTotal;

  /// Seri bu hamlede kopabilir mi?
  final bool streakAtRisk;

  bool get _showCombo => combo >= 2;
  bool get _showStreak => streak >= 1;

  /// Combo sönmeye yaklaştıkça çarpan soluyor.
  ///
  /// Önce kalan hak nokta olarak çiziliyordu; nokta dizisi ne anlama
  /// geldiği söylenmeden anlaşılmıyordu. Solma evrensel okunur: "bu şey
  /// bitmek üzere".
  double get _comboOpacity {
    final left = graceLeft;
    final total = graceTotal;
    if (left == null || total == null || total <= 0) return 1;
    return 0.5 + 0.5 * (left / total).clamp(0.0, 1.0);
  }

  String get _explanation {
    final parts = <String>[];
    if (_showCombo) {
      parts.add(
        'Combo ×$combo: art arda sıra temizledikçe artar ve puanı katlar.',
      );
      final left = graceLeft;
      if (left != null) {
        parts.add(
          left > 0
              ? 'Temizlemeyen $left hamle hakkın kaldı.'
              : 'Sıradaki temizliksiz hamle combo’yu bitirir.',
        );
      }
    }
    if (_showStreak) {
      parts.add(
        'Seri $streak: her üç parçada en az bir sıra temizlersen büyür.',
      );
      if (streakAtRisk) parts.add('Bu tepside henüz temizlik yok.');
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_showCombo && !_showStreak) return const SizedBox.shrink();

    final streakColor = streakAtRisk
        ? AppColors.danger
        : AppColors.textSecondary;

    return Tooltip(
      message: _explanation,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Semantics(
        label: _explanation,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_showCombo)
                TweenAnimationBuilder<double>(
                  // Anahtar combo'ya bağlı: her artışta baştan oynar.
                  key: ValueKey<int>(combo),
                  tween: Tween<double>(begin: 1.3, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: _kEase,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerRight,
                    child: child,
                  ),
                  child: Text(
                    '×$combo',
                    style: AppText.stat.copyWith(
                      fontSize: 22,
                      height: 1,
                      letterSpacing: -0.5,
                      color: accent.withValues(alpha: _comboOpacity),
                    ),
                  ),
                ),
              if (_showStreak)
                Padding(
                  padding: EdgeInsets.only(top: _showCombo ? 3 : 0),
                  child: Text(
                    'seri $streak',
                    style: AppText.label.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      height: 1,
                      color: streakColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Giriş hareketleri için ortak eğri.
///
/// `easeOutBack` kadar zıplamaz, `easeInOut` kadar da uyuşuk değil.
const Cubic _kEase = Cubic(0.32, 0.72, 0.0, 1.0);

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
