import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Keşif ilerlemesinin ince çubuğu.
///
/// Keşif ekranı, ana ekran şeridi ve sonuç paneli aynı çubuğu kullanır;
/// üçünde ayrı ayrı çizilseydi kalınlıkları çoktan birbirinden ayrılırdı.
///
/// [gain] verilirse çubuk iki tonlu çizilir: koşudan önceki pay sönük, bu
/// koşuda eklenen pay vurgulu. Oyuncu "bu yolculukta kattığım bu kadar"
/// diye görür.
///
/// Katmanlama sırası bilinçli: önce zemin, sonra **toplam** dilim kazanç
/// renginde, en üste koşu öncesi pay taban renginde. Böylece iki ton için
/// piksel hesabı yapılmaz, iki kesir yeter.
class DiscoveryProgressTrack extends StatelessWidget {
  const DiscoveryProgressTrack({
    super.key,
    required this.value,
    this.color = AppColors.textPrimary,
    this.background = AppColors.surface,
    this.gain = 0,
    this.gainColor = AppColors.success,
    this.thickness = 6,
    this.animate = false,
  });

  /// Toplam doluluk, 0.0 – 1.0. [gain] buna dahildir.
  final double value;

  final Color color;
  final Color background;

  /// Bu koşuda eklenen pay, 0.0 – 1.0.
  final double gain;
  final Color gainColor;
  final double thickness;

  /// Kazanılan dilim büyüyerek gelsin mi? Yalnız sonuç panelinde açılır.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // Katmanlama saydam renkle çalışmaz: üstteki taban rengi yarı saydamsa
    // altındaki kazanç rengi sızar ve çubuk iki değil üç tonlu görünür.
    // Sözleşme burada yazılı olsun ki ileride biri `withValues(alpha:)`
    // geçtiğinde sessizce bozulmasın.
    assert(
      color.a == 1.0 && gainColor.a == 1.0 && background.a == 1.0,
      'DiscoveryProgressTrack opak renk bekler; katmanlar üst üste çiziliyor.',
    );

    final total = value.clamp(0.0, 1.0);
    final earned = gain.clamp(0.0, total);
    final before = total - earned;

    // "Hareketi azalt" açıkken dilim yerinde belirir; bilgi kaybolmaz,
    // yalnız hareket kalkar.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = animate && earned > 0 && !reduceMotion
        ? const Duration(milliseconds: 420)
        : Duration.zero;

    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(thickness / 2),
        // Genişlik **açıkça** sonsuz isteniyor.
        //
        // Çubuğun içinde kendi genişliğini belirleyen hiçbir şey yok: zemin
        // `Positioned.fill`, dilimler `FractionallySizedBox`. Yalnız
        // yükseklik verilmiş bir kutu, `CrossAxisAlignment.start` kullanan
        // bir `Column` içinde gevşek kısıtla karşılaşınca sıfır genişlikte
        // kalıyordu — çubuk ekranda birkaç piksellik bir noktaya dönüyor,
        // ilerleme hiç görünmüyordu. Ana ekran şeridi, keşif ekranı, sonuç
        // paneli ve günlük görev kartları aynı çubuğu kullandığı için hata
        // dördünde birden görünüyordu.
        child: SizedBox(
          width: double.infinity,
          height: thickness,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double t, _) {
              return Stack(
                children: <Widget>[
                  Positioned.fill(child: ColoredBox(color: background)),
                  // `heightFactor` **zorunlu**: çocuksuz bir `ColoredBox`
                  // gevşek kısıtta en küçük boyutu alıyor, yani sıfır
                  // yükseklik. Yalnız `widthFactor` verilen dilimler
                  // çiziliyor ama görünmüyordu — çubuk her yerde boş bir
                  // oluk gibi duruyordu (ana ekran şeridi, Yolculuk Kartım,
                  // sonuç paneli, günlük görev kartı).
                  FractionallySizedBox(
                    widthFactor: before + earned * t,
                    heightFactor: 1,
                    child: ColoredBox(color: gainColor),
                  ),
                  FractionallySizedBox(
                    widthFactor: before,
                    heightFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
