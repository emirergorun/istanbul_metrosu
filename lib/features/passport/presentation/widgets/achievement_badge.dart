import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/achievement.dart';

/// Yolculuk Kartı'nın rozeti — toplanabilir bir metro pini.
///
/// Ortak dilbilgisi her rozette aynı: yuvarlatılmış altıgen jeton gövdesi,
/// ince dış halka, ortada tek bir işaret. Pasaport damgası benzetmesi
/// kaldırıldı; bunlar damga değil, kartın üstünde biriken **pinler**.
///
/// Ölçü: "bu rozet gerçekten mineli bir pin olarak üretilseydi yine iyi
/// görünür müydü?" Bu yüzden her işaret tek fikirli, kalın geometrili ve
/// negatif alanı açık. İlerleme yayı rozetin üstünde **yok**: ilerleme
/// karta ait, rozetin kendisi temiz kalıyor.
///
/// İki hâl var: açık ve kilitli. Kilitli rozet gizlenmiyor — aynı gövde,
/// aynı işaret, yalnız soluk. Oyuncu ne toplayabileceğini görmeli.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.definition,
    required this.unlocked,
    this.size = 44,
  });

  final AchievementDefinition definition;
  final bool unlocked;
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
          painter: BadgePinPainter(
            glyph: BadgeGlyph.of(definition),
            color: colorOf(definition.category),
            unlocked: unlocked,
            master: kMasterAchievementIds.contains(definition.id),
          ),
        ),
      ),
    );
  }
}

/// Koleksiyonun büyük parçaları.
///
/// Daha zengin bir çerçeve alıyorlar ama **aynı aileden** çıkmıyorlar:
/// gövde ve işaret aynı, yalnız dışına ikinci bir halka ve dört çentik
/// ekleniyor. Ayrı bir sanat yönü açmak koleksiyonu böler.
const Set<String> kMasterAchievementIds = <String>{
  'explorer_50',
  'line_complete_3',
  'every_game',
  'journey_20',
  'journey_100',
  'daily_30',
  'streak_7',
  'escape_levels_all',
  'escape_stars_all',
};

/// Rozetin ortasındaki işaret.
///
/// Kategoriye değil **başarıma** ait: dört kategori işareti on altı rozeti
/// birbirinin kopyası yapıyordu. Her işaret tek bir fikir anlatır.
enum BadgeGlyph {
  /// Tek durak — ilk keşif.
  station,

  /// Üç durak yan yana — kâşif kademeleri.
  stationRow,

  /// Hat üstünde beş durak — büyük kâşif.
  stationLine,

  /// İki hattın kesiştiği düğüm — aktarma.
  interchange,

  /// Uçtan uca dolmuş tek hat.
  lineFull,

  /// Üç paralel hat.
  lineTriple,

  /// Tren burnu — ilk yolculuk.
  train,

  /// Üst üste iki chevron — sık yolcu.
  chevronDouble,

  /// Üç chevron — çok yolculuk.
  chevronTriple,

  /// Üç bloklu parça — Blok Metro.
  tray,

  /// Karşılıklı iki ok — oyundan oyuna geçen oyuncu.
  switchGames,

  /// İki rayın arasından yukarı çıkan ok — Karşıdan Karşıya.
  crossing,

  /// Durakları olan çember — yüz yolculuk, tam tur.
  ring,

  /// Soru işareti gövdesi — Metro Bilgi.
  quiz,

  /// Tam dolu ızgara — bütün oyunlar.
  gridFull,

  /// Üç günlük sütun.
  streakThree,

  /// Yedi günlük sütun.
  streakSeven,

  /// Takvim — toplam gün.
  calendar,

  /// Tünel kemeri ve içine giren metro — Tünele Kaç'ın ilk kaçışı.
  tunnel,

  /// Ayrılan iki ray — makas.
  railSwitch,

  /// Hattın sonundaki tampon — son sefer.
  terminus,

  /// Halka içinde onay — kusursuz sefer, tek fazla hamle yok.
  flawless,

  /// Yıldız — bütün yıldızlar.
  star;

  /// Başarımın işaretini kimliğinden seçer.
  ///
  /// Kimlik kalıcı ve kayıtta duruyor; başlık değişse de rozet değişmez.
  /// Tanımadığı bir kimlik gelirse kategorinin genel işaretine düşer —
  /// yeni bir başarım eklendiğinde ekran boş rozet çizmesin.
  static BadgeGlyph of(AchievementDefinition definition) =>
      switch (definition.id) {
        'first_discovery' => station,
        'explorer_10' || 'explorer_25' => stationRow,
        'explorer_50' => stationLine,
        'interchange_10' => interchange,
        'line_complete_1' => lineFull,
        'line_complete_3' || 'three_lines' => lineTriple,
        'first_journey' => train,
        'journey_5' => chevronDouble,
        'journey_20' => chevronTriple,
        'game_traveler' => switchGames,
        'blocks_runs_10' => tray,
        'crossing_runs_10' => crossing,
        'journey_100' => ring,
        'quiz_400' => quiz,
        'every_game' => gridFull,
        'streak_3' => streakThree,
        'streak_7' => streakSeven,
        'daily_30' => calendar,
        'escape_first' => tunnel,
        'escape_levels_15' => railSwitch,
        'escape_levels_all' => terminus,
        'escape_perfect' => flawless,
        'escape_stars_all' => star,
        _ => switch (definition.category) {
          AchievementCategory.exploration => station,
          AchievementCategory.journey => train,
          AchievementCategory.gameplay => switchGames,
          AchievementCategory.daily => calendar,
        },
      };
}

/// Rozet gövdesini ve işaretini çizen boyacı.
///
/// `LinePin` ile aynı gövdeyi kullanır: hat pinleri ve başarım rozetleri
/// yan yana durduğunda tek bir koleksiyon gibi okunmalı.
class BadgePinPainter extends CustomPainter {
  const BadgePinPainter({
    required this.glyph,
    required this.color,
    required this.unlocked,
    this.master = false,
  });

  final BadgeGlyph glyph;
  final Color color;
  final bool unlocked;
  final bool master;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - (master ? 3.0 : 1.5);
    final tone = unlocked ? color : AppColors.blocker;

    paintPinBody(
      canvas: canvas,
      center: center,
      radius: radius,
      color: color,
      tone: tone,
      unlocked: unlocked,
      master: master,
    );
    _paintGlyph(canvas, center, radius * 0.56, tone, size.shortestSide);
  }

  void _paintGlyph(
    Canvas canvas,
    Offset center,
    double r,
    Color tone,
    double boxSize,
  ) {
    // Çizgi kalınlığı rozet boyutuyla ölçekleniyor: 28 piksellik raf
    // rozetinde 1.6 piksel ince kalıyor, 44'te kalın.
    final stroke = Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, boxSize * 0.055)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = tone;

    switch (glyph) {
      case BadgeGlyph.station:
        canvas.drawCircle(center, r * 0.78, stroke);
        canvas.drawCircle(center, r * 0.30, fill);

      case BadgeGlyph.stationRow:
        canvas.drawLine(
          Offset(center.dx - r * 0.85, center.dy),
          Offset(center.dx + r * 0.85, center.dy),
          stroke,
        );
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            Offset(center.dx + i * r * 0.85, center.dy),
            r * 0.30,
            fill,
          );
        }

      case BadgeGlyph.stationLine:
        // Kâşifin son kademesi: hat kıvrılıyor, beş durak dolu.
        final path = Path()
          ..moveTo(center.dx - r, center.dy + r * 0.55)
          ..lineTo(center.dx - r * 0.2, center.dy + r * 0.55)
          ..lineTo(center.dx + r * 0.45, center.dy - r * 0.55)
          ..lineTo(center.dx + r, center.dy - r * 0.55);
        canvas.drawPath(path, stroke);
        for (final point in <Offset>[
          Offset(center.dx - r, center.dy + r * 0.55),
          Offset(center.dx - r * 0.2, center.dy + r * 0.55),
          Offset(center.dx + r * 0.45, center.dy - r * 0.55),
          Offset(center.dx + r, center.dy - r * 0.55),
        ]) {
          canvas.drawCircle(point, r * 0.24, fill);
        }

      case BadgeGlyph.interchange:
        canvas.drawLine(
          Offset(center.dx - r, center.dy - r * 0.6),
          Offset(center.dx + r, center.dy + r * 0.6),
          stroke,
        );
        canvas.drawLine(
          Offset(center.dx - r, center.dy + r * 0.6),
          Offset(center.dx + r, center.dy - r * 0.6),
          stroke,
        );
        canvas.drawCircle(center, r * 0.34, Paint()..color = AppColors.surface);
        canvas.drawCircle(center, r * 0.34, stroke);

      case BadgeGlyph.lineFull:
        canvas.drawLine(
          Offset(center.dx - r * 0.9, center.dy),
          Offset(center.dx + r * 0.9, center.dy),
          stroke,
        );
        canvas.drawCircle(
          Offset(center.dx - r * 0.9, center.dy),
          r * 0.3,
          fill,
        );
        canvas.drawCircle(
          Offset(center.dx + r * 0.9, center.dy),
          r * 0.3,
          fill,
        );

      case BadgeGlyph.lineTriple:
        for (var i = -1; i <= 1; i++) {
          final y = center.dy + i * r * 0.62;
          canvas.drawLine(
            Offset(center.dx - r * 0.85, y),
            Offset(center.dx + r * 0.85, y),
            stroke,
          );
        }

      case BadgeGlyph.train:
        final body = RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy + r * 0.05),
            width: r * 1.5,
            height: r * 1.7,
          ),
          topLeft: Radius.circular(r * 0.6),
          topRight: Radius.circular(r * 0.6),
          bottomLeft: Radius.circular(r * 0.2),
          bottomRight: Radius.circular(r * 0.2),
        );
        canvas.drawRRect(body, stroke);
        canvas.drawLine(
          Offset(center.dx - r * 0.55, center.dy + r * 0.1),
          Offset(center.dx + r * 0.55, center.dy + r * 0.1),
          stroke,
        );

      case BadgeGlyph.chevronDouble:
        _chevrons(canvas, center, r, stroke, 2);

      case BadgeGlyph.chevronTriple:
        _chevrons(canvas, center, r, stroke, 3);

      case BadgeGlyph.tray:
        final side = r * 0.78;
        for (final offset in <Offset>[
          Offset(-side * 0.58, -side * 0.58),
          Offset(side * 0.58, -side * 0.58),
          Offset(-side * 0.58, side * 0.58),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center + offset,
                width: side,
                height: side,
              ),
              Radius.circular(side * 0.2),
            ),
            fill,
          );
        }

      case BadgeGlyph.switchGames:
        // Üstte sağa, altta sola: iki oyun arasında gidip gelen oyuncu.
        for (final dir in <double>[1, -1]) {
          final y = center.dy - dir * r * 0.42;
          final tip = center.dx + dir * r * 0.85;
          canvas.drawLine(
            Offset(center.dx - dir * r * 0.85, y),
            Offset(tip, y),
            stroke,
          );
          canvas.drawPath(
            Path()
              ..moveTo(tip - dir * r * 0.38, y - r * 0.34)
              ..lineTo(tip, y)
              ..lineTo(tip - dir * r * 0.38, y + r * 0.34),
            stroke,
          );
        }

      case BadgeGlyph.crossing:
        // Raylar ortada kesiliyor: ok raylara değmeden aradan geçiyor.
        // Oyunun kendisi bu — trenin gelmediği anı bulup karşıya geçmek.
        final gap = r * 0.34;
        for (final dy in <double>[-0.3, 0.42]) {
          final y = center.dy + dy * r;
          canvas.drawLine(
            Offset(center.dx - r * 0.95, y),
            Offset(center.dx - gap, y),
            stroke,
          );
          canvas.drawLine(
            Offset(center.dx + gap, y),
            Offset(center.dx + r * 0.95, y),
            stroke,
          );
        }
        canvas.drawLine(
          Offset(center.dx, center.dy + r * 0.9),
          Offset(center.dx, center.dy - r * 0.8),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.34, center.dy - r * 0.46)
            ..lineTo(center.dx, center.dy - r * 0.84)
            ..lineTo(center.dx + r * 0.34, center.dy - r * 0.46),
          stroke,
        );

      case BadgeGlyph.ring:
        canvas.drawCircle(center, r * 0.78, stroke);
        for (var i = 0; i < 4; i++) {
          final angle = -math.pi / 2 + i * math.pi / 2;
          canvas.drawCircle(
            center + Offset(math.cos(angle), math.sin(angle)) * r * 0.78,
            r * 0.24,
            fill,
          );
        }

      case BadgeGlyph.gridFull:
        final side = r * 0.78;
        for (final offset in <Offset>[
          Offset(-side * 0.58, -side * 0.58),
          Offset(side * 0.58, -side * 0.58),
          Offset(-side * 0.58, side * 0.58),
          Offset(side * 0.58, side * 0.58),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center + offset,
                width: side,
                height: side,
              ),
              Radius.circular(side * 0.2),
            ),
            fill,
          );
        }

      case BadgeGlyph.quiz:
        // Soru işareti çizilmiyor, **kurgulanıyor**: yay + gövde + nokta.
        // Font çizmek rozet ailesinin dışına düşerdi.
        final rect = Rect.fromCircle(
          center: Offset(center.dx, center.dy - r * 0.42),
          radius: r * 0.52,
        );
        canvas.drawArc(rect, math.pi, math.pi * 1.35, false, stroke);
        canvas.drawLine(
          Offset(center.dx + r * 0.03, center.dy + r * 0.02),
          Offset(center.dx + r * 0.03, center.dy + r * 0.42),
          stroke,
        );
        canvas.drawCircle(
          Offset(center.dx + r * 0.03, center.dy + r * 0.85),
          r * 0.16,
          fill,
        );

      case BadgeGlyph.streakThree:
        _bars(canvas, center, r, fill, 3);

      case BadgeGlyph.streakSeven:
        _bars(canvas, center, r, fill, 5);

      case BadgeGlyph.calendar:
        final frame = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy + r * 0.1),
            width: r * 1.8,
            height: r * 1.6,
          ),
          Radius.circular(r * 0.22),
        );
        canvas.drawRRect(frame, stroke);
        canvas.drawLine(
          Offset(center.dx - r * 0.9, center.dy - r * 0.28),
          Offset(center.dx + r * 0.9, center.dy - r * 0.28),
          stroke,
        );
        canvas.drawCircle(
          Offset(center.dx, center.dy + r * 0.42),
          r * 0.22,
          fill,
        );

      case BadgeGlyph.tunnel:
        // Kemer: yarım daire ve iki ayak; içinde kısa bir metro.
        final arch = Path()
          ..moveTo(center.dx - r * 0.8, center.dy + r * 0.75)
          ..lineTo(center.dx - r * 0.8, center.dy)
          ..arcToPoint(
            Offset(center.dx + r * 0.8, center.dy),
            radius: Radius.circular(r * 0.8),
          )
          ..lineTo(center.dx + r * 0.8, center.dy + r * 0.75);
        canvas.drawPath(arch, stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(center.dx, center.dy + r * 0.3),
              width: r * 0.62,
              height: r * 0.6,
            ),
            Radius.circular(r * 0.18),
          ),
          fill,
        );

      case BadgeGlyph.railSwitch:
        // Düz ray ve ondan ayrılan kol: makas.
        canvas.drawLine(
          Offset(center.dx - r * 0.9, center.dy + r * 0.45),
          Offset(center.dx + r * 0.9, center.dy + r * 0.45),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.5, center.dy + r * 0.45)
            ..quadraticBezierTo(
              center.dx + r * 0.1,
              center.dy + r * 0.45,
              center.dx + r * 0.9,
              center.dy - r * 0.55,
            ),
          stroke,
        );
        canvas.drawCircle(
          Offset(center.dx - r * 0.5, center.dy + r * 0.45),
          r * 0.2,
          fill,
        );

      case BadgeGlyph.terminus:
        // Hat biter, tampon durur.
        canvas.drawLine(
          Offset(center.dx - r * 0.9, center.dy),
          Offset(center.dx + r * 0.55, center.dy),
          stroke,
        );
        canvas.drawLine(
          Offset(center.dx + r * 0.75, center.dy - r * 0.62),
          Offset(center.dx + r * 0.75, center.dy + r * 0.62),
          stroke,
        );
        for (final x in <double>[-0.9, -0.2]) {
          canvas.drawCircle(
            Offset(center.dx + r * x, center.dy),
            r * 0.24,
            fill,
          );
        }

      case BadgeGlyph.flawless:
        canvas.drawCircle(center, r * 0.82, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - r * 0.4, center.dy + r * 0.02)
            ..lineTo(center.dx - r * 0.08, center.dy + r * 0.34)
            ..lineTo(center.dx + r * 0.44, center.dy - r * 0.3),
          stroke,
        );

      case BadgeGlyph.star:
        final points = <Offset>[
          for (var i = 0; i < 10; i++)
            center +
                Offset(
                      math.cos(-math.pi / 2 + i * math.pi / 5),
                      math.sin(-math.pi / 2 + i * math.pi / 5),
                    ) *
                    (r * (i.isEven ? 0.95 : 0.42)),
        ];
        canvas.drawPath(Path()..addPolygon(points, true), fill);
    }
  }

  void _chevrons(
    Canvas canvas,
    Offset center,
    double r,
    Paint stroke,
    int count,
  ) {
    final gap = r * 0.62;
    final top = center.dy - gap * (count - 1) / 2;
    for (var i = 0; i < count; i++) {
      final y = top + i * gap;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - r * 0.7, y + r * 0.22)
          ..lineTo(center.dx, y - r * 0.24)
          ..lineTo(center.dx + r * 0.7, y + r * 0.22),
        stroke,
      );
    }
  }

  void _bars(Canvas canvas, Offset center, double r, Paint fill, int count) {
    final width = r * 0.30;
    final gap = r * 0.46;
    final left = center.dx - gap * (count - 1) / 2;
    for (var i = 0; i < count; i++) {
      // Sütunlar yükseliyor: seri uzadıkça grafik de yükseliyor.
      final height = r * (0.55 + 0.30 * i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + i * gap - width / 2,
            center.dy + r * 0.8 - height,
            width,
            height,
          ),
          Radius.circular(width / 2),
        ),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(BadgePinPainter old) =>
      old.unlocked != unlocked ||
      old.color != color ||
      old.glyph != glyph ||
      old.master != master;
}

/// Koleksiyonun ortak gövdesi: yuvarlatılmış altıgen jeton.
///
/// Hem başarım rozetleri hem hat pinleri bunu kullanıyor. Tek bir yerde
/// duruyor ki koleksiyon ikiye bölünmesin.
void paintPinBody({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required Color color,
  required Color tone,
  required bool unlocked,
  bool master = false,
}) {
  final body = _roundedHexagon(center, radius);

  if (unlocked) {
    // Mine pinin kalınlığı: gövdenin koyu bir kopyası bir tık aşağıda.
    // Gölge ya da parlama değil, basılı bir parçanın kenarı.
    canvas.drawPath(
      body.shift(Offset(0, math.max(1.2, radius * 0.1))),
      Paint()..color = Color.lerp(color, Colors.black, 0.6)!,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = Color.alphaBlend(
          color.withValues(alpha: 0.2),
          AppColors.surface,
        ),
    );
  }
  canvas.drawPath(
    body,
    Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = unlocked ? 1.8 : 1.2
      ..strokeJoin = StrokeJoin.round,
  );

  // Büyük koleksiyon parçası: ikinci ince halka. Renk değişmiyor, ailede
  // kalıyor; yalnız çerçeve zenginleşiyor.
  if (master) {
    canvas.drawPath(
      _roundedHexagon(center, radius + 2.5),
      Paint()
        ..color = tone.withValues(alpha: unlocked ? 0.55 : 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// Köşeleri yumuşatılmış altıgen — jeton silueti.
Path _roundedHexagon(Offset center, double radius) {
  const sides = 6;
  final corner = radius * 0.22;
  final points = <Offset>[
    for (var i = 0; i < sides; i++)
      Offset(
        center.dx + radius * math.cos(-math.pi / 2 + i * math.pi / 3),
        center.dy + radius * math.sin(-math.pi / 2 + i * math.pi / 3),
      ),
  ];

  final path = Path();
  for (var i = 0; i < sides; i++) {
    final current = points[i];
    final next = points[(i + 1) % sides];
    final previous = points[(i - 1 + sides) % sides];

    final toPrevious = (previous - current);
    final toNext = (next - current);
    final start = current + toPrevious / toPrevious.distance * corner;
    final end = current + toNext / toNext.distance * corner;

    i == 0 ? path.moveTo(start.dx, start.dy) : path.lineTo(start.dx, start.dy);
    path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
  }
  return path..close();
}
