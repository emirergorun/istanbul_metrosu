import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../data/metro/metro_repository.dart';
import '../domain/merge_drop_state.dart';

/// Hat Düşür'ün parça renkleri — kanonik hat verisinden.
///
/// M1-M9 gerçek hatların resmî renkleri (`metro.json`; M1 için M1A).
/// İstanbul'da M10 yok, M11'in rengi veride yok: ikisi oyunun ustalık
/// basamakları ve kendi rengini taşıyor — M10 kurumsal lacivert, M11 bütün
/// hatların halkası ([paintMetroToken]).
///
/// Eskiden oyunun kendi 11 renklik listesi vardı: M5 yanlış mor, M6 altın,
/// M8 turkuaz, M9 açık yeşildi; hiçbiri gerçek hattın rengi değildi.
@immutable
class MetroTokenPalette {
  const MetroTokenPalette(this.colors, this.ringColors);

  /// Kanonik hat verisinden kurar; bulunmayan hat için yedek renk.
  factory MetroTokenPalette.from(MetroRepository? metro) {
    Color line(String id, Color fallback) =>
        metro?.lineById(id)?.color ?? fallback;
    final colors = <Color>[
      line('M1A', const Color(0xFFE2261C)),
      line('M2', const Color(0xFF019A44)),
      line('M3', const Color(0xFF05A8E2)),
      line('M4', const Color(0xFFE72177)),
      line('M5', const Color(0xFF693064)),
      line('M6', const Color(0xFFCBAA77)),
      line('M7', const Color(0xFFF39EC0)),
      line('M8', const Color(0xFF447ABE)),
      line('M9', const Color(0xFFFFD300)),
      AppColors.brandNavy,
      AppColors.brandNavyDeep,
    ];
    return MetroTokenPalette(colors, colors.take(9).toList(growable: false));
  }

  /// Yedek palet: hat verisi yokken (kapak aracı, birim testi).
  static final MetroTokenPalette fallback = MetroTokenPalette.from(null);

  /// Seviyeye göre gövde rengi (M1 → 0).
  final List<Color> colors;

  /// M11 halkasının dilimleri: M1-M9'un renkleri.
  final List<Color> ringColors;

  Color colorOf(int level) => colors[(level - 1).clamp(0, colors.length - 1)];
}

/// Jeton çiziminin metin önbelleği: her karede onlarca `TextPainter` kurmak
/// fizik oyununda gereksiz yük.
final Map<String, TextPainter> _labelCache = <String, TextPainter>{};

TextPainter _label(String text, double size, Color color) {
  final key = '$text|${size.round()}|${color.toARGB32()}';
  return _labelCache.putIfAbsent(key, () {
    if (_labelCache.length > 400) _labelCache.clear();
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: size.roundToDouble(),
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: -0.3,
          color: color,
          fontFeatures: kTabularFigures,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  });
}

/// Hat jetonu: metro haritasındaki durak düğümünden türeyen düz bir rozet.
///
/// Fizik dairesinin **içinde** kalır (`radius`); şekil bilerek daire —
/// çarpışma dairesel, göz de daireyi görsün ki "neden değmedi" sorusu
/// doğmasın. Dilbilgisi her seviyede aynı:
///
/// * **Gövde**: hattın rengi, düz. Altında bir tık koyu bir "kalınlık"
///   payı (emaye rozet hissi) — gradyan, parlama, yüz yok.
/// * **Kenar halkası**: gövdenin içinde, okunur renkte ince bir halka.
/// * **Etiket**: M1…M11, okunur renkte.
/// * **Hat motifi**: büyük jetonlarda etiketin altında kısa bir hat ve üç
///   durak noktası.
///
/// Değer arttıkça gürültü değil özen artar:
///
/// * M1-M4: tek halka.
/// * M5-M6: halka kalınlaşır.
/// * M7-M8: halkanın dışına ikinci, ince bir çizgi.
/// * M9-M10: halka durak çentikleriyle bölünür.
/// * M11: lacivert gövde, halka M1-M9'un renklerinden dilimler — bütün
///   hatlar tek rozette.
void paintMetroToken(
  Canvas canvas,
  Offset center,
  double radius,
  int level,
  MetroTokenPalette palette, {
  double opacity = 1,
}) {
  if (radius <= 0.5) return;
  final r = radius;
  final body = palette.colorOf(level);
  final on = LineTheme.readableOn(body);
  final lip = Color.lerp(body, Colors.black, 0.32)!;
  Color fade(Color c, [double a = 1]) => c.withValues(alpha: c.a * a * opacity);

  // Kalınlık payı ve gövde: ikisi birlikte fizik dairesini tam doldurur.
  final face = center.translate(0, -r * 0.03);
  final faceR = r * 0.95;
  canvas.drawCircle(
    center.translate(0, r * 0.05),
    faceR,
    Paint()..color = fade(lip),
  );
  canvas.drawCircle(face, faceR, Paint()..color = fade(body));

  final tier = switch (level) {
    <= 4 => 0,
    <= 6 => 1,
    <= 8 => 2,
    <= 10 => 3,
    _ => 4,
  };

  final ringR = faceR * 0.82;
  final ringW = r * (tier == 0 ? 0.06 : 0.08);
  final ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, ringW)
    ..color = fade(on, 0.82);

  if (tier == 4) {
    // Bütün hatlar: M1-M9 renklerinden eşit dilimli halka.
    final colors = palette.ringColors;
    final sweep = 2 * math.pi / colors.length;
    final rect = Rect.fromCircle(center: face, radius: ringR);
    final slice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * 0.13);
    for (var i = 0; i < colors.length; i++) {
      slice.color = fade(colors[i]);
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + 0.04,
        sweep - 0.08,
        false,
        slice,
      );
    }
  } else if (tier == 3) {
    // Durak çentikli halka: 12 eşit parça, aralarında küçük boşluk.
    const parts = 12;
    final sweep = 2 * math.pi / parts;
    final rect = Rect.fromCircle(center: face, radius: ringR);
    for (var i = 0; i < parts; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + 0.07,
        sweep - 0.14,
        false,
        ringPaint,
      );
    }
  } else {
    canvas.drawCircle(face, ringR, ringPaint);
  }
  if (tier >= 2 && tier < 4) {
    // İkinci, ince çizgi: halkanın hemen dışında.
    canvas.drawCircle(
      face,
      ringR + ringW * 1.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.025)
        ..color = fade(on, 0.45),
    );
  }

  // Etiket.
  final text = mergeDropLabelForLevel(level);
  final fontSize = r * (text.length > 2 ? 0.52 : 0.62);
  final hasMotif = r >= 20;
  final label = _label(text, fontSize, fade(on));
  final labelCenter = face.translate(0, hasMotif ? -r * 0.1 : 0);
  label.paint(
    canvas,
    labelCenter.translate(-label.width / 2, -label.height / 2),
  );

  // Hat motifi: kısa bir hat ve üç durak.
  if (hasMotif) {
    final y = face.dy + r * 0.38;
    final half = r * 0.3;
    final motif = Paint()
      ..color = fade(on, 0.6)
      ..strokeWidth = math.max(1, r * 0.045)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(face.dx - half, y),
      Offset(face.dx + half, y),
      motif,
    );
    for (final dx in <double>[-half, 0, half]) {
      canvas.drawCircle(
        Offset(face.dx + dx, y),
        r * 0.055,
        Paint()..color = fade(on, 0.85),
      );
    }
  }
}

/// Bağımsız jeton: HUD'daki "şimdi / sonra" önizlemesi gibi yerler için.
class MetroTokenView extends StatelessWidget {
  const MetroTokenView({
    super.key,
    required this.level,
    required this.palette,
    this.size = 28,
  });

  final int level;
  final MetroTokenPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _TokenPainter(level, palette)),
  );
}

class _TokenPainter extends CustomPainter {
  const _TokenPainter(this.level, this.palette);

  final int level;
  final MetroTokenPalette palette;

  @override
  void paint(Canvas canvas, Size size) => paintMetroToken(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    level,
    palette,
  );

  @override
  bool shouldRepaint(_TokenPainter old) =>
      old.level != level || old.palette != palette;
}
