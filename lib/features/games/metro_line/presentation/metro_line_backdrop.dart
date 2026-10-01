import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Metro Hattı'nın arka planı: gün batımında Boğaz.
///
/// Ufukta asma köprü, solda tepede kubbeli ve minareli bir cami, sağda
/// tepede Galata Kulesi ve ev sıraları; denizde Kız Kulesi, vapurlar,
/// martılar. Tahta (yüzen ada) bu sahnenin önünde, denizin üstünde durur.
///
/// Durağan: yalnız boyut değişince yeniden çizilir.
class MetroLineIstanbulBackdrop extends CustomPainter {
  const MetroLineIstanbulBackdrop();

  /// Ufkun ekrandaki yüksekliği (oran).
  static const double horizonFraction = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * horizonFraction;
    final fill = Paint()..isAntiAlias = true;

    // Gökyüzü.
    fill.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, horizon),
      <Color>[
        const Color(0xFF4B4E9C),
        const Color(0xFFE88AB8),
        const Color(0xFFFFD3A5),
      ],
      <double>[0, 0.62, 1],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, horizon + 1), fill);
    fill.shader = null;

    // Güneş ve hâlesi.
    final sun = Offset(w * 0.58, horizon - h * 0.045);
    fill.shader = ui.Gradient.radial(sun, w * 0.5, <Color>[
      const Color(0x99FFE7A6),
      const Color(0x00FFE7A6),
    ]);
    canvas.drawCircle(sun, w * 0.5, fill);
    fill.shader = null;
    fill.color = const Color(0xFFFFEDB8);
    canvas.drawCircle(sun, w * 0.09, fill);

    // Bulutlar.
    fill.color = const Color(0x8CFFF3EA);
    for (final (cx, cy, s) in <(double, double, double)>[
      (0.18, 0.09, 1.0),
      (0.72, 0.06, 0.8),
      (0.5, 0.16, 0.6),
      (0.92, 0.15, 0.7),
    ]) {
      final c = Offset(w * cx, h * cy);
      final r = w * 0.05 * s;
      for (final (dx, rr) in <(double, double)>[
        (0, 1.0),
        (1.1, 0.75),
        (-1.0, 0.65),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset(dx * r, (1 - rr) * r * 0.5),
            width: r * 3 * rr,
            height: r * 1.5 * rr,
          ),
          fill,
        );
      }
    }

    // Uzak kıyı: soluk tepeler.
    fill.color = const Color(0xFFB07FA3);
    final far = Path()..moveTo(0, horizon);
    for (var i = 0; i <= 12; i++) {
      final x = w * i / 12;
      far.lineTo(x, horizon - h * (0.012 + 0.012 * math.sin(i * 1.7)));
    }
    far
      ..lineTo(w, horizon)
      ..close();
    canvas.drawPath(far, fill);

    // Boğaz köprüsü: iki kule, sarkan ana kablo, askılar.
    _bridge(canvas, w, h, horizon);

    // Sol tepe ve cami; sağ tepe, evler ve Galata Kulesi.
    _hill(canvas, w, h, horizon, left: true);
    _mosque(canvas, Offset(w * 0.17, horizon - h * 0.05), w * 0.13);
    _hill(canvas, w, h, horizon, left: false);
    _houses(canvas, w, h, horizon);
    _galata(canvas, Offset(w * 0.84, horizon - h * 0.055), w * 0.11);

    // Deniz.
    fill.shader = ui.Gradient.linear(
      Offset(0, horizon),
      Offset(0, h),
      <Color>[
        const Color(0xFFF2B9A6),
        const Color(0xFF5FA3C8),
        const Color(0xFF2E6F9E),
      ],
      <double>[0, 0.25, 1],
    );
    canvas.drawRect(Rect.fromLTWH(0, horizon, w, h - horizon), fill);
    fill.shader = null;

    // Güneşin denizdeki yansıması.
    final glint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x99FFE7A6);
    for (var k = 0; k < 10; k++) {
      final y = horizon + 4 + k * k * 2.2;
      final half = w * (0.04 + 0.012 * k) * (k.isEven ? 1 : 0.7);
      glint.strokeWidth = 1.5 + k * 0.25;
      canvas.drawLine(
        Offset(sun.dx - half, y),
        Offset(sun.dx + half, y),
        glint,
      );
    }
    // Dalgacıklar.
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..color = const Color(0x40FFFFFF);
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final y = horizon + (h - horizon) * math.pow(rnd.nextDouble(), 1.4);
      final x = rnd.nextDouble() * w;
      final len = 6 + (y - horizon) / h * 22;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x, y), width: len, height: len * 0.35),
        math.pi * 1.1,
        math.pi * 0.8,
        false,
        wave,
      );
    }

    // Kız Kulesi ve vapurlar.
    _maidensTower(canvas, Offset(w * 0.1, h * 0.86), w * 0.1);
    _ferry(canvas, Offset(w * 0.78, horizon + h * 0.05), w * 0.12);
    _ferry(canvas, Offset(w * 0.3, horizon + h * 0.025), w * 0.07);

    // Martılar.
    final gull = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..color = const Color(0xE6FFFFFF);
    for (final (gx, gy, s) in <(double, double, double)>[
      (0.32, 0.1, 1.0),
      (0.38, 0.13, 0.7),
      (0.66, 0.21, 0.85),
      (0.08, 0.2, 0.6),
    ]) {
      final c = Offset(w * gx, h * gy);
      final r = 9 * s;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r, c.dy - r * 0.3)
          ..quadraticBezierTo(c.dx - r * 0.4, c.dy - r * 0.6, c.dx, c.dy)
          ..quadraticBezierTo(
            c.dx + r * 0.4,
            c.dy - r * 0.6,
            c.dx + r,
            c.dy - r * 0.3,
          ),
        gull,
      );
    }
  }

  void _bridge(Canvas c, double w, double h, double horizon) {
    final deckY = horizon - h * 0.028;
    final top = horizon - h * 0.11;
    final t0 = w * 0.3;
    final t1 = w * 0.7;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8A5A86);
    // Tabliye.
    p.strokeWidth = 3;
    c.drawLine(Offset(-w * 0.05, deckY), Offset(w * 1.05, deckY), p);
    // Kuleler.
    p.strokeWidth = 4;
    for (final tx in <double>[t0, t1]) {
      c.drawLine(Offset(tx - 3, horizon), Offset(tx - 3, top), p);
      c.drawLine(Offset(tx + 3, horizon), Offset(tx + 3, top), p);
    }
    // Ana kablo ve askılar.
    p.strokeWidth = 1.6;
    final cable = Path()
      ..moveTo(-w * 0.05, deckY - h * 0.005)
      ..quadraticBezierTo((t0 - w * 0.05) / 2, deckY - h * 0.02, t0, top)
      ..quadraticBezierTo(w / 2, deckY + h * 0.05, t1, top)
      ..quadraticBezierTo(
        (t1 + w * 1.05) / 2,
        deckY - h * 0.02,
        w * 1.05,
        deckY - h * 0.005,
      );
    c.drawPath(cable, p);
    p
      ..strokeWidth = 0.8
      ..color = const Color(0x998A5A86);
    // Ana açıklıkta kablo, iki kule tepesi arasında ikinci derece eğri:
    // y(t) = (1−t)²·tepe + 2t(1−t)·kontrol + t²·tepe.
    final control = deckY + h * 0.05;
    for (var i = 1; i < 14; i++) {
      final t = i / 14;
      final x = t0 + (t1 - t0) * t;
      final y =
          (1 - t) * (1 - t) * top + 2 * t * (1 - t) * control + t * t * top;
      c.drawLine(Offset(x, math.min(y, deckY)), Offset(x, deckY), p);
    }
  }

  void _hill(
    Canvas c,
    double w,
    double h,
    double horizon, {
    required bool left,
  }) {
    final p = Paint()..color = const Color(0xFF7E5A86);
    final path = Path();
    if (left) {
      path
        ..moveTo(0, horizon)
        ..lineTo(0, horizon - h * 0.06)
        ..quadraticBezierTo(w * 0.15, horizon - h * 0.085, w * 0.36, horizon)
        ..close();
    } else {
      path
        ..moveTo(w * 0.6, horizon)
        ..quadraticBezierTo(w * 0.82, horizon - h * 0.09, w, horizon - h * 0.07)
        ..lineTo(w, horizon)
        ..close();
    }
    c.drawPath(path, p);
  }

  void _houses(Canvas c, double w, double h, double horizon) {
    final rnd = math.Random(11);
    const colors = <Color>[
      Color(0xFF9E6F9C),
      Color(0xFFB07FA3),
      Color(0xFF8A5F8E),
    ];
    final window = Paint()..color = const Color(0xCCFFE2A0);
    for (var i = 0; i < 9; i++) {
      final x = w * (0.62 + i * 0.042);
      final t = (x - w * 0.6) / (w * 0.4);
      final ground = horizon - h * 0.075 * math.sin(t * math.pi * 0.6) - 1;
      final hh = h * (0.018 + rnd.nextDouble() * 0.02);
      final ww = w * 0.04;
      c.drawRect(
        Rect.fromLTWH(x, ground - hh, ww, hh + h * 0.02),
        Paint()..color = colors[i % colors.length],
      );
      c.drawPath(
        Path()
          ..moveTo(x - 1, ground - hh)
          ..lineTo(x + ww / 2, ground - hh - ww * 0.4)
          ..lineTo(x + ww + 1, ground - hh)
          ..close(),
        Paint()..color = const Color(0xFFB8645A),
      );
      if (rnd.nextBool()) {
        c.drawRect(
          Rect.fromLTWH(x + ww * 0.35, ground - hh * 0.7, ww * 0.25, hh * 0.25),
          window,
        );
      }
    }
  }

  /// Basamaklı kubbeli cami ve dört minare.
  void _mosque(Canvas c, Offset base, double s) {
    final p = Paint()..color = const Color(0xFF6E4C7E);
    c.drawRect(
      Rect.fromLTWH(base.dx - s * 0.6, base.dy - s * 0.3, s * 1.2, s * 0.3 + 2),
      p,
    );
    for (final side in <double>[-1, 1]) {
      c.drawArc(
        Rect.fromCenter(
          center: Offset(base.dx + side * s * 0.36, base.dy - s * 0.3),
          width: s * 0.46,
          height: s * 0.34,
        ),
        math.pi,
        math.pi,
        true,
        p,
      );
    }
    c.drawRect(
      Rect.fromLTWH(base.dx - s * 0.28, base.dy - s * 0.44, s * 0.56, s * 0.15),
      p,
    );
    c.drawArc(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - s * 0.44),
        width: s * 0.62,
        height: s * 0.6,
      ),
      math.pi,
      math.pi,
      true,
      p,
    );
    c.drawRect(
      Rect.fromLTWH(
        base.dx - s * 0.012,
        base.dy - s * 0.82,
        s * 0.024,
        s * 0.09,
      ),
      p,
    );
    for (final mx in <double>[-0.78, 0.78, -1.0, 1.0]) {
      final x = base.dx + mx * s;
      final mh = s * (mx.abs() < 0.9 ? 1.2 : 1.0);
      final mw = s * 0.045;
      c.drawRect(Rect.fromLTWH(x - mw / 2, base.dy - mh, mw, mh + 2), p);
      c.drawRect(
        Rect.fromLTWH(x - mw, base.dy - mh * 0.72, mw * 2, mw * 0.5),
        p,
      );
      c.drawPath(
        Path()
          ..moveTo(x - mw * 0.7, base.dy - mh)
          ..lineTo(x, base.dy - mh - s * 0.16)
          ..lineTo(x + mw * 0.7, base.dy - mh)
          ..close(),
        p,
      );
    }
  }

  /// Galata Kulesi: taş gövde, pencere sırası, balkon, konik külah.
  void _galata(Canvas c, Offset base, double s) {
    final body = Rect.fromLTWH(
      base.dx - s * 0.16,
      base.dy - s * 1.0,
      s * 0.32,
      s * 1.0 + 2,
    );
    c.drawRect(body, Paint()..color = const Color(0xFF6E4C7E));
    c.drawRect(
      Rect.fromLTWH(body.left, body.top, body.width * 0.4, body.height),
      Paint()..color = const Color(0xFF7E5C8E),
    );
    final win = Paint()..color = const Color(0xCCFFE2A0);
    for (var k = 0; k < 3; k++) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            base.dx - s * 0.03,
            base.dy - s * (0.3 + k * 0.22),
            s * 0.06,
            s * 0.1,
          ),
          Radius.circular(s * 0.03),
        ),
        win,
      );
    }
    final balcony = Rect.fromLTWH(
      base.dx - s * 0.21,
      base.dy - s * 1.04,
      s * 0.42,
      s * 0.05,
    );
    c.drawRect(balcony, Paint()..color = const Color(0xFF5E3F6E));
    c.drawRect(
      Rect.fromLTWH(base.dx - s * 0.14, base.dy - s * 1.18, s * 0.28, s * 0.14),
      Paint()..color = const Color(0xFF6E4C7E),
    );
    for (var k = 0; k < 3; k++) {
      c.drawRect(
        Rect.fromLTWH(
          base.dx - s * 0.11 + k * s * 0.08,
          base.dy - s * 1.15,
          s * 0.04,
          s * 0.07,
        ),
        win,
      );
    }
    c.drawPath(
      Path()
        ..moveTo(base.dx - s * 0.18, base.dy - s * 1.18)
        ..lineTo(base.dx, base.dy - s * 1.62)
        ..lineTo(base.dx + s * 0.18, base.dy - s * 1.18)
        ..close(),
      Paint()..color = const Color(0xFF4F3460),
    );
    c.drawRect(
      Rect.fromLTWH(
        base.dx - s * 0.008,
        base.dy - s * 1.72,
        s * 0.016,
        s * 0.11,
      ),
      Paint()..color = const Color(0xFF4F3460),
    );
  }

  /// Kız Kulesi: adacık, beyaz yapı, kule ve kırmızı şerit.
  void _maidensTower(Canvas c, Offset base, double s) {
    c.drawOval(
      Rect.fromCenter(center: base, width: s * 2.4, height: s * 0.4),
      Paint()..color = const Color(0xFF8C7A70),
    );
    c.drawOval(
      Rect.fromCenter(
        center: base.translate(0, s * 0.12),
        width: s * 2.8,
        height: s * 0.3,
      ),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final wall = Paint()..color = const Color(0xFFF7EFE3);
    c.drawRect(
      Rect.fromLTWH(base.dx - s * 0.9, base.dy - s * 0.55, s * 1.4, s * 0.5),
      wall,
    );
    c.drawRect(
      Rect.fromLTWH(base.dx + s * 0.1, base.dy - s * 1.45, s * 0.38, s * 1.4),
      wall,
    );
    c.drawRect(
      Rect.fromLTWH(base.dx - s * 0.9, base.dy - s * 0.6, s * 1.4, s * 0.07),
      Paint()..color = const Color(0xFFD25A4A),
    );
    c.drawPath(
      Path()
        ..moveTo(base.dx + s * 0.04, base.dy - s * 1.45)
        ..lineTo(base.dx + s * 0.29, base.dy - s * 1.92)
        ..lineTo(base.dx + s * 0.54, base.dy - s * 1.45)
        ..close(),
      Paint()..color = const Color(0xFF7D8A96),
    );
  }

  /// Vapur: siyah alt gövde, beyaz üst yapı, sarı-siyah baca.
  void _ferry(Canvas c, Offset base, double s) {
    c.drawRRect(
      RRect.fromLTRBR(
        base.dx - s,
        base.dy - s * 0.18,
        base.dx + s,
        base.dy,
        Radius.circular(s * 0.1),
      ),
      Paint()..color = const Color(0xFF1E2328),
    );
    c.drawRect(
      Rect.fromLTRB(
        base.dx - s * 0.8,
        base.dy - s * 0.42,
        base.dx + s * 0.8,
        base.dy - s * 0.18,
      ),
      Paint()..color = Colors.white,
    );
    final win = Paint()..color = const Color(0xFF3A4A5A);
    for (var i = 0; i < 7; i++) {
      c.drawRect(
        Rect.fromLTWH(
          base.dx - s * 0.7 + i * s * 0.2,
          base.dy - s * 0.36,
          s * 0.09,
          s * 0.1,
        ),
        win,
      );
    }
    final funnel = Rect.fromLTWH(
      base.dx - s * 0.06,
      base.dy - s * 0.62,
      s * 0.14,
      s * 0.2,
    );
    c.drawRect(funnel, Paint()..color = const Color(0xFFF2C12E));
    c.drawRect(
      Rect.fromLTWH(funnel.left, funnel.top, funnel.width, funnel.height * 0.3),
      Paint()..color = const Color(0xFF1E2328),
    );
    c.drawCircle(
      Offset(funnel.center.dx + s * 0.12, funnel.top - s * 0.12),
      s * 0.1,
      Paint()..color = const Color(0x88FFFFFF),
    );
    // Arkasında köpük izi.
    c.drawLine(
      Offset(base.dx + s, base.dy - s * 0.02),
      Offset(base.dx + s * 1.8, base.dy + s * 0.04),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(MetroLineIstanbulBackdrop oldDelegate) => false;
}
