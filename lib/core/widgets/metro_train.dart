import 'package:flutter/material.dart';

/// Metro treni — her ölçekte çizilebilen özgün, basit bir şekil.
///
/// Tek çizim kodu iki yerde kullanılır: alt ilerleme çubuğundaki minik ikon
/// ve varış sahnesindeki ekran boyu tren. Tüm oranlar [height] üzerinden
/// hesaplanır, böylece küçük ikon ile dev tren aynı karaktere sahiptir.
///
/// Gövde rengi hattın rengidir; resmi marka görseli kullanılmaz.
class MetroTrain extends StatelessWidget {
  const MetroTrain({
    super.key,
    required this.color,
    required this.height,
    this.wagons = 2,
    this.wagonAspect = MetroTrainPainter.defaultWagonAspect,
  });

  final Color color;
  final double height;
  final int wagons;

  /// Vagon genişliği / yüksekliği. Büyük trenlerde daha uzun vagon iyi durur.
  final double wagonAspect;

  /// Verilen yükseklikte trenin toplam genişliği.
  static double widthFor({
    required double height,
    int wagons = 2,
    double wagonAspect = MetroTrainPainter.defaultWagonAspect,
  }) {
    final wagonWidth = height * wagonAspect;
    final coupling = height * MetroTrainPainter.couplingRatio;
    return wagons * wagonWidth + (wagons - 1) * coupling;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(height: height, wagons: wagons, wagonAspect: wagonAspect),
      height: height,
      child: CustomPaint(
        painter: MetroTrainPainter(
          color: color,
          wagons: wagons,
          wagonAspect: wagonAspect,
        ),
      ),
    );
  }
}

/// [MetroTrain]'in çizimi. Tüm ölçüler vagon yüksekliğine oranlıdır.
class MetroTrainPainter extends CustomPainter {
  const MetroTrainPainter({
    required this.color,
    this.wagons = 2,
    this.wagonAspect = defaultWagonAspect,
  });

  static const double defaultWagonAspect = 1.1;
  static const double couplingRatio = 0.14;

  final Color color;
  final int wagons;
  final double wagonAspect;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final wagonWidth = h * wagonAspect;
    final coupling = h * couplingRatio;

    // Gövde hat rengiyle aynı; ray da öyle. İnce açık kontur olmazsa tren
    // rayın üstünde kaybolur.
    final outline = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (h * 0.078).clamp(1.0, 3.0);

    // Vagonları birleştiren kısa bağlantı.
    final couplingPaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i < wagons - 1; i++) {
      final x = (i + 1) * wagonWidth + i * coupling;
      canvas.drawRect(
        Rect.fromLTWH(
          x - h * 0.03,
          h / 2 - h * 0.078,
          coupling + h * 0.06,
          h * 0.156,
        ),
        couplingPaint,
      );
    }

    for (var i = 0; i < wagons; i++) {
      _paintWagon(
        canvas,
        h: h,
        left: i * (wagonWidth + coupling),
        wagonWidth: wagonWidth,
        outline: outline,
        isFront: i == wagons - 1,
      );
    }
  }

  void _paintWagon(
    Canvas canvas, {
    required double h,
    required double left,
    required double wagonWidth,
    required Paint outline,
    required bool isFront,
  }) {
    // Öndeki vagonun burnu yuvarlak, arkadaki düz — yön belli olsun.
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, 0, wagonWidth, h),
      topLeft: Radius.circular(isFront ? h * 0.11 : h * 0.33),
      bottomLeft: Radius.circular(isFront ? h * 0.11 : h * 0.33),
      topRight: Radius.circular(isFront ? h * 0.5 : h * 0.11),
      bottomRight: Radius.circular(isFront ? h * 0.5 : h * 0.11),
    );

    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(body, outline);

    _paintWindows(
      canvas,
      h: h,
      left: left,
      wagonWidth: wagonWidth,
      isFront: isFront,
    );

    // Alt etek: tekerlek hizasını ima eder.
    canvas.drawRect(
      Rect.fromLTWH(
        left + h * 0.14,
        h - h * 0.19,
        wagonWidth - h * 0.28,
        h * 0.10,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
  }

  void _paintWindows(
    Canvas canvas, {
    required double h,
    required double left,
    required double wagonWidth,
    required bool isFront,
  }) {
    final inset = h * 0.17;
    final windowW = h * 0.30;
    final windowH = h * 0.30;
    final top = h * 0.25;
    final gap = h * 0.12;

    final inner = wagonWidth - inset * 2;
    final count = ((inner + gap) / (windowW + gap)).floor().clamp(2, 8);
    final totalW = count * windowW + (count - 1) * gap;
    final startX = left + (wagonWidth - totalW) / 2;

    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < count; i++) {
      // Öndeki vagonun en sağdaki penceresi ön camdır: biraz daha yuvarlak.
      final isWindshield = isFront && i == count - 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(startX + i * (windowW + gap), top, windowW, windowH),
          Radius.circular(isWindshield ? h * 0.14 : h * 0.08),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MetroTrainPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.wagons != wagons ||
      oldDelegate.wagonAspect != wagonAspect;
}
