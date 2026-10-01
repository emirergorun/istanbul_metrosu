import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../domain/machinist_rules.dart';

/// Makinist'in sinyal renkleri — tek yerde.
///
/// Oyun baştan sona trafik ışığı diliyle konuşuyor: yeşil kalk, sarı
/// yavaşla, kırmızı dur. Her ekranda aynı üç ton; kırmızının ve yeşilin
/// ikinci, üçüncü kopyaları yok. Kırmızı uygulamanın tehlike rengi.
abstract final class MachinistPalette {
  static const Color go = Color(0xFF34E07A);
  static const Color caution = AppColors.warning;
  static const Color stop = AppColors.danger;

  /// HUD kartlarının zemini: sahnenin açık tünel duvarında da okunur.
  static const Color panel = Color(0xF224282E);
}

/// Kombine kumanda kolu: yukarı itince çekiş, aşağı çekince fren.
///
/// Gerçek metro kabinlerindeki tek kollu kumanda gibi: ortada boş (N),
/// üstte P1–P4 çekiş, altta B1–B4 fren kademeleri. Kol bırakıldığı
/// kademede kalır. Parmak kolu sürükler; kalkınca en yakın kademeye oturur.
///
/// `GestureDetector` yerine `Listener`: sürükleme tanıyıcısı ilk birkaç
/// pikseli yutuyor, kolda gecikme hissediliyordu.
class MachinistMasterLever extends StatefulWidget {
  const MachinistMasterLever({
    super.key,
    required this.value,
    required this.onChanged,
    this.onNotch,
    this.width = 104,
    this.height = 216,
  });

  /// Kol konumu: +1 tam çekiş, 0 boş, −1 tam fren.
  final double value;
  final ValueChanged<double> onChanged;

  /// Kol yeni bir kademeye geçince (titreşim için).
  final ValueChanged<int>? onNotch;
  final double width;
  final double height;

  static const int notches = MachinistRules.leverNotches;

  /// Kademenin adı: P4 … P1, N, B1 … B4.
  static String notchLabel(int notch) => notch > 0
      ? 'P$notch'
      : notch < 0
      ? 'B${-notch}'
      : 'N';

  @override
  State<MachinistMasterLever> createState() => _MachinistMasterLeverState();
}

class _MachinistMasterLeverState extends State<MachinistMasterLever> {
  bool _dragging = false;
  int? _lastNotch;

  /// Yuvanın üst ve alt ucu (kolun gidebildiği aralık), piksel.
  double get _top => 30;
  double get _bottom => widget.height - 26;

  double _valueAt(double y) {
    final t = ((y - _top) / (_bottom - _top)).clamp(0.0, 1.0);
    return 1 - 2 * t;
  }

  int _notchOf(double v) => (v * MachinistMasterLever.notches).round();

  void _move(Offset local, {bool snap = false}) {
    var v = _valueAt(local.dy);
    final notch = _notchOf(v);
    if (snap) v = notch / MachinistMasterLever.notches;
    if (notch != _lastNotch) {
      _lastNotch = notch;
      widget.onNotch?.call(notch);
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final notch = _notchOf(widget.value);
    return Semantics(
      slider: true,
      label: 'Kumanda kolu',
      value: MachinistMasterLever.notchLabel(notch),
      increasedValue: MachinistMasterLever.notchLabel(
        math.min(notch + 1, MachinistMasterLever.notches),
      ),
      decreasedValue: MachinistMasterLever.notchLabel(
        math.max(notch - 1, -MachinistMasterLever.notches),
      ),
      onIncrease: () => widget.onChanged(
        math.min(notch + 1, MachinistMasterLever.notches) /
            MachinistMasterLever.notches,
      ),
      onDecrease: () => widget.onChanged(
        math.max(notch - 1, -MachinistMasterLever.notches) /
            MachinistMasterLever.notches,
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          setState(() => _dragging = true);
          _lastNotch = notch;
          _move(e.localPosition);
        },
        onPointerMove: (e) => _move(e.localPosition),
        onPointerUp: (e) {
          _move(e.localPosition, snap: true);
          setState(() => _dragging = false);
        },
        onPointerCancel: (_) {
          widget.onChanged(notch / MachinistMasterLever.notches);
          setState(() => _dragging = false);
        },
        child: CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _LeverPainter(
            value: widget.value,
            dragging: _dragging,
            top: _top,
            bottom: _bottom,
          ),
        ),
      ),
    );
  }
}

class _LeverPainter extends CustomPainter {
  _LeverPainter({
    required this.value,
    required this.dragging,
    required this.top,
    required this.bottom,
  });

  final double value;
  final bool dragging;
  final double top;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const n = MachinistMasterLever.notches;
    final notch = (value * n).round();
    double yOf(double v) => top + (1 - v) / 2 * (bottom - top);

    // Taban plakası: koyu fırçalanmış metal, köşelerde vida.
    final plate = RRect.fromLTRBR(0, 0, w, h, const Radius.circular(16));
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xF23A3F46), Color(0xF21B1E22)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      plate.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x33FFFFFF),
    );
    for (final p in <Offset>[
      const Offset(10, 10),
      Offset(w - 10, 10),
      Offset(10, h - 10),
      Offset(w - 10, h - 10),
    ]) {
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF15171A));
      canvas.drawCircle(p, 1.4, Paint()..color = const Color(0x55FFFFFF));
    }

    // Kademe bölgeleri: üstte çekiş (yeşil), altta fren (kırmızı).
    final slotX = w * 0.38;
    final scaleX = w * 0.62;
    final powerRect = Rect.fromLTRB(slotX - 9, yOf(1) - 6, slotX + 9, yOf(0));
    final brakeRect = Rect.fromLTRB(slotX - 9, yOf(0), slotX + 9, yOf(-1) + 6);
    canvas.drawRect(
      powerRect,
      Paint()..color = MachinistPalette.go.withValues(alpha: 0.16),
    );
    canvas.drawRect(
      brakeRect,
      Paint()..color = MachinistPalette.stop.withValues(alpha: 0.18),
    );
    // Yuva.
    final slot = RRect.fromLTRBR(
      slotX - 5,
      top - 6,
      slotX + 5,
      bottom + 6,
      const Radius.circular(5),
    );
    canvas.drawRRect(slot, Paint()..color = const Color(0xFF0B0C0E));
    canvas.drawRRect(
      slot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x22FFFFFF),
    );

    // Kademe çentikleri ve adları.
    for (var k = n; k >= -n; k--) {
      final y = yOf(k / n);
      final active = k == notch;
      final color = k > 0
          ? MachinistPalette.go
          : k < 0
          ? MachinistPalette.stop
          : Colors.white;
      canvas.drawLine(
        Offset(slotX + 9, y),
        Offset(slotX + (k == 0 ? 20 : 15), y),
        Paint()
          ..strokeWidth = k == 0 ? 2 : 1.4
          ..color = active ? color : color.withValues(alpha: 0.45),
      );
      _text(
        canvas,
        MachinistMasterLever.notchLabel(k),
        Offset(scaleX + 14, y),
        active ? 12 : 10,
        active ? color : const Color(0x99FFFFFF),
      );
    }

    // Kol: yuvadan çıkan şaft ve T başlıklı tutamak.
    final y = yOf(value);
    final shaft = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[
          Color(0xFF6E757D),
          Color(0xFFD4D9DE),
          Color(0xFF5D636A),
        ],
      ).createShader(Rect.fromLTRB(slotX - 4, y - 8, slotX + 4, y + 8));
    canvas.drawRRect(
      RRect.fromLTRBR(
        slotX - 4,
        y - 7,
        slotX + 4,
        y + 7,
        const Radius.circular(2),
      ),
      shaft,
    );
    final grip = RRect.fromLTRBR(
      slotX - 30,
      y - 12,
      slotX + 30,
      y + 12,
      const Radius.circular(10),
    );
    canvas.drawRRect(
      grip.shift(const Offset(0, 3)),
      Paint()..color = const Color(0x88000000),
    );
    final gripColor = notch > 0
        ? MachinistPalette.go
        : notch < 0
        ? MachinistPalette.stop
        : const Color(0xFFE6E8EB);
    canvas.drawRRect(
      grip,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(gripColor, Colors.white, 0.35)!,
            gripColor,
            Color.lerp(gripColor, Colors.black, 0.35)!,
          ],
        ).createShader(grip.outerRect),
    );
    // Kavrama çizgileri.
    final ridge = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.2;
    for (final dx in <double>[-16, -8, 0, 8, 16]) {
      canvas.drawLine(
        Offset(slotX + dx, y - 6),
        Offset(slotX + dx, y + 6),
        ridge,
      );
    }
    if (dragging) {
      canvas.drawRRect(
        grip.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
    // Üstte kademe adı.
    _text(
      canvas,
      MachinistMasterLever.notchLabel(notch),
      Offset(w / 2, 14),
      13,
      gripColor == const Color(0xFFE6E8EB) ? Colors.white : gripColor,
    );
  }

  void _text(Canvas canvas, String text, Offset center, double size, Color c) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: c,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_LeverPainter old) =>
      old.value != value || old.dragging != dragging;
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
        ..color = MachinistPalette.stop,
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
      MachinistPalette.go,
    );
    _lamp(
      canvas,
      c + Offset(r * 0.32, -r * 0.3),
      'F',
      brake,
      MachinistPalette.stop,
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
      MachinistPalette.caution,
    );
    zone(3, -3, const Color(0xFFB5E04A));
    zone(1.5, -1.5, MachinistPalette.go);
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
