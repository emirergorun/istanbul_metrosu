import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Oyunların ortak HUD parçaları — her oyun aynı dili konuşsun.
///
/// Kural: oyuna özgü bir sayı [JourneyHud]'un yanında [HudStat] olarak
/// durur; duraklat düğmesiyle aynı boy (44), aynı düz zemin
/// ([AppColors.surfaceHigh]), aynı köşe (12). Renkli saydam kutu, renkli
/// çerçeve ve parlama yok: kutu hangi sahnenin üstünde olursa olsun okunur.
/// Anlık bildirim [HudToast], kalıcı yönerge [HudHint]; ikisi de düz panel.
///
/// Kimlik rengi (hat rengi) kutunun içine değil, küçük bir işarete gider:
/// [HudStat.accent] etiketin yanında bir nokta olarak görünür.

/// Düz koyu panel: sahnenin üstündeki her yazının zemini.
const Color hudPanel = Color(0xF224282E);

/// HUD'daki küçük gösterge: üstte etiket, altta değer.
class HudStat extends StatelessWidget {
  const HudStat({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.child,
    this.accent,
  });

  /// Tek sayılık gösterge.
  factory HudStat.value({
    Key? key,
    required String label,
    required String value,
    String? semanticLabel,
    Color? accent,
  }) => HudStat(
    key: key,
    label: label,
    semanticLabel: semanticLabel ?? '$label $value',
    accent: accent,
    child: Text(
      value,
      maxLines: 1,
      style: AppText.statSmall.copyWith(height: 1.1),
    ),
  );

  /// Büyük harfle, Türkçe doğru yazılmış etiket ("SEVİYE", "HAK").
  final String label;
  final String semanticLabel;
  final Widget child;

  /// Varsa etiketin solunda küçük bir kimlik noktası (ör. trenin hattı).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (accent != null) ...<Widget>[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: AppText.micro.copyWith(height: 1.1)),
                ],
              ),
              const SizedBox(height: 2),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Kalan haklar: dolu nokta yanar, giden hak boş halka olur; son hak
/// tehlike rengine döner. Bütün oyunlarda hak aynı biçimde sayılır.
class HudLives extends StatelessWidget {
  const HudLives({super.key, required this.left, required this.total});

  final int left;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fill = left <= 1 ? AppColors.danger : AppColors.textPrimary;
    return SizedBox(
      height: 18,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < total; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < left ? fill : Colors.transparent,
                border: Border.all(
                  color: i < left ? fill : AppColors.outline,
                  width: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hak göstergesi: "HAK" etiketi ve noktalar.
class HudLivesStat extends StatelessWidget {
  const HudLivesStat({super.key, required this.left, required this.total});

  final int left;
  final int total;

  @override
  Widget build(BuildContext context) => HudStat(
    label: 'HAK',
    semanticLabel: '$left hak kaldı',
    child: HudLives(left: left, total: total),
  );
}

/// Anlık bildirim ("Durak bonusu +40", "Hat açıldı"): düz panel, cümle.
///
/// Gölge, renkli çerçeve ya da hap biçimi yok. Kimlik rengi varsa solda
/// küçük bir şerit olarak görünür; yazı her zaman okunur beyaz.
class HudToast extends StatelessWidget {
  const HudToast({super.key, required this.text, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: hudPanel,
        borderRadius: BorderRadius.circular(8),
        border: accent == null
            ? null
            : Border(left: BorderSide(color: accent!, width: 3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.captionStrong.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

/// Kalıcı yönerge satırı ("Dokun: … · Basılı tut: ipucu"): sahnenin
/// üstünde de okunsun diye düz panel üstünde, ikincil renkte.
class HudHint extends StatelessWidget {
  const HudHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: hudPanel,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
