import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../session/journey_status.dart';
import '../application/merge_drop_controller.dart';
import '../domain/merge_drop_state.dart';
import 'merge_drop_effects.dart';
import 'metro_token.dart';

/// Depo zemini: uygulamanın en koyu yüzeyinden bir ton açık, lacivert
/// eğilimli. Jetonların hat renkleri bunun üstünde en net okunuyor.
const Color _floor = Color(0xFF151B24);
const Color _bay = Color(0xFF1A212C);

/// Oyun alanı: depo, tehlike çizgisi, nişan, jetonlar ve birleşme efektleri.
///
/// Tek ölçek kuralı: dünya birimi depo genişliği; x, y ve yarıçap aynı
/// sayıyla çarpılır (bkz. [MergeDropController.worldWidth]). Çizilen
/// dikdörtgen fiziğin kendisidir — kenarlar, zemin ve tehlike çizgisi
/// fizikle birebir aynı yerde.
class MergeDropPainter extends CustomPainter {
  MergeDropPainter({
    required this.controller,
    required this.palette,
    required this.effects,
    required this.showGuide,
  });

  final MergeDropController controller;
  final MetroTokenPalette palette;
  final MergeDropEffects effects;

  /// Nişan çizgisi: yalnız parmak tahtadayken.
  final bool showGuide;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / MergeDropController.worldWidth;
    final now = effects.now;
    _paintDepot(canvas, size);
    _paintDanger(canvas, size, scale, now);
    if (showGuide) _paintGuide(canvas, size, scale);

    canvas.save();
    canvas.clipRRect(_depotShape(size));
    final active = effects.active;
    for (final effect in active) {
      _paintPull(canvas, scale, effect, now);
    }
    for (final ball in controller.balls) {
      paintMetroToken(
        canvas,
        Offset(ball.x * scale, ball.y * scale),
        ball.drawRadius * scale,
        ball.level,
        palette,
      );
    }
    _paintHeld(canvas, scale);
    for (final effect in active) {
      _paintRing(canvas, scale, effect, now);
    }
    canvas.restore();
    for (final effect in active) {
      _paintScore(canvas, size, scale, effect, now);
    }
  }

  RRect _depotShape(Size size) =>
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));

  /// Depo: düz zemin, tehlike çizgisinin altında hafif dikey bölmeler (depo
  /// yolları) ve ince bir kenar. Cam kavanoz ya da oyuncak kutusu değil.
  void _paintDepot(Canvas canvas, Size size) {
    final shape = _depotShape(size);
    canvas.drawRRect(shape, Paint()..color = _floor);
    canvas.save();
    canvas.clipRRect(shape);
    // Depo yolları: dört bölme, birer koyu birer açık.
    const bays = 6;
    final bay = size.width / bays;
    final paint = Paint()..color = _bay;
    for (var i = 0; i < bays; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * bay, 0, bay, size.height), paint);
    }
    // Zemin çizgisi: peron kenarı gibi ince bir şerit.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 3, size.width, 3),
      Paint()..color = AppColors.outline.withValues(alpha: 0.7),
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.outline.withValues(alpha: 0.65),
    );
  }

  /// Tehlike çizgisi gerçek tehlikeyi gösterir: sakinken soluk kesikli,
  /// yığın yaklaşınca sarı, çizgi aşılınca kırmızı ve yavaş bir nabız.
  void _paintDanger(Canvas canvas, Size size, double scale, int now) {
    final y = controller.dangerY * scale;
    switch (controller.danger) {
      case MergeDropDanger.calm:
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: 0.16)
          ..strokeWidth = 1;
        for (var x = 6.0; x < size.width - 6; x += 10) {
          canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
        }
      case MergeDropDanger.near:
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = AppColors.warning.withValues(alpha: 0.6)
            ..strokeWidth = 1.5,
        );
      case MergeDropDanger.critical:
        final pulse = 0.5 + 0.5 * math.sin(now / 1000 * math.pi * 3);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, y),
          Paint()
            ..color = AppColors.danger.withValues(alpha: 0.05 + 0.05 * pulse),
        );
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = AppColors.danger.withValues(alpha: 0.6 + 0.4 * pulse)
            ..strokeWidth = 2,
        );
    }
  }

  /// Nişan: tutulan jetonun altından zemine kadar soluk kesikli dikey çizgi.
  /// Yörünge tahmini değil; yalnız bırakılacak sütun.
  void _paintGuide(Canvas canvas, Size size, double scale) {
    if (!controller.canDrop) return;
    final r = mergeDropRadiusForLevel(controller.currentLevel);
    final x = controller.aimX * scale;
    final start = (r * 2 + 0.03) * scale;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var y = start; y < size.height - 4; y += 11) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + 5, size.height)),
        paint,
      );
    }
  }

  /// Tutulan jeton: doğum noktasında, nişanın tepesinde. Bekleme sürerken
  /// soluk — "henüz bırakamazsın".
  void _paintHeld(Canvas canvas, double scale) {
    if (controller.status.isFinished) return;
    final level = controller.currentLevel;
    final r = mergeDropRadiusForLevel(level);
    paintMetroToken(
      canvas,
      Offset(controller.aimX * scale, (r + 0.015) * scale),
      r * scale,
      level,
      palette,
      opacity: controller.canDrop ? 1 : 0.4,
    );
  }

  /// Birleşmenin ilk anı: iki eski jeton birleşme noktasına çekilip söner.
  void _paintPull(Canvas canvas, double scale, MergeEffect effect, int now) {
    final t = (now - effect.startedAt) / MergeDropTiming.pullMs;
    if (t >= 1) return;
    final e = effect.event;
    final eased = Curves.easeInCubic.transform(t.clamp(0.0, 1.0));
    final parentLevel = e.level - 1;
    final r = mergeDropRadiusForLevel(parentLevel) * scale;
    final target = Offset(e.x * scale, e.y * scale);
    for (final (px, py) in <(double, double)>[e.parentA, e.parentB]) {
      final from = Offset(px * scale, py * scale);
      paintMetroToken(
        canvas,
        Offset.lerp(from, target, eased)!,
        r * (1 - 0.35 * eased),
        parentLevel,
        palette,
        opacity: 1 - eased,
      );
    }
  }

  /// Darbe halkası: yeni jetonun çevresinde açılan ince bir halka.
  void _paintRing(Canvas canvas, double scale, MergeEffect effect, int now) {
    final t = (now - effect.startedAt) / MergeDropTiming.ringMs;
    if (t >= 1) return;
    final e = effect.event;
    final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final r = mergeDropRadiusForLevel(e.level) * scale;
    final color = e.level >= mergeDropMaxLevel
        ? AppColors.warning
        : palette.colorOf(e.level);
    canvas.drawCircle(
      Offset(e.x * scale, e.y * scale),
      r * (1.0 + 0.45 * eased),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.08 * (1 - eased))
        ..color = Color.lerp(
          color,
          Colors.white,
          0.35,
        )!.withValues(alpha: 0.75 * (1 - eased)),
    );
  }

  /// Puan yazısı: birleşmenin üstünde doğar, hafifçe yükselir, solar.
  /// Zincirse altında küçük "ZİNCİR ×N".
  void _paintScore(
    Canvas canvas,
    Size size,
    double scale,
    MergeEffect effect,
    int now,
  ) {
    final e = effect.event;
    if (e.points <= 0 && e.chain < 2) return;
    final t = ((now - effect.startedAt) / MergeDropTiming.scoreMs).clamp(
      0.0,
      1.0,
    );
    final rise = Curves.easeOutCubic.transform(t) * 22;
    final alpha = t < 0.45 ? 1.0 : 1 - (t - 0.45) / 0.55;
    final r = mergeDropRadiusForLevel(e.level) * scale;
    var y = e.y * scale - r - 10 - rise;
    final x = (e.x * scale).clamp(24.0, size.width - 24);
    if (e.points > 0) {
      final points = _text(
        '+${e.points}',
        AppText.statSmall.copyWith(
          // Çizici temanın dışında: aile açıkça verilmezse sistem fontuna
          // düşer.
          fontFamily: AppFonts.body,
          fontSize: e.level >= 8 ? 17 : 14,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
      points.paint(canvas, Offset(x - points.width / 2, y - points.height / 2));
      y += points.height * 0.8;
    }
    if (e.chain >= 2) {
      final chain = _text(
        'ZİNCİR ×${e.chain}',
        AppText.micro.copyWith(
          fontFamily: AppFonts.body,
          color: AppColors.warning.withValues(alpha: alpha),
        ),
      );
      chain.paint(canvas, Offset(x - chain.width / 2, y - chain.height / 2));
    }
  }

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(covariant MergeDropPainter oldDelegate) => true;
}

/// Deponun üstündeki şehir: çok soluk tek renkli İstanbul silueti ve zemin
/// çizgisi.
///
/// Metafor bilerek basit: şehir yukarıda, hat deposu yeraltında. Siluet
/// oyunla yarışmasın diye zeminden yalnız bir ton açık; ayrıntı, ışık ya
/// da gradyan yok. Depo sabit oranlı olduğu için uzun ekranlarda kalan
/// boşluğu doldurur, kısa ekranda kendiliğinden küçülür.
class MergeDropSkylinePainter extends CustomPainter {
  const MergeDropSkylinePainter();

  static const Color _city = Color(0xFF1A2029);

  /// Bundan alçak alanda siluet çizilmez: basık bir şehir süs değil leke.
  static const double minHeight = 60;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < minHeight) return;
    final w = size.width;
    final h = size.height;
    final base = h - 1;
    final fill = Paint()..color = _city;

    // Alçak yapılar: bir sıra ev ve han.
    const blocks = <(double, double, double)>[
      (0.00, 0.08, 0.22),
      (0.07, 0.06, 0.30),
      (0.30, 0.10, 0.18),
      (0.39, 0.07, 0.26),
      (0.52, 0.09, 0.20),
      (0.62, 0.08, 0.28),
      (0.86, 0.07, 0.24),
      (0.92, 0.08, 0.17),
    ];
    for (final (x, bw, bh) in blocks) {
      canvas.drawRect(
        Rect.fromLTRB(x * w, base - bh * h, (x + bw) * w, base),
        fill,
      );
    }

    // Cami: kubbe ve iki minare.
    final dome = Offset(0.2 * w, base - 0.26 * h);
    canvas.drawRect(Rect.fromLTRB(0.12 * w, dome.dy, 0.28 * w, base), fill);
    canvas.drawCircle(dome, math.min(0.08 * w, 0.24 * h), fill);
    for (final x in <double>[0.1, 0.3]) {
      final top = base - 0.78 * h;
      canvas.drawRect(
        Rect.fromLTRB((x - 0.006) * w, top, (x + 0.006) * w, base),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo((x - 0.006) * w, top)
          ..lineTo(x * w, top - 0.12 * h)
          ..lineTo((x + 0.006) * w, top)
          ..close(),
        fill,
      );
    }

    // Galata Kulesi: gövde ve konik külah.
    final towerTop = base - 0.72 * h;
    canvas.drawRect(Rect.fromLTRB(0.74 * w, towerTop, 0.80 * w, base), fill);
    canvas.drawPath(
      Path()
        ..moveTo(0.735 * w, towerTop)
        ..lineTo(0.77 * w, towerTop - 0.24 * h)
        ..lineTo(0.805 * w, towerTop)
        ..close(),
      fill,
    );

    // Zemin: şehrin altı, deponun üstü.
    canvas.drawLine(
      Offset(0, base),
      Offset(w, base),
      Paint()
        ..color = AppColors.outline.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant MergeDropSkylinePainter oldDelegate) => false;
}
