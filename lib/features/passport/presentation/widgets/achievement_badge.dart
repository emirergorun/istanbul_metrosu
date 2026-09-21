import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/achievement.dart';

/// Pasaport damgası — bir başarımın rozeti.
///
/// Stok `Icons.*` kullanılmadı: rozet ailesi uygulamanın kendi çizim diline
/// ait olmalı, aksi hâlde başarımlar Material demosundan kesilip
/// yapıştırılmış gibi durur. Damga sekizgen — turnike kartındaki delgi
/// izine benziyor ve metro dünyasına ait.
///
/// Üç hâl var ve üçü **şekille** de ayrışıyor, yalnız renkle değil:
/// açık damga dolu, ilerleyen damga çevresinde bir yay taşıyor, uzak damga
/// boş bir sekizgen.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.definition,
    required this.unlocked,
    required this.progress,
    this.size = 44,
  });

  final AchievementDefinition definition;
  final bool unlocked;

  /// 0.0 – 1.0.
  final double progress;

  final double size;

  /// Kategorinin rengi.
  ///
  /// Oyun renkleri değil, Okabe–Ito paletinden gelen kategori renkleri
  /// kullanılıyor: rozetler oyunlara değil oyunculuk alanlarına ait.
  static Color colorOf(AchievementCategory category) => switch (category) {
    AchievementCategory.exploration => AppColors.categoryGeography,
    AchievementCategory.journey => AppColors.categoryHistory,
    AchievementCategory.gameplay => AppColors.categoryCultureArt,
    AchievementCategory.daily => AppColors.categorySports,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _BadgePainter(
            category: definition.category,
            color: colorOf(definition.category),
            unlocked: unlocked,
            progress: progress.clamp(0.0, 1.0),
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter({
    required this.category,
    required this.color,
    required this.unlocked,
    required this.progress,
  });

  final AchievementCategory category;
  final Color color;
  final bool unlocked;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1.5;
    final tone = unlocked ? color : AppColors.blocker;

    final seal = _octagon(center, radius);

    if (unlocked) {
      canvas.drawPath(seal, Paint()..color = color.withValues(alpha: 0.20));
    }
    canvas.drawPath(
      seal,
      Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = unlocked ? 1.6 : 1.2,
    );

    // Açılmamış ama ilerlemiş rozet: damganın çevresinde saat yönünde bir
    // yay. Oyuncu "ne kadar kaldı" sorusunu rozete bakarak cevaplıyor.
    if (!unlocked && progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 1),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    _paintMark(canvas, center, radius * 0.52, tone);
  }

  /// Sekizgen damga gövdesi.
  Path _octagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  /// Kategoriyi anlatan iç şekil.
  void _paintMark(Canvas canvas, Offset center, double r, Color tone) {
    final stroke = Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = tone;

    switch (category) {
      // Keşif: durak halkası — keşif ekranındaki durak noktasıyla aynı dil.
      case AchievementCategory.exploration:
        canvas.drawCircle(center, r * 0.75, stroke);
        canvas.drawCircle(center, r * 0.22, fill);
      // Yolculuk: hattın üstünde ilerleyen ok.
      case AchievementCategory.journey:
        canvas.drawLine(
          Offset(center.dx - r, center.dy),
          Offset(center.dx + r * 0.5, center.dy),
          stroke,
        );
        final head = Path()
          ..moveTo(center.dx + r, center.dy)
          ..lineTo(center.dx + r * 0.3, center.dy - r * 0.5)
          ..lineTo(center.dx + r * 0.3, center.dy + r * 0.5)
          ..close();
        canvas.drawPath(head, fill);
      // Oyun: dört kare — blok oyununun tepsisi.
      case AchievementCategory.gameplay:
        final side = r * 0.72;
        for (final offset in <Offset>[
          Offset(-side * 0.6, -side * 0.6),
          Offset(side * 0.6, -side * 0.6),
          Offset(-side * 0.6, side * 0.6),
          Offset(side * 0.6, side * 0.6),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center + offset,
                width: side,
                height: side,
              ),
              const Radius.circular(1.5),
            ),
            fill,
          );
        }
      // Günlük: üç delgi — seri rozetiyle aynı işaret.
      case AchievementCategory.daily:
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            Offset(center.dx + i * r * 0.7, center.dy),
            r * 0.24,
            fill,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.unlocked != unlocked ||
      old.progress != progress ||
      old.color != color ||
      old.category != category;
}
