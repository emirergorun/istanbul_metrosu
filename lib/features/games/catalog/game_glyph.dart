import 'package:flutter/material.dart';

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

  /// İki rayın tek raya katılması — Hat Birleştir.
  merge,

  /// İki tünel duvarı arasındaki açıklık — Ray Uçuşu.
  tunnel,

  /// Üst üste yığılan rozetler — Hat Düşür.
  drop,

  /// Ray üzerinde durak dizisi, sonuncusu boş — Metro Bilgi.
  /// ("Sıradaki durak hangisi?" sorusunun şekli.)
  sequence,

  /// Şeritler arası geçiş — Ray Değiştir.
  lanes,

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
      case GameGlyph.sequence:
        _paintSequence(canvas, s, fill, stroke);
      case GameGlyph.lanes:
        _paintLanes(canvas, s, fill, stroke);
      case GameGlyph.locked:
        _paintLocked(canvas, s, fill, stroke);
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

  /// İki ray tek rayda birleşir.
  void _paintMerge(Canvas canvas, double s, Paint stroke, Paint fill) {
    final path = Path()
      ..moveTo(s * 0.14, s * 0.14)
      ..lineTo(s * 0.44, s * 0.46)
      ..lineTo(s * 0.86, s * 0.46)
      ..moveTo(s * 0.14, s * 0.82)
      ..lineTo(s * 0.44, s * 0.50);
    canvas.drawPath(path, stroke);

    // Birleşme noktasındaki durak işareti.
    canvas.drawCircle(Offset(s * 0.47, s * 0.48), s * 0.10, fill);
  }

  /// Tünel açıklığından geçen tren.
  void _paintTunnel(Canvas canvas, double s, Paint fill) {
    // 24pt'de ayrıntı taşımıyor: duvarlar sağ kenardan taşırılır (tünel
    // devam ediyormuş gibi okunur) ve tren büyütülür. Önceki hâlde duvarlar
    // serbest duran iki küçük kare gibi görünüyordu.
    final left = s * 0.66;
    final inner = Radius.circular(s * 0.10);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(left, 0, s - left, s * 0.34),
        bottomLeft: inner,
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(left, s * 0.66, s - left, s * 0.34),
        topLeft: inner,
      ),
      fill,
    );

    // Açıklığa giren tren; burnu sağa bakar.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.04, s * 0.36, s * 0.52, s * 0.28),
        topLeft: Radius.circular(s * 0.06),
        bottomLeft: Radius.circular(s * 0.06),
        topRight: Radius.circular(s * 0.14),
        bottomRight: Radius.circular(s * 0.14),
      ),
      fill,
    );
  }

  /// Kaba düşen rozet — Hat Düşür.
  void _paintDrop(Canvas canvas, double s, Paint fill) {
    // Hız çizgileri kulak gibi okunuyordu, kaldırıldı. Geriye iki öge
    // kalıyor: düşen rozet ve onu toplayan kap. "Düşür" fiili bu ikisinden
    // anlaşılıyor.
    canvas.drawCircle(Offset(s * 0.50, s * 0.20), s * 0.165, fill);

    // Açık ağızlı kap.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.14, s * 0.46)
        ..lineTo(s * 0.14, s * 0.74)
        ..arcToPoint(
          Offset(s * 0.36, s * 0.90),
          radius: Radius.circular(s * 0.18),
          clockwise: false,
        )
        ..lineTo(s * 0.64, s * 0.90)
        ..arcToPoint(
          Offset(s * 0.86, s * 0.74),
          radius: Radius.circular(s * 0.18),
          clockwise: false,
        )
        ..lineTo(s * 0.86, s * 0.46),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Ray üzerinde üç durak; ilk ikisi "hatırlanmış" olarak dolu.
  void _paintSequence(Canvas canvas, double s, Paint fill, Paint stroke) {
    // Dört noktayla çizilmişti: 24pt'de nokta çapı ile aralık eşitleniyor,
    // noktalar birbirine değip tek bir leke oluyordu. Üç nokta aynı fikri
    // anlatıyor ve aralarında görünür boşluk kalıyor.
    final y = s * 0.5;
    canvas.drawLine(
      Offset(s * 0.12, y),
      Offset(s * 0.88, y),
      Paint()
        ..color = color.withValues(alpha: 0.40)
        ..strokeWidth = s * 0.065
        ..strokeCap = StrokeCap.round,
    );

    const count = 3;
    for (var i = 0; i < count; i++) {
      final x = s * 0.18 + (s * 0.64) * i / (count - 1);
      final remembered = i < 2;
      canvas.drawCircle(
        Offset(x, y),
        s * 0.105,
        remembered
            ? fill
            : (Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = s * 0.065),
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
