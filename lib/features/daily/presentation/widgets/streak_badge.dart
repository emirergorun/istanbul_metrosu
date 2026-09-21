import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Seri rozeti — "4 GÜN".
///
/// Emoji değil çizim: uygulamanın ikon dili elle çizilmiş şekiller üzerine
/// kurulu ve emoji her telefonda başka türlü görünüyor. Alev de yok; metro
/// dünyasında karşılığı olmayan bir sembol, oyunun kendi dilinden düşer.
/// Bunun yerine **üst üste damgalanmış bilet delikleri**: turnikeden kaç
/// gün üst üste geçildiğini anlatıyor.
///
/// Seri kırıkken rozet hiç çizilmez — sıfır bir bilgi değil, gürültüdür.
class StreakBadge extends StatelessWidget {
  const StreakBadge({
    super.key,
    required this.days,
    this.completedToday = false,
  });

  final int days;

  /// Bugün tamamlandıysa rozet dolu, değilse sönük çizilir.
  final bool completedToday;

  @override
  Widget build(BuildContext context) {
    if (days <= 0) return const SizedBox.shrink();

    final color = completedToday ? AppColors.success : AppColors.textMuted;

    return Semantics(
      label: completedToday
          ? '$days günlük seri, bugün tamamlandı'
          : '$days günlük seri, bugün henüz tamamlanmadı',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _StreakDots(filled: completedToday, color: color),
              const SizedBox(width: 6),
              Text(
                '$days GÜN',
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.display,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Üç bilet deliği. Doluluk seriyi değil **bugünü** anlatır.
class _StreakDots extends StatelessWidget {
  const _StreakDots({required this.filled, required this.color});

  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 10,
      child: CustomPaint(painter: _StreakDotsPainter(filled, color)),
    );
  }
}

class _StreakDotsPainter extends CustomPainter {
  const _StreakDotsPainter(this.filled, this.color);

  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * 0.26;
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < 3; i++) {
      final dx = radius + i * (size.width - radius * 2) / 2;
      canvas.drawCircle(Offset(dx, size.height / 2), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StreakDotsPainter old) =>
      old.filled != filled || old.color != color;
}
