import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../application/simit_catch_controller.dart';
import '../domain/simit_catch_state.dart';

/// Simit Kap sahnesi: Boğaz'da öğle, martı ve simitler.
///
/// Uygulamanın çizim dili: bulanıklık yok, düz renk ve yumuşak gradyan,
/// her ölçü sahne yüksekliğine ([u]) oranlı. Uzak katmanlar (siluet,
/// bulut, dalga, vapur) kendi hızında akar; simitler ve martı dünya
/// koordinatında, fizikle birebir aynı yerde çizilir.
class SimitCatchPainter extends CustomPainter {
  const SimitCatchPainter(this.controller);

  final SimitCatchController controller;

  // Gökyüzü ve deniz.
  static const Color _skyTop = Color(0xFF3E9BE6);
  static const Color _skyBottom = Color(0xFF9AD6F7);
  static const Color _sun = Color(0xFFFFF4C2);
  static const Color _cloud = Color(0xFFF5FAFF);
  static const Color _skyline = Color(0xFF6BB2EA);
  static const Color _skylineFar = Color(0xFF85C2EF);
  static const Color _seaTop = Color(0xFF3B8EE0);
  static const Color _seaBottom = Color(0xFF1C5BB5);
  static const Color _wave = Color(0x66D6ECFF);

  // Simit: fırından yeni çıkmış kabuk, susam.
  static const Color _crust = Color(0xFFD7873A);
  static const Color _crustDark = Color(0xFFA9581F);
  static const Color _crustLight = Color(0xFFF3B464);
  static const Color _sesame = Color(0xFFFFF0CF);
  static const Color _crustPassed = Color(0xFFA6978A);
  static const Color _crustPassedDark = Color(0xFF7D7064);

  // Martı.
  static const Color _gullWhite = Color(0xFFFFFFFF);
  static const Color _gullShade = Color(0xFFDCE6EF);
  static const Color _gullWing = Color(0xFFA9B6C3);
  static const Color _gullWingTip = Color(0xFF3B4450);
  static const Color _beak = Color(0xFFFFB627);
  static const Color _beakTip = Color(0xFFE5482B);
  static const Color _feet = Color(0xFFF08A24);

  /// Ufuk: siluetin tabanı, denizin üstü.
  static const double _horizon = 0.80;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final u = size.height;
    canvas.clipRect(Offset.zero & size);

    _paintSky(canvas, size);
    _paintSun(canvas, size, u);
    _paintClouds(canvas, size, u);
    _paintSkyline(canvas, size, u);
    _paintSea(canvas, size, u);
    _paintFerry(canvas, size, u);

    final simits = controller.simits;
    // Arka yarılar martıdan önce, ön yarılar sonra: martı halkanın
    // içinden geçiyormuş gibi görünsün.
    for (final simit in simits) {
      _paintSimit(canvas, simit, u, back: true);
    }
    _paintTrail(canvas, u);
    _paintGull(canvas, u);
    for (final simit in simits) {
      _paintSimit(canvas, simit, u, back: false);
    }
    _paintArrow(canvas, u);
    _paintSparkles(canvas, u);
    _paintAward(canvas, size, u);
  }

  double _screenX(double worldX, double u) => (worldX - controller.scroll) * u;

  // ------------------------------------------------------------ arka plan

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_skyTop, _skyBottom],
        ).createShader(rect),
    );
  }

  void _paintSun(Canvas canvas, Size size, double u) {
    final center = Offset(size.width * 0.78, u * 0.12);
    final glow = u * 0.17;
    canvas.drawCircle(
      center,
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            _sun.withValues(alpha: 0.55),
            _sun.withValues(alpha: 0.18),
            _sun.withValues(alpha: 0),
          ],
          stops: const <double>[0.25, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: glow)),
    );
    canvas.drawCircle(center, u * 0.05, Paint()..color = _sun);
  }

  /// Bulutlar yavaş akar ve sahnenin dışına çıkınca öbür uçtan girer.
  void _paintClouds(Canvas canvas, Size size, double u) {
    const clouds = <(double, double, double)>[
      // (başlangıç x, y, ölçek) — x sahne yüksekliği cinsinden.
      (0.12, 0.12, 1.0),
      (0.62, 0.30, 0.65),
      (0.95, 0.44, 0.8),
      (0.35, 0.50, 0.6),
      (1.35, 0.22, 0.75),
    ];
    final span = size.width / u + 0.5;
    for (final (x0, y, scale) in clouds) {
      final x = _wrap(x0 - controller.scroll * 0.12, span) - 0.25;
      _cloudShape(canvas, Offset(x * u, y * u), u * 0.12 * scale);
    }
  }

  void _cloudShape(Canvas canvas, Offset base, double w) {
    final paint = Paint()..color = _cloud;
    final h = w * 0.34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(base.dx - w, base.dy - h, w * 2, h),
        Radius.circular(h / 2),
      ),
      paint,
    );
    canvas.drawCircle(Offset(base.dx - w * 0.35, base.dy - h), h * 1.05, paint);
    canvas.drawCircle(
      Offset(base.dx + w * 0.25, base.dy - h * 1.2),
      h * 1.5,
      paint,
    );
  }

  /// İstanbul silueti: köprü, ev sırası, cami ve Galata Kulesi.
  ///
  /// Akış yavaş (sahnenin onda biri) ve iki kez yan yana çizilir;
  /// böylece hep bir bütün olarak görünür.
  void _paintSkyline(Canvas canvas, Size size, double u) {
    final base = _horizon * u;
    final width = math.max(size.width, u * 0.75);
    final offset = -_wrap(controller.scroll * 0.06 * u, width);
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(offset + i * width, 0);
      // Siluet sahnenin uzağında: ölçüleri ön plandakinin %60'ı, yoksa
      // simitlerle aynı büyüklükte kalıp öne çıkıyordu.
      _skylineTile(canvas, width, base, u * 0.6);
      canvas.restore();
    }
  }

  void _skylineTile(Canvas canvas, double w, double base, double u) {
    final far = Paint()..color = _skylineFar;
    final near = Paint()..color = _skyline;

    // Köprü: iki kule, sarkan kablo, tabliye.
    final deck = base - u * 0.07;
    final towerA = w * 0.06;
    final towerB = w * 0.42;
    final towerTop = base - u * 0.21;
    for (final x in <double>[towerA, towerB]) {
      canvas.drawRect(
        Rect.fromLTRB(x - u * 0.008, towerTop, x + u * 0.008, base),
        far,
      );
    }
    final cable = Paint()
      ..color = _skylineFar
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.004;
    final sag = Path()
      ..moveTo(towerA - w * 0.08, deck)
      ..quadraticBezierTo(
        towerA - w * 0.03,
        towerTop + u * 0.04,
        towerA,
        towerTop,
      )
      ..quadraticBezierTo(
        (towerA + towerB) / 2,
        deck - u * 0.005,
        towerB,
        towerTop,
      )
      ..quadraticBezierTo(
        towerB + w * 0.05,
        towerTop + u * 0.06,
        towerB + w * 0.1,
        deck,
      );
    canvas.drawPath(sag, cable);
    for (var i = 1; i < 12; i++) {
      final x = towerA + (towerB - towerA) * i / 12;
      final t = (i / 12 - 0.5).abs() * 2;
      final top = deck - (deck - towerTop) * (0.08 + 0.92 * t * t);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, deck),
        cable..strokeWidth = u * 0.0018,
      );
    }
    cable.strokeWidth = u * 0.004;
    canvas.drawRect(
      Rect.fromLTRB(
        -w * 0.05,
        deck - u * 0.006,
        towerB + w * 0.12,
        deck + u * 0.004,
      ),
      far,
    );

    // Kıyıdaki ev sırası.
    final houses = Path()..moveTo(0, base);
    const roofs = <(double, double)>[
      (0.00, 0.045),
      (0.05, 0.06),
      (0.10, 0.04),
      (0.16, 0.07),
      (0.22, 0.05),
      (0.30, 0.035),
      (0.36, 0.055),
      (0.44, 0.04),
      (0.50, 0.06),
      (0.56, 0.045),
      (0.66, 0.05),
      (0.74, 0.065),
      (0.82, 0.04),
      (0.90, 0.055),
      (0.96, 0.045),
    ];
    for (var i = 0; i < roofs.length; i++) {
      final (x, h) = roofs[i];
      final next = i + 1 < roofs.length ? roofs[i + 1].$1 : 1.0;
      houses
        ..lineTo(x * w, base - h * u)
        ..lineTo(next * w, base - h * u);
    }
    houses
      ..lineTo(w, base)
      ..close();
    canvas.drawPath(houses, far);

    // Cami: büyük kubbe, yarım kubbeler, dört minare.
    final mosqueX = w * 0.68;
    final body = base - u * 0.09;
    canvas.drawRect(
      Rect.fromLTRB(mosqueX - u * 0.11, body, mosqueX + u * 0.11, base),
      near,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(mosqueX, body), radius: u * 0.07),
      math.pi,
      math.pi,
      true,
      near,
    );
    for (final side in <double>[-1, 1]) {
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(mosqueX + side * u * 0.075, body + u * 0.01),
          radius: u * 0.035,
        ),
        math.pi,
        math.pi,
        true,
        near,
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(
        mosqueX - u * 0.003,
        body - u * 0.1,
        mosqueX + u * 0.003,
        body - u * 0.065,
      ),
      near,
    );
    for (final dx in <double>[-0.17, -0.13, 0.13, 0.17]) {
      _minaret(
        canvas,
        Offset(mosqueX + dx * u, base),
        u,
        near,
        tall: dx.abs() > 0.15 ? 0.25 : 0.2,
      );
    }

    // Galata Kulesi: gövde, şerefe, konik külah.
    final towerX = w * 0.92;
    final shaftTop = base - u * 0.19;
    canvas.drawRect(
      Rect.fromLTRB(towerX - u * 0.028, shaftTop, towerX + u * 0.028, base),
      near,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        towerX - u * 0.036,
        shaftTop - u * 0.02,
        towerX + u * 0.036,
        shaftTop,
      ),
      near,
    );
    canvas.drawPath(
      Path()
        ..moveTo(towerX - u * 0.032, shaftTop - u * 0.02)
        ..lineTo(towerX, shaftTop - u * 0.11)
        ..lineTo(towerX + u * 0.032, shaftTop - u * 0.02)
        ..close(),
      near,
    );
  }

  void _minaret(
    Canvas canvas,
    Offset foot,
    double u,
    Paint paint, {
    required double tall,
  }) {
    final top = foot.dy - tall * u;
    canvas.drawRect(
      Rect.fromLTRB(foot.dx - u * 0.006, top, foot.dx + u * 0.006, foot.dy),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        foot.dx - u * 0.01,
        top + tall * u * 0.3,
        foot.dx + u * 0.01,
        top + tall * u * 0.3 + u * 0.006,
      ),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(foot.dx - u * 0.006, top)
        ..lineTo(foot.dx, top - u * 0.035)
        ..lineTo(foot.dx + u * 0.006, top)
        ..close(),
      paint,
    );
  }

  void _paintSea(Canvas canvas, Size size, double u) {
    final top = _horizon * u;
    final rect = Rect.fromLTRB(0, top, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_seaTop, _seaBottom],
        ).createShader(rect),
    );

    // Dalga çizgileri denizle birlikte akar; aşağıdakiler daha hızlı
    // (yakın), yukarıdakiler daha yavaş.
    final wave = Paint()
      ..color = _wave
      ..strokeCap = StrokeCap.round
      ..strokeWidth = u * 0.006;
    const rows = <(double, double)>[
      (0.83, 0.5),
      (0.88, 0.7),
      (0.93, 0.9),
      (0.97, 1.0),
    ];
    for (final (y, speed) in rows) {
      final spacing = u * 0.24;
      final shift = _wrap(controller.scroll * speed * u, spacing);
      for (
        var x = -shift + (y * 97 % 1) * spacing;
        x < size.width + spacing;
        x += spacing
      ) {
        canvas.drawLine(Offset(x, y * u), Offset(x + u * 0.07, y * u), wave);
      }
    }
  }

  /// Vapur: Boğaz'ın simgesi. Sahneden yavaşça geçer, dumanı tüter.
  void _paintFerry(Canvas canvas, Size size, double u) {
    final length = u * 0.3;
    final span = size.width + length * 2;
    final x =
        span - _wrap(controller.scroll * 0.18 * u + span * 0.55, span) - length;
    final waterline = u * 0.86;
    final h = u * 0.045;

    // Gövde: lacivert, kırmızı şerit.
    final hull = Path()
      ..moveTo(x, waterline - h)
      ..lineTo(x + length, waterline - h)
      ..lineTo(x + length * 0.92, waterline)
      ..lineTo(x + length * 0.08, waterline)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF233B5C));
    canvas.drawRect(
      Rect.fromLTWH(x, waterline - h, length, h * 0.18),
      Paint()..color = const Color(0xFFE5483B),
    );

    // İki kat güverte ve sarı pencereler.
    final deck1 = Rect.fromLTWH(
      x + length * 0.08,
      waterline - h * 2.0,
      length * 0.84,
      h,
    );
    final deck2 = Rect.fromLTWH(
      x + length * 0.2,
      waterline - h * 2.9,
      length * 0.58,
      h * 0.9,
    );
    final white = Paint()..color = _gullWhite;
    canvas.drawRRect(
      RRect.fromRectAndRadius(deck1, Radius.circular(h * 0.2)),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(deck2, Radius.circular(h * 0.2)),
      white,
    );
    final window = Paint()..color = const Color(0xFFFFD34D);
    for (final (deck, count) in <(Rect, int)>[(deck1, 9), (deck2, 6)]) {
      final step = deck.width / count;
      for (var i = 0; i < count; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              deck.left + step * (i + 0.25),
              deck.top + deck.height * 0.3,
              step * 0.5,
              deck.height * 0.4,
            ),
            Radius.circular(h * 0.06),
          ),
          window,
        );
      }
    }

    // Baca ve bayrak.
    final funnel = Rect.fromLTWH(
      x + length * 0.38,
      waterline - h * 3.9,
      length * 0.1,
      h,
    );
    canvas.drawRect(funnel, Paint()..color = const Color(0xFFFFC21A));
    canvas.drawRect(
      Rect.fromLTWH(funnel.left, funnel.top, funnel.width, h * 0.22),
      Paint()..color = const Color(0xFF1E2228),
    );
    final mast = Offset(x + length * 0.72, waterline - h * 2.9);
    canvas.drawLine(
      mast,
      mast.translate(0, -h * 0.9),
      Paint()
        ..color = const Color(0xFF233B5C)
        ..strokeWidth = u * 0.003,
    );
    canvas.drawPath(
      Path()
        ..moveTo(mast.dx, mast.dy - h * 0.9)
        ..lineTo(mast.dx + h * 0.55, mast.dy - h * 0.72)
        ..lineTo(mast.dx, mast.dy - h * 0.52)
        ..close(),
      Paint()..color = const Color(0xFFE5483B),
    );

    // Duman: bacadan yükselip büyüyen ve solan halkalar.
    final t = controller.clock;
    for (var i = 0; i < 3; i++) {
      final phase = (t * 0.45 + i / 3) % 1;
      final center = Offset(
        funnel.center.dx - phase * length * 0.25,
        funnel.top - phase * h * 2.6 - h * 0.3,
      );
      canvas.drawCircle(
        center,
        h * (0.35 + phase * 0.55),
        Paint()..color = _gullWhite.withValues(alpha: 0.75 * (1 - phase)),
      );
    }
  }

  // --------------------------------------------------------------- simit

  void _paintSimit(Canvas canvas, Simit simit, double u, {required bool back}) {
    final center = Offset(_screenX(simit.x, u), simit.y * u);
    final rx = simit.halfWidth * u;
    if (center.dx < -rx * 2 || center.dx > u * 3) return;
    final ry = rx * 0.42;
    final thick = simitCatchRimRadius * u * 2.3;
    final passed = simit.state == SimitState.passed;
    final missed = simit.state == SimitState.missed;
    final crust = passed ? _crustPassed : _crust;
    final dark = passed ? _crustPassedDark : _crustDark;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(simit.tilt);
    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: rx * 2,
      height: ry * 2,
    );
    // Arka yarı üst kemer (π..2π), ön yarı alt kemer (0..π).
    final start = back ? math.pi : 0.0;

    // Kabuğun gölgeli alt kenarı, kendisi ve parlak sırtı: üç kalınlıkta
    // aynı kemer.
    canvas.drawArc(
      oval.shift(Offset(0, thick * 0.18)),
      start,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thick
        ..color = dark,
    );
    canvas.drawArc(
      oval,
      start,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thick * 0.82
        ..color = missed
            ? Color.lerp(crust, const Color(0xFFE5483B), 0.45)!
            : crust,
    );
    canvas.drawArc(
      oval.shift(Offset(0, -thick * 0.16)),
      start + 0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thick * 0.22
        ..color = (passed ? _gullShade : _crustLight).withValues(alpha: 0.8),
    );

    // Susam: simide göre sabit (kimliğinden), her karede aynı yerde.
    if (!passed) {
      final seed = math.Random(simit.id * 7919 + (back ? 1 : 0));
      final sesame = Paint()..color = _sesame;
      for (var i = 0; i < 9; i++) {
        final a = start + 0.2 + seed.nextDouble() * (math.pi - 0.4);
        final p =
            Offset(math.cos(a) * rx, math.sin(a) * ry) +
            Offset(0, (seed.nextDouble() - 0.6) * thick * 0.5);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(seed.nextDouble() * math.pi);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: thick * 0.26,
            height: thick * 0.13,
          ),
          sesame,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  /// Sıradaki simidin üstünde aşağı bakan ok: "içine yukarıdan gir".
  void _paintArrow(Canvas canvas, double u) {
    final next = controller.nextSimit;
    if (next == null) return;
    final x = _screenX(next.x, u);
    final bob = math.sin(controller.clock * 5) * u * 0.008;
    final tip = Offset(
      x,
      next.y * u - next.halfWidth * u * 0.42 - u * 0.05 + bob,
    );
    final paint = Paint()
      ..color = _gullWhite
      ..strokeWidth = u * 0.009
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(tip.translate(0, -u * 0.05), tip, paint);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - u * 0.016, tip.dy - u * 0.016)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + u * 0.016, tip.dy - u * 0.016),
      paint,
    );
  }

  // ---------------------------------------------------------------- martı

  void _paintTrail(Canvas canvas, double u) {
    final trail = controller.trail;
    for (var i = 0; i < trail.length; i++) {
      final p = trail[i];
      final t = (i + 1) / (trail.length + 1);
      canvas.drawCircle(
        Offset(_screenX(p.x, u), p.y * u),
        u * (0.003 + 0.004 * t),
        Paint()..color = _gullWhite.withValues(alpha: 0.25 + 0.5 * t),
      );
    }
  }

  void _paintGull(Canvas canvas, double u) {
    final center = Offset(simitCatchBirdX * u, controller.birdY * u);
    final s = u * 0.045; // gövdenin yarı boyu
    // Gövde hıza göre eğilir: yükselirken burun yukarı, düşerken aşağı.
    final tilt = (controller.velocity * 0.55).clamp(-0.45, 0.7);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);

    _paintWing(canvas, s, back: true);

    // Ayaklar.
    final feet = Paint()
      ..color = _feet
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-s * 0.2, s * 0.5),
      Offset(-s * 0.5, s * 0.85),
      feet,
    );
    canvas.drawLine(
      Offset(-s * 0.02, s * 0.52),
      Offset(-s * 0.3, s * 0.9),
      feet,
    );

    // Kuyruk ve gövde.
    canvas.drawPath(
      Path()
        ..moveTo(-s * 0.8, -s * 0.05)
        ..lineTo(-s * 1.35, -s * 0.3)
        ..lineTo(-s * 1.25, s * 0.2)
        ..close(),
      Paint()..color = _gullShade,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-s * 0.1, s * 0.08),
        width: s * 2.0,
        height: s * 1.15,
      ),
      Paint()..color = _gullShade,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-s * 0.1, 0),
        width: s * 1.95,
        height: s * 1.05,
      ),
      Paint()..color = _gullWhite,
    );
    // Baş.
    final head = Offset(s * 0.72, -s * 0.28);
    canvas.drawCircle(head, s * 0.5, Paint()..color = _gullWhite);
    // Gaga.
    canvas.drawPath(
      Path()
        ..moveTo(head.dx + s * 0.38, head.dy - s * 0.02)
        ..lineTo(head.dx + s * 1.05, head.dy + s * 0.2)
        ..lineTo(head.dx + s * 0.36, head.dy + s * 0.26)
        ..close(),
      Paint()..color = _beak,
    );
    canvas.drawCircle(
      Offset(head.dx + s * 0.9, head.dy + s * 0.2),
      s * 0.08,
      Paint()..color = _beakTip,
    );
    // Göz.
    canvas.drawCircle(
      Offset(head.dx + s * 0.16, head.dy - s * 0.08),
      s * 0.1,
      Paint()..color = const Color(0xFF1E2228),
    );
    canvas.drawCircle(
      Offset(head.dx + s * 0.19, head.dy - s * 0.11),
      s * 0.035,
      Paint()..color = _gullWhite,
    );

    _paintWing(canvas, s, back: false);
    canvas.restore();
  }

  /// Kanat: her dokunuşta hızla aşağı vurur ve geri kalkar; arada
  /// süzülürken hafifçe dalgalanır.
  ///
  /// Açı omuzdan ölçülür: eksi yukarı. Arka kanat aynı açıyla, gövdenin
  /// arkasında, daha koyu ve kısa çizilir (derinlik).
  void _paintWing(Canvas canvas, double s, {required bool back}) {
    final angle = _wingAngle();
    final shoulder = Offset(-s * 0.15, -s * 0.2);
    final length = s * (back ? 1.45 : 1.85);

    canvas.save();
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(angle + (back ? -0.25 : 0));
    final wing = Path()
      ..moveTo(0, -s * 0.15)
      ..quadraticBezierTo(length * 0.45, -s * 0.55, length, -s * 0.05)
      ..quadraticBezierTo(length * 0.6, s * 0.2, 0, s * 0.2)
      ..close();
    // Kanat sola doğru, gövdenin üstüne yatık: yukarı bakan omuzdan arkaya.
    canvas.scale(-1, 1);
    canvas.rotate(0.35);
    canvas.drawPath(
      wing,
      Paint()..color = back ? _gullWing.withValues(alpha: 0.85) : _gullWing,
    );
    canvas.drawPath(
      Path()
        ..moveTo(length * 0.68, -s * 0.38)
        ..quadraticBezierTo(length * 0.85, -s * 0.3, length, -s * 0.05)
        ..quadraticBezierTo(length * 0.82, s * 0.05, length * 0.66, s * 0.1)
        ..close(),
      Paint()..color = _gullWingTip,
    );
    canvas.restore();
  }

  double _wingAngle() {
    const up = 0.9; // kanat yukarıda (rad, saat yönü tersine)
    const down = -0.75; // kanat aşağıda
    final since = controller.sinceFlap;
    const strike = 0.09; // aşağı vuruş
    const recover = 0.22; // geri kalkış
    if (since < strike) return up + (down - up) * (since / strike);
    if (since < strike + recover) {
      final t = (since - strike) / recover;
      return down + (up - down) * Curves.easeOut.transform(t);
    }
    // Süzülme: kanat açık, hafif dalga.
    return 0.7 + math.sin(controller.clock * 6) * 0.1;
  }

  // ---------------------------------------------------------------- efekt

  /// TAM İSABET'te simidin çevresinde kısa kıvılcımlar.
  void _paintSparkles(Canvas canvas, double u) {
    if (!controller.lastAwardSwish) return;
    final t = controller.sinceAward;
    if (t < 0 || t > 0.6) return;
    Simit? last;
    for (final simit in controller.simits) {
      if (simit.state == SimitState.passed) last = simit;
    }
    if (last == null) return;
    final center = Offset(_screenX(last.x, u), last.y * u);
    final paint = Paint()
      ..color = const Color(0xFFFFF3A6).withValues(alpha: 1 - t / 0.6);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.55;
      final r = last.halfWidth * u * (0.8 + t * 1.2);
      _star(
        canvas,
        center + Offset(math.cos(a) * r, math.sin(a) * r * 0.7),
        u * 0.014 * (1 - t),
        paint,
      );
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rr = i.isEven ? r : r * 0.3;
      final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path..close(), paint);
  }

  /// "+2 TAM İSABET": puan, yazdığı yerden yükselip kaybolur.
  ///
  /// Sayı yolculuğa yazılan puan (ölçekli); ham sayı skor tablosuyla
  /// tutmazdı.
  void _paintAward(Canvas canvas, Size size, double u) {
    final t = controller.sinceAward;
    const life = 0.9;
    if (controller.lastAward <= 0 || t < 0 || t > life) return;
    final fade = t < life * 0.6 ? 1.0 : 1 - (t - life * 0.6) / (life * 0.4);
    // Martının üstünde: simidin ve martının üstüne binmesin.
    final anchor = Offset(
      simitCatchBirdX * u + u * 0.02,
      controller.awardY * u - u * 0.2 - t * u * 0.08,
    );
    _outlinedText(
      canvas,
      '+${controller.lastAward}',
      anchor,
      u * 0.055,
      const Color(0xFFFFD34D),
      fade,
    );
    if (controller.lastAwardSwish) {
      _outlinedText(
        canvas,
        'TAM İSABET',
        anchor.translate(0, u * 0.055),
        u * 0.03,
        _gullWhite,
        fade,
      );
    }
  }

  void _outlinedText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    double opacity,
  ) {
    TextPainter layout(Paint? stroke, Color? fill) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: fontSize * 0.04,
          color: fill,
          foreground: stroke,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final outline = layout(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * 0.16
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF7A3E12).withValues(alpha: opacity),
      null,
    );
    final fill = layout(null, color.withValues(alpha: opacity));
    final origin = center - Offset(fill.width / 2, fill.height / 2);
    outline.paint(canvas, origin);
    fill.paint(canvas, origin);
  }

  static double _wrap(double value, double span) {
    final r = value % span;
    return r < 0 ? r + span : r;
  }

  @override
  bool shouldRepaint(SimitCatchPainter oldDelegate) => true;
}
