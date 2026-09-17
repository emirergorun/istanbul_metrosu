import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

import '../domain/trivia_category.dart';

/// Soru kategorisinin simgesi.
///
/// Önce üç harfli kısaltma kullanılıyordu (`TAR`, `SAN`, `COĞ`). Metro hat
/// rozetiyle aynı dili konuşuyordu ama iki sorunu vardı: `SAN` kimsenin
/// "Kültür & Sanat" diye çözemeyeceği bir kısaltma, ve kategori adı zaten
/// yanında yazılı olduğu için kısaltma bilgi taşımıyor, yalnızca yer
/// kaplıyordu.
///
/// Çizim dili oyun kataloğundaki [GameGlyph] ile aynı: elle çizilmiş,
/// tek renk, tüm ölçüler kutu boyutuna oranlı, stok `Icons.*` yok. Simge
/// **tek başına anlam taşımak zorunda değil** — kategori adı her zaman
/// yanında durur, simge yalnızca tanımayı hızlandırır.
class CategoryGlyphIcon extends StatelessWidget {
  const CategoryGlyphIcon({
    super.key,
    required this.category,
    this.color,
    this.size = 16,
  });

  /// Kategorinin kendi rengi. Simge tek renk çizilir; okunurluk için
  /// [AppColors] içinde kontrastı doğrulanmış tonlar kullanılır.
  static Color colorOf(TriviaCategory category) => switch (category) {
    TriviaCategory.history => AppColors.categoryHistory,
    TriviaCategory.cultureArt => AppColors.categoryCultureArt,
    TriviaCategory.sports => AppColors.categorySports,
    TriviaCategory.geographyCity => AppColors.categoryGeography,
    TriviaCategory.istanbul => AppColors.categoryIstanbul,
    TriviaCategory.generalKnowledge => AppColors.categoryGeneral,
  };

  final TriviaCategory category;

  /// Boş bırakılırsa kategorinin kendi rengi kullanılır.
  final Color? color;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      // Tamamen dekoratif: ekran okuyucu kategori adını zaten okuyor.
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _CategoryGlyphPainter(
            category: category,
            color: color ?? colorOf(category),
          ),
        ),
      ),
    );
  }
}

class _CategoryGlyphPainter extends CustomPainter {
  const _CategoryGlyphPainter({required this.category, required this.color});

  final TriviaCategory category;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (category) {
      case TriviaCategory.history:
        _paintColumn(canvas, s, fill);
      case TriviaCategory.cultureArt:
        _paintPalette(canvas, s, fill);
      case TriviaCategory.sports:
        _paintTrophy(canvas, s, fill);
      case TriviaCategory.geographyCity:
        _paintPin(canvas, s, fill, stroke);
      case TriviaCategory.istanbul:
        _paintBridge(canvas, s, fill);
      case TriviaCategory.generalKnowledge:
        _paintBook(canvas, s, fill);
    }
  }

  /// Antik sütun — tarih.
  ///
  /// Kum saati de denendi; 16 punto boyunda iki üçgen tek lekeye dönüşüyor.
  /// Sütunun yatay başlık/taban çizgileri bu boyutta ayrı kalıyor.
  void _paintColumn(Canvas canvas, double s, Paint fill) {
    final cap = s * 0.11;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.14, s * 0.12, s * 0.72, cap),
        Radius.circular(s * 0.04),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.10, s * 0.77, s * 0.80, cap),
        Radius.circular(s * 0.04),
      ),
      fill,
    );
    // Üç yiv: gövdeyi dolu bir dikdörtgen yapmak sütunu kutuya çeviriyordu.
    for (var i = 0; i < 3; i++) {
      final x = s * 0.26 + i * s * 0.19;
      canvas.drawRect(Rect.fromLTWH(x, s * 0.27, s * 0.09, s * 0.46), fill);
    }
  }

  /// Ressam paleti — kültür ve sanat.
  ///
  /// Tam daire + iç nokta olarak çizilmişti ve paletten çok bir düğmeye
  /// benziyordu. Paleti palet yapan şey daire değil, **bir kenarındaki
  /// girinti** ve başparmak deliği. Dış hat bu yüzden asimetrik: sağ alt
  /// köşe içeri kıvrılıyor.
  void _paintPalette(Canvas canvas, double s, Paint fill) {
    final body = Path()
      ..moveTo(s * 0.50, s * 0.08)
      ..cubicTo(s * 0.86, s * 0.08, s * 0.96, s * 0.34, s * 0.88, s * 0.56)
      // Sağ alttaki girinti: başparmağın girdiği yer.
      ..cubicTo(s * 0.82, s * 0.70, s * 0.70, s * 0.62, s * 0.64, s * 0.72)
      ..cubicTo(s * 0.58, s * 0.82, s * 0.66, s * 0.90, s * 0.50, s * 0.92)
      ..cubicTo(s * 0.22, s * 0.94, s * 0.06, s * 0.72, s * 0.08, s * 0.48)
      ..cubicTo(s * 0.10, s * 0.24, s * 0.26, s * 0.08, s * 0.50, s * 0.08)
      ..close();

    // Gövde konturla: dolu çizilirse boya lekeleri görünmez.
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.085
        ..strokeJoin = StrokeJoin.round,
    );

    // Üç boya lekesi.
    canvas.drawCircle(Offset(s * 0.34, s * 0.30), s * 0.075, fill);
    canvas.drawCircle(Offset(s * 0.62, s * 0.28), s * 0.075, fill);
    canvas.drawCircle(Offset(s * 0.28, s * 0.56), s * 0.075, fill);
  }

  /// Kupa — spor.
  ///
  /// Kulplar kaldırıldı. 18 punto boyunda iki yay kâsenin iki yanında
  /// kulak gibi duruyor ve siluet kupadan uzaklaşıyordu. Kulpsuz kupa
  /// hâlâ kupa: ayırt eden şey geniş ağız, hızla daralan gövde, ince
  /// ayak ve geniş taban — kulplar değil.
  void _paintTrophy(Canvas canvas, double s, Paint fill) {
    final bowl = Path()
      ..moveTo(s * 0.18, s * 0.10)
      ..lineTo(s * 0.82, s * 0.10)
      ..lineTo(s * 0.82, s * 0.22)
      // Omuzdan dibe hızlı daralma: kupayı bardaktan ayıran hat.
      ..cubicTo(s * 0.80, s * 0.48, s * 0.68, s * 0.58, s * 0.58, s * 0.60)
      ..lineTo(s * 0.42, s * 0.60)
      ..cubicTo(s * 0.32, s * 0.58, s * 0.20, s * 0.48, s * 0.18, s * 0.22)
      ..close();
    canvas.drawPath(bowl, fill);

    // Ayak: gövdeden belirgin şekilde ince.
    canvas.drawRect(
      Rect.fromLTWH(s * 0.45, s * 0.58, s * 0.10, s * 0.16),
      fill,
    );
    // Kaide ve taban: iki kademe, kupayı ayakta tutan görüntü.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.33, s * 0.72, s * 0.34, s * 0.08),
        Radius.circular(s * 0.03),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.22, s * 0.82, s * 0.56, s * 0.11),
        Radius.circular(s * 0.04),
      ),
      fill,
    );
  }

  /// Konum işareti — coğrafya ve şehir.
  ///
  /// Gövde konturla, göz dolu çizilir. Dolu gövdeye delik açmak
  /// `saveLayer` gerektirirdi ve simge her yüzeyde çalışmak zorunda.
  void _paintPin(Canvas canvas, double s, Paint fill, Paint stroke) {
    final pin = Path()
      ..moveTo(s * 0.50, s * 0.90)
      ..cubicTo(s * 0.18, s * 0.56, s * 0.18, s * 0.34, s * 0.31, s * 0.21)
      ..cubicTo(s * 0.44, s * 0.08, s * 0.69, s * 0.12, s * 0.77, s * 0.29)
      ..cubicTo(s * 0.84, s * 0.46, s * 0.71, s * 0.63, s * 0.50, s * 0.90)
      ..close();
    canvas.drawPath(pin, stroke);
    canvas.drawCircle(Offset(s * 0.50, s * 0.38), s * 0.11, fill);
  }

  /// Boğaz köprüsü — İstanbul.
  ///
  /// Kategori "Ulaşım" iken metro treni çiziliyordu. Kapsam şehrin
  /// tamamına genişleyince tren yanlış söz vermeye başladı: burada
  /// köprüler, semtler ve tarihî yapılar da soruluyor. Üstelik tren
  /// oyunun her yerinde zaten var (kalan hak göstergesi, yolculuk
  /// çubuğu); köprü İstanbul'u tek başına anlatan siluet.
  void _paintBridge(Canvas canvas, double s, Paint fill) {
    final cable = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;

    const towerX = <double>[0.24, 0.76];
    final deckY = s * 0.70;

    // Kuleler arasındaki asma kablo.
    canvas.drawPath(
      Path()
        ..moveTo(s * towerX[0], s * 0.24)
        ..quadraticBezierTo(s * 0.50, s * 0.68, s * towerX[1], s * 0.24),
      cable,
    );
    // Kenar kabloları: köprüyü kıyıya bağlar.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.04, deckY)
        ..quadraticBezierTo(s * 0.14, s * 0.44, s * towerX[0], s * 0.24),
      cable,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.96, deckY)
        ..quadraticBezierTo(s * 0.86, s * 0.44, s * towerX[1], s * 0.24),
      cable,
    );

    // Kuleler.
    for (final x in towerX) {
      canvas.drawRect(
        Rect.fromLTWH(s * x - s * 0.045, s * 0.18, s * 0.09, s * 0.56),
        fill,
      );
    }

    // Tabliye.
    canvas.drawRect(Rect.fromLTWH(0, deckY, s, s * 0.09), fill);
  }

  /// Açık kitap — genel kültür.
  ///
  /// Önce ampul çizilmişti: 17 punto boyunda halka + iki duy çizgisi
  /// ampulden çok bir vidaya benziyordu ve "fikir" çağrışımı genel kültürü
  /// anlatmıyordu. Kitap bu ölçekte tanınıyor ve kategorinin işini
  /// doğrudan söylüyor.
  void _paintBook(Canvas canvas, double s, Paint fill) {
    final page = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // İki sayfa, ortada sırt. Sayfa üstleri hafif içbükey: kitap açık duruyor.
    final left = Path()
      ..moveTo(s * 0.50, s * 0.30)
      ..quadraticBezierTo(s * 0.32, s * 0.18, s * 0.10, s * 0.24)
      ..lineTo(s * 0.10, s * 0.76)
      ..quadraticBezierTo(s * 0.32, s * 0.70, s * 0.50, s * 0.82);
    final right = Path()
      ..moveTo(s * 0.50, s * 0.30)
      ..quadraticBezierTo(s * 0.68, s * 0.18, s * 0.90, s * 0.24)
      ..lineTo(s * 0.90, s * 0.76)
      ..quadraticBezierTo(s * 0.68, s * 0.70, s * 0.50, s * 0.82);
    canvas.drawPath(left, page);
    canvas.drawPath(right, page);

    // Sırt: iki sayfayı birbirine bağlar, yoksa iki ayrı yaprak gibi durur.
    canvas.drawRect(
      Rect.fromLTWH(s * 0.47, s * 0.30, s * 0.06, s * 0.52),
      fill,
    );
  }

  @override
  bool shouldRepaint(_CategoryGlyphPainter oldDelegate) =>
      oldDelegate.category != category || oldDelegate.color != color;
}
