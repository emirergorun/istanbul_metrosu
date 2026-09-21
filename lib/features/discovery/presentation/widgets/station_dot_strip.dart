import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Hattı metro haritasındaki gibi çizen ilerleme göstergesi.
///
/// Yuvarlak bir dolgu çubuğu yerine hattın kendisi çizilir: bir çizgi,
/// üstünde durak sayısı kadar nokta. Dolu nokta keşfedilmiş durak, boş halka
/// keşfedilmemiş durak.
///
/// Tek çizim dört işi birden yapar:
///
/// * doluluk oranı bir bakışta okunur — çubuğun yaptığı iş,
/// * durak sayısı görünür (M6'da dört nokta, M5'te yirmi dört), hatların
///   ölçeği hissedilir,
/// * durum renge değil **şekle** dayanır; renk körlüğünde de ayırt edilir,
/// * oyunun kendi dilidir: hat rengi artı nokta, metro demektir.
///
/// Doluluk **oran değil dizidir**: hangi durakların keşfedildiği tek tek
/// çizilir. Keşif bitişik olmak zorunda değil — oyuncu hattın ortasından
/// başlamış olabilir — ve aradaki boşlukları görmek "buralar duruyor"
/// demenin en kısa yolu.
///
/// En uzun hat M5, yirmi dört durak: 9 piksel nokta + 4 piksel aralık =
/// 312 piksel. 375 piksellik ekranda kartın iç genişliği ~327 piksel, sığar.
/// Daha uzun bir hat eklenirse noktalar orantılı küçülür (bkz. [_minGap]).
class StationDotStrip extends StatelessWidget {
  const StationDotStrip({super.key, required this.states, required this.color});

  /// Hattın durakları, sırayla: `true` keşfedilmiş demektir.
  final List<bool> states;

  /// Hattın koyu zeminde okunabilir varyantı ([LineTheme.accent]).
  final Color color;

  static const double height = 10;

  @override
  Widget build(BuildContext context) {
    // Noktalar bilgiyi tekrar eder; sayı ve etiket kartın kendisinde yazılı.
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _DotStripPainter(states: states, color: color),
        ),
      ),
    );
  }
}

class _DotStripPainter extends CustomPainter {
  const _DotStripPainter({required this.states, required this.color});

  final List<bool> states;
  final Color color;

  /// İki nokta arasındaki en küçük boşluk.
  ///
  /// Bunun altına inilirse noktalar tek bir çizgiye yapışır ve sayılamaz
  /// hâle gelir; o durumda nokta çapı küçülür.
  static const double _minGap = 3;
  static const double _maxDot = 9;
  static const double _minDot = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final total = states.length;
    if (total <= 0 || size.width <= 0) return;

    var dot = _maxDot;
    if (total > 1) {
      final available = (size.width - (total - 1) * _minGap) / total;
      dot = available.clamp(_minDot, _maxDot);
    }
    final gap = total > 1 ? (size.width - total * dot) / (total - 1) : 0.0;
    final radius = dot / 2;
    final centerY = size.height / 2;
    double centerX(int index) => radius + index * (dot + gap);

    final track = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.outline;
    canvas.drawLine(
      Offset(centerX(0), centerY),
      Offset(centerX(total - 1), centerY),
      track,
    );

    // Ardışık iki keşfedilmiş durak arasındaki parça hat renginde çizilir;
    // gerçek bir hat haritasında olduğu gibi kopuk keşif kopuk görünür.
    final travelled = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var i = 0; i + 1 < total; i++) {
      if (!states[i] || !states[i + 1]) continue;
      canvas.drawLine(
        Offset(centerX(i), centerY),
        Offset(centerX(i + 1), centerY),
        travelled,
      );
    }

    final filled = Paint()..color = color;
    final hollowFill = Paint()..color = AppColors.boardBackground;
    final hollowRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.outline;

    for (var i = 0; i < total; i++) {
      final center = Offset(centerX(i), centerY);
      if (states[i]) {
        canvas.drawCircle(center, radius, filled);
      } else {
        // Önce zemin rengiyle dolduruluyor ki altından geçen çizgi
        // halkanın içinde görünmesin.
        canvas.drawCircle(center, radius, hollowFill);
        canvas.drawCircle(center, radius - 0.7, hollowRing);
      }
    }
  }

  @override
  bool shouldRepaint(_DotStripPainter old) =>
      old.color != color || !listEquals(old.states, states);
}
