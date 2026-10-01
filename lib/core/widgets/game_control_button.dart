import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'pressable.dart';

/// Oyun denetimlerinin işaretleri — çizilmiş, stok simge değil.
enum GameControlGlyph { undo, hint, restart, left, right }

/// Oyun alanının altındaki denetim: işaret ve kısa etiket, kutusuz.
///
/// Bulmaca oyunlarının ortak denetim ailesi (Tünele Kaç, Ray Döşe).
///
/// Üç denetim tek aile: aynı çizgi kalınlığı, aynı boy, aynı etiket dili.
/// Kutu, çerçeve ya da gölge yok — tahtayla yarışmasınlar. Önem sırası
/// renkle veriliyor: sık kullanılan geri al tam beyaz ([emphasis]), ipucu ve
/// baştan iki ton geride. Böylece bölüm başında tek açık denetim ipucu
/// olsa bile ekranın en parlak ögesi o olmuyor. Parmak alanı 56 piksel yüksek, düğme genişliği
/// kadar geniş.
class GameControlButton extends StatelessWidget {
  const GameControlButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.busy = false,
    this.emphasis = false,
  });

  final GameControlGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// İpucu aranırken: işaret soluklaşır.
  final bool busy;

  /// Ailenin öndeki denetimi.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = emphasis ? AppColors.textPrimary : AppColors.textMuted;
    final tone = enabled ? base : AppColors.textMuted.withValues(alpha: 0.38);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      scale: 0.92,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius + 4),
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: 24,
              child: CustomPaint(
                painter: _GlyphPainter(
                  glyph: glyph,
                  color: busy ? tone.withValues(alpha: 0.4) : tone,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 1,
              style: AppText.caption.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.color});

  final GameControlGlyph glyph;
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
      case GameControlGlyph.undo:
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
      case GameControlGlyph.hint:
        // Ampul: yuvarlak cam, daralan boyun ve iki çizgilik duy.
        final bulb = Path()
          ..moveTo(s * 0.38, s * 0.66)
          ..cubicTo(s * 0.38, s * 0.56, s * 0.24, s * 0.5, s * 0.24, s * 0.36)
          ..arcToPoint(
            Offset(s * 0.76, s * 0.36),
            radius: Radius.circular(s * 0.26),
          )
          ..cubicTo(s * 0.76, s * 0.5, s * 0.62, s * 0.56, s * 0.62, s * 0.66)
          ..close();
        canvas.drawPath(bulb, paint);
        canvas.drawLine(
          Offset(s * 0.4, s * 0.8),
          Offset(s * 0.6, s * 0.8),
          paint,
        );
        canvas.drawLine(
          Offset(s * 0.44, s * 0.92),
          Offset(s * 0.56, s * 0.92),
          paint,
        );
      case GameControlGlyph.left:
      case GameControlGlyph.right:
        // Ray değiştirme oku: kısa gövde ve açık uç, yön verilene bakar.
        final dir = glyph == GameControlGlyph.left ? -1.0 : 1.0;
        final tip = Offset(s * (0.5 + dir * 0.32), s * 0.5);
        canvas.drawLine(Offset(s * (0.5 - dir * 0.3), s * 0.5), tip, paint);
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx - dir * s * 0.24, s * 0.26)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - dir * s * 0.24, s * 0.74),
          paint,
        );
      case GameControlGlyph.restart:
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
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
