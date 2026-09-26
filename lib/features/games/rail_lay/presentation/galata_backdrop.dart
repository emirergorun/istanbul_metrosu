import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Ray Döşe'nin arka planı: akşamüstü Haliç ve Galata Kulesi.
///
/// Gerçek bir fotoğraf değil, çizim: hem telif sorunu yok hem de
/// uygulamanın düz, vektörel diliyle (kapaklar, glifler, tren) aynı elden
/// çıkmış görünüyor. Blur yok; derinlik yalnızca gradyan ve katman
/// sırasıyla veriliyor.
///
/// Sahne statik, bu yüzden [shouldRepaint] `false` ve ekran bunu bir
/// `RepaintBoundary` içine koyuyor: oyun saniyede 60 kez yeniden çizilirken
/// kule bir kez çizilip önbellekte kalıyor.
class GalataBackdropPainter extends CustomPainter {
  const GalataBackdropPainter();

  // --- Palet: gün batımı ---
  static const Color _skyTop = AppColors.brandNavyDeep;
  static const Color _skyHigh = Color(0xFF2B2A5C);
  static const Color _skyMid = Color(0xFF7A3F6E);
  static const Color _skyLow = Color(0xFFD9745A);
  static const Color _horizonGlow = Color(0xFFF3B267);
  static const Color _farShore = Color(0xFF3B2B55);
  static const Color _waterTop = Color(0xFF4A355E);
  static const Color _waterBottom = Color(0xFF1C1B2C);
  static const Color _nearHill = Color(0xFF221B33);
  static const Color _houses = Color(0xFF2E2442);
  static const Color _litWindow = Color(0xFFFFC66E);

  // --- Kule: batıdan (soldan) güneş alan taş ---
  static const Color _stoneLit = Color(0xFFE8C9A0);
  static const Color _stoneMid = Color(0xFFC49C74);
  static const Color _stoneShade = Color(0xFF8A6A55);
  static const Color _opening = Color(0xFF2D2233);
  static const Color _roofLit = Color(0xFF6F7A93);
  static const Color _roofMid = Color(0xFF414A60);
  static const Color _roofShade = Color(0xFF2E3446);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final horizon = size.height * 0.66;

    _paintSky(canvas, size, horizon);
    _paintFarShore(canvas, size, horizon);
    _paintWater(canvas, size, horizon);
    _paintNearHill(canvas, size, horizon);
    _paintTower(
      canvas,
      base: Offset(size.width * 0.78, horizon + size.height * 0.012),
      height: size.height * 0.42,
    );
    _paintHouses(canvas, size, horizon);
    _paintScrim(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size, double horizon) {
    final rect = Rect.fromLTWH(0, 0, size.width, horizon);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_skyTop, _skyHigh, _skyMid, _skyLow, _horizonGlow],
          stops: <double>[0, 0.35, 0.62, 0.86, 1],
        ).createShader(rect),
    );

    // Birkaç soluk yıldız: yalnız göğün koyu üst kısmında.
    final star = Paint()..color = Colors.white.withValues(alpha: 0.45);
    const stars = <Offset>[
      Offset(0.08, 0.05),
      Offset(0.22, 0.12),
      Offset(0.41, 0.04),
      Offset(0.57, 0.10),
      Offset(0.66, 0.03),
      Offset(0.92, 0.08),
      Offset(0.33, 0.18),
    ];
    for (final s in stars) {
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        math.max(0.8, size.width * 0.003),
        star,
      );
    }

    // Batan güneş: ufkun hemen üstünde, suyun altında kalan yarısı kesilir.
    final sun = Offset(size.width * 0.30, horizon - size.height * 0.035);
    final radius = size.width * 0.09;
    canvas.drawCircle(
      sun,
      radius * 1.9,
      Paint()..color = const Color(0xFFFFC98A).withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      sun,
      radius,
      Paint()..color = const Color(0xFFFFD9A0).withValues(alpha: 0.92),
    );
  }

  /// Haliç'in karşı kıyısı: tarihi yarımadanın kubbe ve minare silueti.
  void _paintFarShore(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = _farShore;

    // Alçak tepe hattı.
    final ridge = Path()
      ..moveTo(0, horizon)
      ..lineTo(0, horizon - h * 0.018)
      ..quadraticBezierTo(
        w * 0.25,
        horizon - h * 0.032,
        w * 0.5,
        horizon - h * 0.02,
      )
      ..quadraticBezierTo(w * 0.7, horizon - h * 0.012, w, horizon - h * 0.016)
      ..lineTo(w, horizon)
      ..close();
    canvas.drawPath(ridge, fill);

    _paintMosque(
      canvas,
      fill,
      center: Offset(w * 0.18, horizon - h * 0.03),
      dome: w * 0.058,
      minaretHeight: h * 0.10,
      minarets: const <double>[-2.0, -1.45, 1.45, 2.0],
    );
    _paintMosque(
      canvas,
      fill,
      center: Offset(w * 0.47, horizon - h * 0.022),
      dome: w * 0.04,
      minaretHeight: h * 0.07,
      minarets: const <double>[-1.6, 1.6],
    );
  }

  /// Kubbe + iki yarım kubbe + minareler. [minarets] kubbe yarıçapı
  /// cinsinden yatay konumlar.
  void _paintMosque(
    Canvas canvas,
    Paint fill, {
    required Offset center,
    required double dome,
    required double minaretHeight,
    required List<double> minarets,
  }) {
    // Kaide.
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - dome * 1.7,
        center.dy - dome * 0.35,
        center.dx + dome * 1.7,
        center.dy + dome,
      ),
      fill,
    );
    // Ana kubbe ve kasnağı.
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(0, -dome * 0.45),
        width: dome * 1.7,
        height: dome * 0.3,
      ),
      fill,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center.translate(0, -dome * 0.55), radius: dome),
      math.pi,
      math.pi,
      true,
      fill,
    );
    // Yarım kubbeler.
    for (final side in <double>[-1, 1]) {
      canvas.drawArc(
        Rect.fromCircle(
          center: center.translate(side * dome * 1.05, -dome * 0.3),
          radius: dome * 0.55,
        ),
        math.pi,
        math.pi,
        true,
        fill,
      );
    }
    // Minareler: ince gövde, sivri külah.
    final shaft = dome * 0.14;
    for (final x in minarets) {
      final mx = center.dx + x * dome;
      final top = center.dy - minaretHeight;
      canvas.drawRect(
        Rect.fromLTRB(mx - shaft / 2, top, mx + shaft / 2, center.dy + dome),
        fill,
      );
      // Şerefe.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(mx, top + minaretHeight * 0.3),
          width: shaft * 1.8,
          height: shaft * 0.6,
        ),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(mx - shaft * 0.7, top)
          ..lineTo(mx, top - minaretHeight * 0.18)
          ..lineTo(mx + shaft * 0.7, top)
          ..close(),
        fill,
      );
    }
  }

  void _paintWater(Canvas canvas, Size size, double horizon) {
    final rect = Rect.fromLTRB(0, horizon, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_waterTop, _waterBottom],
        ).createShader(rect),
    );

    // Güneşin sudaki yansıması: aşağı indikçe daralan kısa çizgiler.
    final glint = Paint()
      ..color = _horizonGlow.withValues(alpha: 0.35)
      ..strokeWidth = math.max(1, size.height * 0.003)
      ..strokeCap = StrokeCap.round;
    final cx = size.width * 0.30;
    for (var i = 0; i < 7; i++) {
      final y = horizon + size.height * (0.012 + i * 0.022);
      final half = size.width * (0.10 - i * 0.012) * (i.isEven ? 1 : 0.7);
      final shift = (i.isEven ? -1 : 1) * size.width * 0.01;
      canvas.drawLine(
        Offset(cx - half + shift, y),
        Offset(cx + half + shift, y),
        glint,
      );
    }
  }

  /// Galata tepesi: kulenin üzerinde durduğu yakın kıyı.
  void _paintNearHill(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.40, h)
        ..quadraticBezierTo(
          w * 0.52,
          horizon + h * 0.05,
          w * 0.64,
          horizon + h * 0.02,
        )
        ..quadraticBezierTo(
          w * 0.82,
          horizon - h * 0.005,
          w,
          horizon + h * 0.004,
        )
        ..lineTo(w, h)
        ..close(),
      Paint()..color = _nearHill,
    );
  }

  /// Karaköy'ün alçak çatıları: kulenin eteğinde, önünde.
  void _paintHouses(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = _houses;
    final lit = Paint()..color = _litWindow.withValues(alpha: 0.75);

    // (x, genişlik, yükseklik) — ekran oranında, sabit desen.
    const houses = <List<double>>[
      <double>[0.50, 0.07, 0.050],
      <double>[0.57, 0.06, 0.070],
      <double>[0.63, 0.08, 0.045],
      <double>[0.70, 0.05, 0.060],
      <double>[0.86, 0.07, 0.055],
      <double>[0.93, 0.08, 0.075],
    ];
    for (var i = 0; i < houses.length; i++) {
      final house = houses[i];
      final left = house[0] * w;
      final width = house[1] * w;
      final top = horizon + h * 0.05 - house[2] * h;
      final rect = Rect.fromLTRB(left, top, left + width, h);
      canvas.drawRect(rect, body);
      // Kırma çatı.
      canvas.drawPath(
        Path()
          ..moveTo(rect.left - width * 0.05, top)
          ..lineTo(rect.center.dx, top - width * 0.28)
          ..lineTo(rect.right + width * 0.05, top)
          ..close(),
        body,
      );
      // Yanan birkaç pencere.
      final windowSize = width * 0.16;
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          if ((i + row * 2 + col) % 3 == 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              left + width * (0.2 + col * 0.42),
              top + width * (0.18 + row * 0.34),
              windowSize,
              windowSize * 1.2,
            ),
            lit,
          );
        }
      }
    }
  }

  /// Galata Kulesi.
  ///
  /// Hafifçe daralan taş gövde, üç sıra kemerli pencere, seyir balkonu,
  /// kemerli üst kat, konik külah ve tepe süsü. Güneş batıdan (soldan)
  /// geldiği için taş soldan aydınlık, sağa doğru gölgede.
  void _paintTower(
    Canvas canvas, {
    required Offset base,
    required double height,
  }) {
    final cx = base.dx;
    final bottomWidth = height * 0.26;
    final topWidth = height * 0.22;
    final plinth = height * 0.03;
    final bodyBottom = base.dy - plinth;
    final bodyTop = bodyBottom - height * 0.55;

    Paint stone(Rect bounds) => Paint()
      ..shader = const LinearGradient(
        colors: <Color>[_stoneLit, _stoneMid, _stoneShade],
        stops: <double>[0, 0.45, 1],
      ).createShader(bounds);

    // Kaide.
    final plinthRect = Rect.fromCenter(
      center: Offset(cx, base.dy - plinth / 2),
      width: bottomWidth * 1.15,
      height: plinth,
    );
    canvas.drawRect(plinthRect, stone(plinthRect));

    // Gövde: yukarı doğru daralan yamuk.
    final body = Path()
      ..moveTo(cx - bottomWidth / 2, bodyBottom)
      ..lineTo(cx + bottomWidth / 2, bodyBottom)
      ..lineTo(cx + topWidth / 2, bodyTop)
      ..lineTo(cx - topWidth / 2, bodyTop)
      ..close();
    final bodyBounds = body.getBounds();
    canvas.drawPath(body, stone(bodyBounds));

    double widthAt(double y) {
      final t = (bodyBottom - y) / (bodyBottom - bodyTop);
      return bottomWidth + (topWidth - bottomWidth) * t;
    }

    // Taş sıraları.
    canvas.save();
    canvas.clipPath(body);
    final course = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = math.max(0.8, height * 0.003);
    for (
      var y = bodyBottom - height * 0.035;
      y > bodyTop;
      y -= height * 0.035
    ) {
      canvas.drawLine(
        Offset(bodyBounds.left, y),
        Offset(bodyBounds.right, y),
        course,
      );
    }
    canvas.restore();

    // Kemerli pencereler: üç sıra, sırada üç pencere.
    final dark = Paint()..color = _opening;
    final lit = Paint()..color = const Color(0xFFFFD08A);
    for (var row = 0; row < 3; row++) {
      final y = bodyBottom - (bodyBottom - bodyTop) * (0.22 + row * 0.26);
      final rowWidth = widthAt(y);
      for (var col = -1; col <= 1; col++) {
        final center = Offset(cx + col * rowWidth * 0.28, y);
        final window = RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: center,
            width: topWidth * 0.1,
            height: height * 0.05,
          ),
          topLeft: Radius.circular(topWidth * 0.05),
          topRight: Radius.circular(topWidth * 0.05),
        );
        canvas.drawRRect(window, (row + col).isEven && row == 1 ? lit : dark);
      }
    }

    // Seyir balkonu: gövdeden taşan bant ve korkuluk.
    final gallery = Rect.fromCenter(
      center: Offset(cx, bodyTop - height * 0.0125),
      width: topWidth * 1.24,
      height: height * 0.025,
    );
    canvas.drawRect(gallery, stone(gallery));
    canvas.drawLine(
      gallery.bottomLeft,
      gallery.bottomRight,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = math.max(1, height * 0.004),
    );
    final railTop = gallery.top - height * 0.022;
    final rail = Paint()
      ..color = const Color(0xFF6E5646)
      ..strokeWidth = math.max(0.8, height * 0.003);
    canvas.drawLine(
      Offset(gallery.left, railTop),
      Offset(gallery.right, railTop),
      rail,
    );
    for (var x = gallery.left; x <= gallery.right + 0.1; x += topWidth * 0.08) {
      canvas.drawLine(Offset(x, railTop), Offset(x, gallery.top), rail);
    }

    // Üst kat: kemerli açıklıklar sırası.
    final drum = Rect.fromLTRB(
      cx - topWidth / 2,
      gallery.top - height * 0.10,
      cx + topWidth / 2,
      gallery.top,
    );
    canvas.drawRect(drum, stone(drum));
    for (var i = -2; i <= 2; i++) {
      final opening = RRect.fromRectAndCorners(
        Rect.fromCenter(
          center: Offset(
            cx + i * topWidth * 0.19,
            drum.center.dy + height * 0.006,
          ),
          width: topWidth * 0.11,
          height: height * 0.06,
        ),
        topLeft: Radius.circular(topWidth * 0.055),
        topRight: Radius.circular(topWidth * 0.055),
      );
      canvas.drawRRect(opening, dark);
    }

    // Saçak.
    final cornice = Rect.fromCenter(
      center: Offset(cx, drum.top - height * 0.006),
      width: topWidth * 1.1,
      height: height * 0.012,
    );
    canvas.drawRect(cornice, stone(cornice));

    // Konik külah: kenarları hafif şişkin.
    final coneBase = cornice.top;
    final apex = Offset(cx, coneBase - height * 0.27);
    final halfBase = topWidth * 0.54;
    final cone = Path()
      ..moveTo(cx - halfBase, coneBase)
      ..quadraticBezierTo(
        cx - halfBase * 0.55,
        coneBase - height * 0.12,
        apex.dx,
        apex.dy,
      )
      ..quadraticBezierTo(
        cx + halfBase * 0.55,
        coneBase - height * 0.12,
        cx + halfBase,
        coneBase,
      )
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[_roofLit, _roofMid, _roofShade],
          stops: <double>[0, 0.5, 1],
        ).createShader(cone.getBounds()),
    );
    // Külah dikişleri.
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = math.max(0.8, height * 0.003);
    for (final t in <double>[-0.5, 0, 0.5]) {
      canvas.drawLine(Offset(cx + halfBase * t, coneBase), apex, seam);
    }

    // Tepe süsü.
    final finial = Paint()
      ..color = _stoneLit
      ..strokeWidth = math.max(1, height * 0.006)
      ..strokeCap = StrokeCap.round;
    final tip = apex.translate(0, -height * 0.035);
    canvas.drawLine(apex, tip, finial);
    canvas.drawCircle(tip, height * 0.007, Paint()..color = _stoneLit);
  }

  /// HUD ve alt şerit okunabilsin diye üst ve alt kenar koyulaştırılır;
  /// ortada tahta kendi opak karolarıyla zaten öne çıkıyor.
  void _paintScrim(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.background.withValues(alpha: 0.55),
            AppColors.background.withValues(alpha: 0.08),
            AppColors.background.withValues(alpha: 0.18),
            AppColors.background.withValues(alpha: 0.82),
          ],
          stops: const <double>[0, 0.24, 0.62, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant GalataBackdropPainter oldDelegate) => false;
}
