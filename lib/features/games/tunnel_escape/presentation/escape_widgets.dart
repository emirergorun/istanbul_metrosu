import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/pressable.dart';
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

/// Oyun denetimlerinin işaretleri — çizilmiş, stok simge değil.
enum EscapeControlGlyph { undo, hint, restart, map }

/// Tahtanın altındaki denetim düğmesi: işaret ve kısa etiket.
///
/// Parmak alanı en az 52 piksel yüksek; üç düğme eşit genişlikte yan yana,
/// başparmağın eriştiği bantta.
class EscapeControlButton extends StatelessWidget {
  const EscapeControlButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.busy = false,
  });

  final EscapeControlGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// İpucu aranırken: işaret soluklaşır.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tone = enabled
        ? AppColors.textPrimary
        : AppColors.textMuted.withValues(alpha: 0.5);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius + 2),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius + 2),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: 20,
              child: CustomPaint(
                painter: _GlyphPainter(
                  glyph: glyph,
                  color: busy ? tone.withValues(alpha: 0.4) : tone,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: AppText.micro.copyWith(color: tone, letterSpacing: 0.9),
            ),
          ],
        ),
      ),
    );
  }
}

/// Denetim işaretinin kendisi, düğmesiz.
class EscapeGlyph extends StatelessWidget {
  const EscapeGlyph({
    super.key,
    required this.glyph,
    this.color = AppColors.textPrimary,
  });

  final EscapeControlGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GlyphPainter(glyph: glyph, color: color),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.color});

  final EscapeControlGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final c = Offset(s / 2, s / 2);

    switch (glyph) {
      case EscapeControlGlyph.undo:
        // Sola kıvrılan ok: son hamleyi geri sar.
        final path = Path()
          ..moveTo(s * 0.26, s * 0.40)
          ..lineTo(s * 0.62, s * 0.40)
          ..arcToPoint(
            Offset(s * 0.62, s * 0.84),
            radius: Radius.circular(s * 0.22),
          )
          ..lineTo(s * 0.34, s * 0.84);
        canvas.drawPath(path, paint);
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.40, s * 0.24)
            ..lineTo(s * 0.24, s * 0.40)
            ..lineTo(s * 0.40, s * 0.56),
          paint,
        );
      case EscapeControlGlyph.hint:
        // İşaret feneri: tek ışık ve iki kısa ışın — "sıradaki adımı göster".
        canvas.drawCircle(c + Offset(0, s * 0.06), s * 0.2, paint);
        canvas.drawLine(
          Offset(s * 0.5, s * 0.08),
          Offset(s * 0.5, s * 0.2),
          paint,
        );
        canvas.drawLine(
          Offset(s * 0.16, s * 0.24),
          Offset(s * 0.24, s * 0.32),
          paint,
        );
        canvas.drawLine(
          Offset(s * 0.84, s * 0.24),
          Offset(s * 0.76, s * 0.32),
          paint,
        );
        canvas.drawLine(
          Offset(s * 0.4, s * 0.9),
          Offset(s * 0.6, s * 0.9),
          paint,
        );
      case EscapeControlGlyph.restart:
        // Kapanmaya yakın çember ve ucunda ok: baştan.
        final rect = Rect.fromCircle(center: c, radius: s * 0.32);
        canvas.drawArc(rect, -math.pi * 0.35, math.pi * 1.65, false, paint);
        final end =
            c +
            Offset(math.cos(-math.pi * 0.35), math.sin(-math.pi * 0.35)) *
                (s * 0.32);
        canvas.drawPath(
          Path()
            ..moveTo(end.dx - s * 0.2, end.dy - s * 0.04)
            ..lineTo(end.dx, end.dy)
            ..lineTo(end.dx - s * 0.02, end.dy + s * 0.2),
          paint,
        );
      case EscapeControlGlyph.map:
        // Hat: üç durak ve onları bağlayan çizgi.
        canvas.drawLine(
          Offset(s * 0.14, s * 0.5),
          Offset(s * 0.86, s * 0.5),
          paint,
        );
        for (final x in <double>[0.2, 0.5, 0.8]) {
          canvas.drawCircle(
            Offset(s * x, s * 0.5),
            s * 0.1,
            Paint()..color = color,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
