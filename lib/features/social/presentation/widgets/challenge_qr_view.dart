import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../../../app/theme.dart';

/// Meydan okuma karesi.
///
/// Hazır bir QR widget'ı yerine kendi boyacımız var. Üç gerekçe:
///
/// 1. **Okunabilirlik.** Kare metroda, hareket eden bir vagonda, başka bir
///    telefonun ekranından okunuyor. Modüller keskin piksel sınırlarına
///    yuvarlanıyor; yarım piksele denk gelen bir modül kamerada bulanık
///    çıkıyor ve okuma süresini uzatıyor.
/// 2. **Sessiz bölge.** Standart, karenin çevresinde dört modüllük boş bir
///    kuşak ister. Koyu temada bu kuşak unutulursa kod, arkasındaki koyu
///    zemine karışıyor ve hiç okunmuyor. Burada kuşak beyaz bir kartla
///    garanti altında.
/// 3. **Kimlik.** Köşe göz desenleri uygulamanın yuvarlak diline uyuyor,
///    ama yalnızca **dış** çerçevede: veri modülleri kare kalıyor, çünkü
///    onları yuvarlatmak okuma hatası üretiyor.
///
/// Kod tamamen cihazda üretiliyor — ağ yok, dosya yok, izin yok.
class ChallengeQrView extends StatelessWidget {
  const ChallengeQrView({
    super.key,
    required this.data,
    this.size = 220,
    this.semanticLabel,
  });

  /// Karekoda girecek metin.
  final String data;

  /// Kenar uzunluğu (sessiz bölge dahil).
  final double size;

  /// Ekran okuyucu etiketi.
  ///
  /// Karekodun kendisi ekran okuyucu için anlamsız; kullanıcıya kodun ne
  /// olduğu ve kamerasız alternatifin nerede olduğu söylenir.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final QrImage image;
    try {
      // Hata düzeltme seviyesi **M**: %15 hasar toleransı. Q ve H daha
      // dayanıklı ama kareyi büyütüyor, yani aynı ekranda modüller
      // küçülüyor — telefondan telefona okumada net kayıp.
      image = QrImage(
        QrCode.fromData(
          data: data,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ),
      );
    } catch (error) {
      // Yük hiçbir karekod sürümüne sığmıyor. Pratikte olmamalı (yük ~110
      // karakter), ama çökmek yerine sessizce boş bırakılıyor.
      debugPrint('Karekod üretilemedi: $error');
      return SizedBox.square(dimension: size);
    }

    return Semantics(
      label: semanticLabel ?? 'Meydan okuma karesi',
      image: true,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * _quietZoneRatio),
            decoration: BoxDecoration(
              // Kare **her zaman** beyaz zeminde. Koyu temada renk
              // çevirmek okuyucuların çoğunda çalışıyor ama hepsinde
              // değil; standart koyu modül / açık zemin diyor.
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: CustomPaint(painter: _QrPainter(image)),
          ),
        ),
      ),
    );
  }

  /// Sessiz bölgenin kenar uzunluğuna oranı.
  ///
  /// Standart dört modül ister; tipik bir 41 modüllük kodda bu ~%9 eder.
  static const double _quietZoneRatio = 0.09;
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    if (count == 0) return;

    final paint = Paint()
      ..color = AppColors.brandNavyDeep
      ..isAntiAlias = false;
    final cell = size.width / count;

    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!image.isDark(row, col)) continue;
        // Kenarlar **tam piksele** yuvarlanıyor: komşu modüller arasında
        // yarım piksellik boşluk kalırsa kamera koyu alanı bölünmüş
        // görüyor ve çözme başarısız olabiliyor.
        final left = (col * cell).floorToDouble();
        final top = (row * cell).floorToDouble();
        final right = ((col + 1) * cell).ceilToDouble();
        final bottom = ((row + 1) * cell).ceilToDouble();
        canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
