import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Oyun kataloğundaki ikonlar.
///
/// Stok `Icons.*` yerine elle çizilmiş şekiller kullanılır. Gerekçe iki
/// katmanlı:
///
/// - **Konu.** Hazır sette metroya ait glif yok. "Ray Uçuşu" için kalkan
///   uçak, "Durak Hafıza" için beyinli kafa çıkıyordu; ikisi de oyunun ne
///   olduğunu anlatmıyor.
/// - **Kimlik.** Material seti her uygulamada aynı; ekran şablondan çıkmış
///   gibi duruyor.
///
/// Çizim dili [MetroTrain] ile aynı: tüm ölçüler kutu boyutuna oranlı, aynı
/// köşe yumuşaklığı, tek renk + beyaz vurgu. Böylece küçük kart ikonu ile
/// uygulamanın geri kalanı aynı elden çıkmış görünür.
enum GameGlyph {
  /// Yerleşen blok parçası — Blok Metro.
  blocks,

  /// Küçük iki rozetin tek büyük rozette birleşmesi — Hat Birleştir.
  ///
  /// 2048 ailesinin görsel dili: yuvarlak köşeli dolu bloklar ve bir
  /// boyut sıçraması. Önceki hâli iki rayın kavuştuğu bir çatal çizimiydi;
  /// doğruydu ama oyunun ne olduğunu anlatmıyordu — oyuncu makas değil
  /// birleştirme yapıyor.
  merge,

  /// İki tünel duvarı arasındaki açıklık — Ray Uçuşu.
  tunnel,

  /// Üst üste yığılan rozetler — Hat Düşür.
  drop,

  /// Soru işareti ve altında dört şık — Metro Bilgi.
  ///
  /// Önceki hâli ray üzerinde durak dizisiydi ve oyun ağ bilgisi sorarken
  /// doğruydu. Havuz 1.200 soruluk genel kültür veritabanına dönünce glif
  /// yanlış söz vermeye başladı: bu bir bilgi yarışması, hafıza oyunu değil.
  quiz,

  /// Şeritler arası geçiş — Ray Değiştir.
  lanes,

  /// Art arda eklenen vagonlar ve önlerindeki yolcu noktası — Yolcu Topla.
  snake,

  /// İki rayın arasından geçen yolcu — Karşıdan Karşıya.
  crossing,

  /// Kıvrılan bir hat ve ucundaki çıkış oku — Metro Hattı.
  metroLine,

  /// Kaydırılan bir metro ve önündeki tünel kemeri — Tünele Kaç.
  escape,

  /// Kilitli kart.
  locked,
}

/// Bir [GameGlyph]'i verilen boyutta çizer.
class GameGlyphIcon extends StatelessWidget {
  const GameGlyphIcon({
    super.key,
    required this.glyph,
    required this.color,
    required this.size,
  });

  final GameGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      // Glif tamamen dekoratif: ekran okuyucu kartın kendi etiketini okur.
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: GameGlyphPainter(glyph: glyph, color: color),
        ),
      ),
    );
  }
}

/// [GameGlyph] çizimi. Ölçüler kutunun kısa kenarına oranlıdır.
class GameGlyphPainter extends CustomPainter {
  const GameGlyphPainter({required this.glyph, required this.color});

  final GameGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case GameGlyph.blocks:
        _paintBlocks(canvas, s, fill);
      case GameGlyph.merge:
        _paintMerge(canvas, s, stroke, fill);
      case GameGlyph.tunnel:
        _paintTunnel(canvas, s, fill);
      case GameGlyph.drop:
        _paintDrop(canvas, s, fill);
      case GameGlyph.quiz:
        _paintQuiz(canvas, s, fill, stroke);
      case GameGlyph.lanes:
        _paintLanes(canvas, s, fill, stroke);
      case GameGlyph.snake:
        _paintSnake(canvas, s, fill);
      case GameGlyph.crossing:
        _paintCrossing(canvas, s, fill, stroke);
      case GameGlyph.metroLine:
        _paintMetroLine(canvas, s, fill);
      case GameGlyph.escape:
        _paintEscape(canvas, s, fill, stroke);
      case GameGlyph.locked:
        _paintLocked(canvas, s, fill, stroke);
    }
  }

  /// Yatay metro, yolunu kesen dikey metro ve sağda tünel kemeri: oyunun
  /// bütün fikri — önünü aç, tünele gir.
  void _paintEscape(Canvas canvas, double s, Paint fill, Paint stroke) {
    // Hedef metro: iki hücre boyunda, ortada.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.06, s * 0.40, s * 0.44, s * 0.22),
        Radius.circular(s * 0.08),
      ),
      fill,
    );
    // Kenara kaydırılmış dikey engel: yol açık.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.56, s * 0.06, s * 0.14, s * 0.28),
        Radius.circular(s * 0.06),
      ),
      fill,
    );
    // Tünel kemeri: sağda, metronun hizasında.
    final arch = Path()
      ..moveTo(s * 0.74, s * 0.34)
      ..lineTo(s * 0.80, s * 0.34)
      ..arcToPoint(
        Offset(s * 0.80, s * 0.68),
        radius: Radius.circular(s * 0.17),
      )
      ..lineTo(s * 0.74, s * 0.68);
    canvas.drawPath(arch, stroke);
    // Yön: metrodan tünele üç nokta.
    for (var i = 0; i < 2; i++) {
      canvas.drawCircle(
        Offset(s * (0.58 + i * 0.08), s * 0.51),
        s * 0.025,
        fill,
      );
    }
  }

  /// Kare hücre — diğer çizimlerin yapı taşı.
  void _cell(Canvas canvas, double x, double y, double side, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, side, side),
        Radius.circular(side * 0.26),
      ),
      paint,
    );
  }

  /// Üç hücreli L parçası ve yerleşeceği boş kare: oyunun tam olarak yaptığı iş.
  void _paintBlocks(Canvas canvas, double s, Paint fill) {
    final side = s * 0.38;
    final gap = s * 0.08;
    final left = s * 0.09;
    final top = s * 0.09;

    _cell(canvas, left, top, side, fill);
    _cell(canvas, left, top + side + gap, side, fill);
    _cell(canvas, left + side + gap, top + side + gap, side, fill);

    // Boşta kalan köşe: parçanın oturacağı yer.
    _cell(
      canvas,
      left + side + gap,
      top,
      side,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.075,
    );
  }

  /// İki küçük rozet, üstünde birleştikleri büyük rozet.
  ///
  /// Boyut sıçraması mekaniği anlatır: aynı iki blok birleşince bir üst
  /// seviyeye çıkar. Büyük blok dolu, küçükler soluk — göz önce sonucu,
  /// sonra girdiyi okur.
  void _paintMerge(Canvas canvas, double s, Paint stroke, Paint fill) {
    final small = s * 0.26;
    final big = s * 0.40;
    final radius = Radius.circular(s * 0.09);

    final faded = Paint()..color = color.withValues(alpha: 0.45);
    // Alt sıra: birleşecek iki eş blok.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.10, s * 0.62, small, small),
        radius,
      ),
      faded,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.42, s * 0.62, small, small),
        radius,
      ),
      faded,
    );

    // Üst sıra: sonuç. Beyaz vurgu çizgisi "bir seviye yukarı"yı işaret eder.
    final target = Rect.fromLTWH(s * 0.30, s * 0.12, big, big);
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, Radius.circular(s * 0.12)),
      fill,
    );
    canvas.drawLine(
      Offset(target.center.dx, target.top + big * 0.26),
      Offset(target.center.dx, target.bottom - big * 0.26),
      Paint()
        ..color = AppColors.background
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(target.left + big * 0.26, target.center.dy),
      Offset(target.right - big * 0.26, target.center.dy),
      Paint()
        ..color = AppColors.background
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Tünel açıklığından geçen tren.
  void _paintTunnel(Canvas canvas, double s, Paint fill) {
    // Duvarlar + tren 26 punto boyunda üç ayrı lekeye dönüşüyordu. Şimdi
    // iki öge var: üstte ve altta tünelin daralan duvarları, ortada
    // aralarından geçen tren. Duvarlar iki kenardan da taşar, yani tünel
    // devam ediyormuş gibi okunur.
    final wall = Paint()..color = color.withValues(alpha: 0.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-s * 0.05, s * 0.06, s * 1.10, s * 0.22),
        Radius.circular(s * 0.07),
      ),
      wall,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-s * 0.05, s * 0.72, s * 1.10, s * 0.22),
        Radius.circular(s * 0.07),
      ),
      wall,
    );

    // Tren: açıklığın ortasında, burnu sağa dönük.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.16, s * 0.38, s * 0.62, s * 0.24),
        topLeft: Radius.circular(s * 0.05),
        bottomLeft: Radius.circular(s * 0.05),
        topRight: Radius.circular(s * 0.12),
        bottomRight: Radius.circular(s * 0.12),
      ),
      fill,
    );
  }

  void _paintDrop(Canvas canvas, double s, Paint fill) {
    // Kap + tek rozet olarak çizilmişti ve `U` harfi gibi okunuyordu: hangi
    // oyun olduğu anlaşılmıyordu. Şimdi üç öge var — düşmekte olan rozet,
    // altındaki yığın ve yığının tabanı. Üst rozetin yığınla hizalı ama
    // ayrı durması "düşürme" fiilini anlatıyor.
    final w = s * 0.30;
    final h = s * 0.19;
    final x = (s - w) / 2;

    // Düşen rozet: yığından kopuk, üstte.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, s * 0.06, w, h),
        Radius.circular(s * 0.06),
      ),
      fill,
    );

    // Oturmuş iki rozet. Alttaki geniş: yığın aşağı doğru büyüyor.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, s * 0.42, w, h),
        Radius.circular(s * 0.06),
      ),
      Paint()..color = color.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.24, s * 0.65, s * 0.52, h),
        Radius.circular(s * 0.06),
      ),
      Paint()..color = color.withValues(alpha: 0.55),
    );

    // Taban: yığının dayandığı yer.
    canvas.drawRect(
      Rect.fromLTWH(s * 0.14, s * 0.89, s * 0.72, s * 0.07),
      fill,
    );
  }

  void _paintQuiz(Canvas canvas, double s, Paint fill, Paint stroke) {
    // Dört şık çubuğu 26 punto boyunda çizgi yığınına dönüşüyordu. İki
    // çubuk aynı fikri anlatıyor ve soru işaretine nefes bırakıyor: üstte
    // soru, altta seçenekler, biri seçili.
    final mark = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.115
      ..strokeCap = StrokeCap.round;

    // Soru işaretinin kancası: yarım daire + aşağı inen kısa çizgi.
    final hook = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(s * 0.50, s * 0.28), radius: s * 0.17),
        3.5,
        4.0,
      )
      ..moveTo(s * 0.50, s * 0.40)
      ..lineTo(s * 0.50, s * 0.50);
    canvas.drawPath(hook, mark);
    canvas.drawCircle(Offset(s * 0.50, s * 0.62), s * 0.065, fill);

    // İki şık; üstteki seçili.
    final barHeight = s * 0.085;
    for (var i = 0; i < 2; i++) {
      final y = s * 0.76 + i * (barHeight + s * 0.065);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.18, y, s * 0.64, barHeight),
          Radius.circular(barHeight / 2),
        ),
        i == 0 ? fill : (Paint()..color = color.withValues(alpha: 0.38)),
      );
    }
  }

  /// Üç şerit; tren ortadakinden üsttekine geçiyor.
  void _paintLanes(Canvas canvas, double s, Paint fill, Paint stroke) {
    final lane = Paint()
      ..color = color.withValues(alpha: 0.40)
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = s * 0.22 + s * 0.28 * i;
      canvas.drawLine(Offset(s * 0.10, y), Offset(s * 0.90, y), lane);
    }

    // Alt şeritten üst şerite geçen yol.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.20, s * 0.78)
        ..lineTo(s * 0.50, s * 0.78)
        ..lineTo(s * 0.78, s * 0.22),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(s * 0.78, s * 0.22), s * 0.10, fill);
  }

  /// Sivri burunlu bir tren ve önünde bekleyen bir yolcu — yolcu
  /// toplandıkça tren vagon vagon uzuyor.
  void _paintSnake(Canvas canvas, double s, Paint fill) {
    final trainRect = Rect.fromLTWH(s * 0.08, s * 0.40, s * 0.46, s * 0.30);
    final train = RRect.fromRectAndCorners(
      trainRect,
      topLeft: Radius.circular(s * 0.06),
      bottomLeft: Radius.circular(s * 0.06),
      topRight: Radius.circular(s * 0.16),
      bottomRight: Radius.circular(s * 0.16),
    );
    canvas.drawRRect(train, fill);
    // Pencere: gövdeyi zemin renginde bir dikdörtgenle "oyuyor".
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.14, s * 0.45, s * 0.16, s * 0.12),
        Radius.circular(s * 0.03),
      ),
      Paint()..color = AppColors.background,
    );

    // Yolcu: trenin önünde, henüz binmemiş — baş + gövde, soluk ton.
    final passenger = Paint()..color = color.withValues(alpha: 0.55);
    final passengerX = s * 0.72;
    canvas.drawCircle(Offset(passengerX, s * 0.46), s * 0.09, passenger);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.63, s * 0.56, s * 0.18, s * 0.16),
        Radius.circular(s * 0.06),
      ),
      passenger,
    );
  }

  /// İki ray ve aralarından yukarı geçen yolcu — Karşıdan Karşıya.
  ///
  /// Raylar yatay, yolcu dikey: oyunun tek cümlesi bu: karşıya geçmek.
  void _paintCrossing(Canvas canvas, double s, Paint fill, Paint stroke) {
    final rail = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    for (final y in <double>[s * 0.28, s * 0.74]) {
      canvas.drawLine(Offset(s * 0.08, y), Offset(s * 0.92, y), rail);
    }

    // Yolcu: baş + gövde, iki rayın tam ortasında.
    canvas.drawCircle(Offset(s * 0.5, s * 0.42), s * 0.11, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.39, s * 0.54, s * 0.22, s * 0.18),
        Radius.circular(s * 0.07),
      ),
      fill,
    );
  }

  /// Kıvrılan hat ve ucundaki ok — Metro Hattı.
  ///
  /// Oyunun tek cümlesi: karışık bir hattı doğru yönden dışarı çıkarmak.
  /// Bu yüzden glif bir köşe dönen kalın çizgi ve başındaki ok.
  void _paintMetroLine(Canvas canvas, double s, Paint fill) {
    final body = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.18, s * 0.80)
        ..lineTo(s * 0.18, s * 0.42)
        ..lineTo(s * 0.58, s * 0.42),
      body,
    );

    // Ok: hattın ucunda, sağa doğru.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.88, s * 0.42)
        ..lineTo(s * 0.64, s * 0.28)
        ..lineTo(s * 0.64, s * 0.56)
        ..close(),
      fill,
    );
  }

  /// Kilit — kilitli kartlar için.
  void _paintLocked(Canvas canvas, double s, Paint fill, Paint stroke) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.22, s * 0.46, s * 0.56, s * 0.38),
        Radius.circular(s * 0.11),
      ),
      fill,
    );
    // Kilit dili.
    canvas.drawArc(
      Rect.fromLTWH(s * 0.33, s * 0.18, s * 0.34, s * 0.36),
      3.14159,
      3.14159,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.09
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(GameGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
