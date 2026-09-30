import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import 'escape_painter.dart';

/// Yıldız rengi — sinyal sarısı, tahtadaki tünel oklarıyla aynı.
const Color escapeStarColor = EscapePalette.signal;

/// Tek bir yıldız: dolu ya da boş.
///
/// Stok simge yerine çizim: köşeleri yuvarlatılmış, uygulamanın kalın
/// geometrili glif ailesiyle aynı dilde.
class EscapeStar extends StatelessWidget {
  const EscapeStar({
    super.key,
    required this.filled,
    this.size = 16,
    this.emptyColor = AppColors.outline,
  });

  final bool filled;
  final double size;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _StarPainter(filled: filled, emptyColor: emptyColor),
    ),
  );
}

/// Üç yıldızlık sıra; [count] kadarı dolu.
class EscapeStarRow extends StatelessWidget {
  const EscapeStarRow({
    super.key,
    required this.count,
    this.size = 14,
    this.gap = 2,
    this.emptyColor = AppColors.outline,
  });

  final int count;
  final double size;
  final double gap;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '3 yıldızdan $count',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < 3; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            EscapeStar(filled: i < count, size: size, emptyColor: emptyColor),
          ],
        ],
      ),
    ),
  );
}

class _StarPainter extends CustomPainter {
  const _StarPainter({required this.filled, required this.emptyColor});

  final bool filled;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = starPath(
      Offset(size.width / 2, size.height * 0.53),
      size.width * 0.5,
    );
    if (filled) {
      canvas.drawPath(path, Paint()..color = escapeStarColor);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, size.width * 0.09)
          ..strokeJoin = StrokeJoin.round
          ..color = emptyColor,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.filled != filled || old.emptyColor != emptyColor;
}

/// Beş köşeli yıldız yolu; uçlar hafifçe yuvarlatılmış.
Path starPath(Offset center, double radius) {
  final inner = radius * 0.48;
  final points = <Offset>[
    for (var i = 0; i < 10; i++)
      center +
          Offset(
                math.cos(-math.pi / 2 + i * math.pi / 5),
                math.sin(-math.pi / 2 + i * math.pi / 5),
              ) *
              (i.isEven ? radius : inner),
  ];
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final prev = points[(i - 1 + points.length) % points.length];
    final next = points[(i + 1) % points.length];
    // Her köşeyi küçük bir kavisle kes: sivri yıldız çocuk çizimi gibi
    // duruyordu.
    const cut = 0.14;
    final a = Offset.lerp(p, prev, cut)!;
    final b = Offset.lerp(p, next, cut)!;
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(p.dx, p.dy, b.dx, b.dy);
  }
  return path..close();
}
