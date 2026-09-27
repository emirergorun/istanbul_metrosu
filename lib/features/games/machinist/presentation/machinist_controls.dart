import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../domain/machinist_rules.dart';

/// Basılı tutulan pedal. Parmak değdiği sürece [onChanged] `true`.
///
/// `GestureDetector` yerine `Listener`: dokunma tanıyıcıları basılı
/// tutmayı ancak gecikmeyle bildiriyor, pedalda her milisaniye sayılıyor.
class MachinistPedal extends StatelessWidget {
  const MachinistPedal({
    super.key,
    required this.label,
    required this.color,
    required this.pressed,
    required this.onChanged,
    this.width = 84,
    this.height = 118,
  });

  final String label;
  final Color color;
  final bool pressed;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label pedalı',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onChanged(true),
        onPointerUp: (_) => onChanged(false),
        onPointerCancel: (_) => onChanged(false),
        child: SizedBox(
          width: width,
          height: height + 22,
          child: Column(
            children: <Widget>[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  transformAlignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0022)
                    ..rotateX(pressed ? 0.55 : 0.12),
                  child: CustomPaint(
                    painter: _PedalPainter(color: color, pressed: pressed),
                    size: Size(width, height),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppText.micro.copyWith(
                  color: pressed ? color : AppColors.textSecondary,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PedalPainter extends CustomPainter {
  _PedalPainter({required this.color, required this.pressed});

  final Color color;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Pedal plakası: aşağı doğru hafif daralan, köşeleri yuvarlak.
    final plate = Path()
      ..moveTo(w * 0.08, h * 0.06)
      ..quadraticBezierTo(w * 0.08, 0, w * 0.2, 0)
      ..lineTo(w * 0.8, 0)
      ..quadraticBezierTo(w * 0.92, 0, w * 0.92, h * 0.06)
      ..lineTo(w * 0.84, h * 0.94)
      ..quadraticBezierTo(w * 0.83, h, w * 0.74, h)
      ..lineTo(w * 0.26, h)
      ..quadraticBezierTo(w * 0.17, h, w * 0.16, h * 0.94)
      ..close();
    if (pressed) {
      canvas.drawPath(
        plate,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawPath(
      plate.shift(const Offset(0, 4)),
      Paint()..color = const Color(0xAA000000),
    );
    canvas.drawPath(
      plate,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF9AA1A9),
            const Color(0xFF4B5058),
            const Color(0xFF30343A),
          ],
        ).createShader(Offset.zero & size),
    );
    // Kauçuk kaydırmaz şeritler.
    final rib = Paint()..color = const Color(0xFF16181B);
    final ribHi = Paint()..color = const Color(0x33FFFFFF);
    for (var i = 0; i < 6; i++) {
      final y = h * (0.14 + i * 0.13);
      final inset = w * (0.2 + i * 0.012);
      final r = RRect.fromLTRBR(
        inset,
        y,
        w - inset,
        y + h * 0.07,
        Radius.circular(h * 0.035),
      );
      canvas.drawRRect(r, rib);
      canvas.drawLine(
        Offset(inset + 4, y + 1),
        Offset(w - inset - 4, y + 1),
        ribHi..strokeWidth = 1,
      );
    }
    // Renk kodu: üstte şerit.
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.3,
        h * 0.035,
        w * 0.7,
        h * 0.075,
        const Radius.circular(3),
      ),
      Paint()..color = pressed ? color : color.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = pressed ? color : const Color(0x66FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_PedalPainter old) =>
      old.pressed != pressed || old.color != color;
}

/// Kadranlı hız göstergesi (km/sa).
class MachinistSpeedometer extends StatelessWidget {
  const MachinistSpeedometer({
    super.key,
    required this.kmh,
    required this.throttle,
    required this.brake,
    this.size = 112,
  });

  final double kmh;
  final double throttle;
  final double brake;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hız ${kmh.round()} kilometre',
      child: CustomPaint(
        size: Size.square(size),
        painter: _GaugePainter(kmh: kmh, throttle: throttle, brake: brake),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.kmh,
    required this.throttle,
    required this.brake,
  });

  final double kmh;
  final double throttle;
  final double brake;

  static const double _max = 80;
  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xE6101216));
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x55FFFFFF),
    );
    final arcRect = Rect.fromCircle(center: c, radius: r - 10);
    canvas.drawArc(
      arcRect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0x33FFFFFF),
    );
    // Kırmızı bölge: 70+.
    canvas.drawArc(
      arcRect,
      _start + _sweep * 70 / _max,
      _sweep * 10 / _max,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFFE53935),
    );
    final v = kmh.clamp(0.0, _max);
    canvas.drawArc(
      arcRect,
      _start,
      _sweep * v / _max,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4FC3F7),
    );
    // Çentikler.
    final tick = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1.5;
    for (var k = 0; k <= 8; k++) {
      final a = _start + _sweep * k / 8;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - 18), c + dir * (r - 14), tick);
    }
    // İbre.
    final a = _start + _sweep * v / _max;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
      c,
      c + dir * (r - 16),
      Paint()
        ..color = const Color(0xFFFF7043)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFFFF7043));
    _text(
      canvas,
      '${kmh.round()}',
      c + Offset(0, r * 0.38),
      r * 0.36,
      Colors.white,
    );
    _text(
      canvas,
      'km/sa',
      c + Offset(0, r * 0.66),
      r * 0.15,
      const Color(0x99FFFFFF),
    );
    // Gaz / fren göstergeleri.
    _lamp(
      canvas,
      c + Offset(-r * 0.32, -r * 0.3),
      'G',
      throttle,
      const Color(0xFF34E07A),
    );
    _lamp(
      canvas,
      c + Offset(r * 0.32, -r * 0.3),
      'F',
      brake,
      const Color(0xFFFF5252),
    );
  }

  void _lamp(
    Canvas canvas,
    Offset at,
    String label,
    double level,
    Color color,
  ) {
    canvas.drawCircle(
      at,
      8,
      Paint()..color = Color.lerp(const Color(0xFF2A2D33), color, level)!,
    );
    _text(
      canvas,
      label,
      at,
      9,
      level > 0.4 ? Colors.black : const Color(0x99FFFFFF),
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: kTabularFigures,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.kmh != kmh || old.throttle != throttle || old.brake != brake;
}

/// Duruş ölçeği: durak işaretine göre trenin önü, yeşil bölge ±1,5 m.
class MachinistStopMeter extends StatelessWidget {
  const MachinistStopMeter({super.key, required this.distance});

  /// Durak işaretine kalan mesafe (m); eksi ise geçildi.
  final double distance;

  static const double range = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 34,
      child: CustomPaint(painter: _StopMeterPainter(distance)),
    );
  }
}

class _StopMeterPainter extends CustomPainter {
  _StopMeterPainter(this.distance);

  final double distance;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final barTop = 10.0;
    final barH = 12.0;
    // Ölçek: solda 40 m uzak, sağda 14 m geçmiş. İşaret 3/4'te.
    const behind = MachinistRules.missDistance;
    const range = MachinistStopMeter.range;
    double xOf(double d) => w * (range - d) / (range + behind);
    final bar = RRect.fromLTRBR(
      0,
      barTop,
      w,
      barTop + barH,
      const Radius.circular(6),
    );
    canvas.drawRRect(bar, Paint()..color = const Color(0xCC101216));
    void zone(double from, double to, Color color) {
      canvas.drawRect(
        Rect.fromLTRB(xOf(from), barTop + 2, xOf(to), barTop + barH - 2),
        Paint()..color = color,
      );
    }

    zone(
      MachinistRules.stopTolerance,
      -MachinistRules.stopTolerance,
      const Color(0xFFFFC21A),
    );
    zone(3, -3, const Color(0xFFB5E04A));
    zone(1.5, -1.5, const Color(0xFF34E07A));
    zone(0.5, -0.5, Colors.white);
    // Tren burnu.
    final x = xOf(distance.clamp(-behind, range));
    final nose = Path()
      ..moveTo(x, barTop - 1)
      ..lineTo(x - 7, barTop - 10)
      ..lineTo(x + 7, barTop - 10)
      ..close();
    canvas.drawPath(nose, Paint()..color = Colors.white);
    canvas.drawLine(
      Offset(x, barTop - 1),
      Offset(x, barTop + barH + 1),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: distance >= 0
            ? '${distance.toStringAsFixed(1)} m'
            : '+${(-distance).toStringAsFixed(1)} m',
        style: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          fontFeatures: kTabularFigures,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((x - tp.width / 2).clamp(0, w - tp.width), barTop + barH + 1),
    );
  }

  @override
  bool shouldRepaint(_StopMeterPainter old) => old.distance != distance;
}
