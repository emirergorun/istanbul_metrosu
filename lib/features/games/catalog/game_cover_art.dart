import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/metro_train.dart';

/// Bir oyunun kapak kompozisyonu.
///
/// Her oyun için **gerçek mekaniğini** anlatan tek bir sahne çizilir: Blok
/// Metro'da temizlenen bir satır, Hat Birleştir'de birleşen iki tren, Ray
/// Uçuşu'nda tünel açıklığı. Oyuncu adı okumadan ne oynayacağını anlamalı.
///
/// Neden raster değil de çizim:
///
/// * Depoda tek bir raster var (`merge_drop_scene.png`); yedi oyun için
///   üretilecek kapaklar ayrı bir sanat çalışması gerektirir ve kod
///   ortamında üretilen düşük kaliteli bir PNG'yi "hazır" diye koymak
///   ürünü aşağı çeker.
/// * Çizim her ölçekte keskin: aynı kompozisyon galeride 160 piksel,
///   detayda 330 piksel genişlikte bozulmadan çalışıyor.
/// * Uygulamanın kendi görsel dili zaten vektörel ([GameGlyph],
///   [MetroTrainPainter], kategori glifleri). Kapaklar o ailenin devamı.
///
/// Raster kapak üretildiğinde mimari hazır: `MiniGame.coverAsset` doldurulur,
/// [GameCoverArt] o oyunda çizim yerine görseli gösterir. Bkz.
/// `game_cover.dart`.
enum GameCoverScene {
  /// Izgara, yerleşen parça ve temizlenen satır — Blok Metro.
  blocks,

  /// Eğik soru kartı ve dört şık — Metro Bilgi.
  quiz,

  /// İki eş tren karosunun daha büyük bir karoda birleşmesi — Hat Birleştir.
  merge,

  /// Tünel duvarları arasındaki açıklıktan geçen tren — Ray Uçuşu.
  tunnel,

  /// Havuzda büyüyerek yığılan rozetler ve düşen yeni rozet — Hat Düşür.
  drop,

  /// Üç ray, kapalı geçitler ve ray değiştiren tren — Ray Değiştir.
  lanes,

  /// Izgarada kıvrılan tren ve önündeki yolcu — Yolcu Topla.
  snake,

  /// Henüz açılmamış oyun.
  locked,
}

/// Kapağın renk ailesi.
///
/// Zemin oyunun kimlik renginden **türetilir**, ona eşit değildir: kimlik
/// rengi parlak ve nesnenin kendisine ait; zemin aynı tonun koyu ve doygun
/// hâli. Böylece yedi kapak birbirinden ayrılıyor ama uygulamanın koyu
/// kimliğinden kopmuyor.
@immutable
class GameCoverPalette {
  const GameCoverPalette({
    required this.top,
    required this.bottom,
    required this.accent,
    required this.title,
  });

  factory GameCoverPalette.of(Color identity) {
    final hsl = HSLColor.fromColor(identity);
    // Doygunluk tabanı: gri bir kimlik rengi kapağı da grileştirirdi,
    // oysa kapağın işi ilk bakışta ayırt edilmek.
    final saturation = hsl.saturation.clamp(0.42, 0.82);
    final top = hsl.withSaturation(saturation).withLightness(0.20).toColor();
    final bottom = hsl.withSaturation(saturation).withLightness(0.11).toColor();
    return GameCoverPalette(
      top: top,
      bottom: bottom,
      accent: identity,
      title: LineTheme.readableOn(bottom),
    );
  }

  /// Zeminin üst ve alt tonu — aralarında yumuşak bir geçiş var.
  final Color top;
  final Color bottom;

  /// Sahnedeki ana nesnenin ve başlık altı çizgisinin rengi.
  final Color accent;

  /// Zemin üzerinde okunabilir başlık rengi.
  final Color title;
}

/// Kapak: zemin, sahne ve **başlık**.
///
/// Başlık kapağın içinde, sol üstte ve altında kısa bir renk çizgisiyle
/// duruyor. Önce kapağın altına ayrı bir şerit olarak konmuştu; kartlar
/// hizalanıyordu ama sonuç bir oyun kapağından çok etiketli bir kutu gibi
/// okunuyordu. Başlık sahnenin parçası olunca kart "oyun" gibi duruyor.
///
/// Sahneler sol üstte başlığa yer bırakacak şekilde kuruldu; nesneler
/// merkezden aşağı ve sağa toplanıyor.
class GameCoverArt extends StatelessWidget {
  const GameCoverArt({
    super.key,
    required this.scene,
    required this.identity,
    required this.title,
    this.asset,
    this.onLightCover = false,
    this.dimmed = false,
    this.showTitle = true,
  });

  final GameCoverScene scene;

  /// Oyunun kimlik rengi; palet bundan türetilir.
  final Color identity;

  final String title;

  /// Üretilmiş raster kapak. Doluysa çizim yerine bu görsel kullanılır.
  final String? asset;

  /// Kapağın başlık alanı açık renk mi? Bkz. [MiniGame.coverIsLight].
  final bool onLightCover;

  /// Kilitli oyun: sahne soluk, başlık sönük.
  final bool dimmed;

  /// Başlık kapağın içine çizilsin mi?
  ///
  /// Küçük kapaklarda (günün yolculuğu kartındaki 84 piksellik poster)
  /// tabela fontu satır ortasından bölünüyor — "HAT BİRL / EŞTİR". O
  /// bağlamlarda başlık kapağın dışında, kendi satırında yazılıyor.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final palette = GameCoverPalette.of(identity);

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Başlık kartın genişliğiyle ölçekleniyor: aynı kapak galeride
          // 160, detayda 330 piksel genişlikte çiziliyor ve iki yerde de
          // aynı oranda görünmesi gerekiyor.
          final width = constraints.maxWidth;
          final fontSize = (width * 0.088).clamp(12.0, 24.0);
          final pad = (width * 0.062).clamp(10.0, 20.0);
          final titleColor = dimmed
              ? AppColors.textMuted
              : onLightCover
              ? AppColors.brandNavyDeep
              : palette.title;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (asset == null)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _ScenePainter(scene: scene, palette: palette),
                  ),
                )
              else
                Image.asset(
                  asset!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              if (showTitle)
                Positioned(
                  left: pad,
                  top: pad * 0.85,
                  right: pad,
                  child: _CoverTitle(
                    title: title,
                    fontSize: fontSize,
                    color: titleColor,
                    // Çizgi başlığın rengini paylaşır. Oyunun kimlik rengi
                    // kullanılırken kapak görselinin paletiyle çakışıyordu:
                    // kırmızı kapakta camgöbeği, sarı kapakta mor çizgi.
                    // Tipografik alt çizgi olarak okunması daha doğru.
                    rule: dimmed ? AppColors.outline : titleColor,
                    // Açık kapakta siyah gölge metni kirletiyor; koyu
                    // başlık zaten zemininden yeterince ayrılıyor.
                    shadow: !onLightCover,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CoverTitle extends StatelessWidget {
  const _CoverTitle({
    required this.title,
    required this.fontSize,
    required this.color,
    required this.rule,
    this.shadow = true,
  });

  final String title;
  final double fontSize;
  final Color color;
  final Color rule;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          // `toUpperCase()` **yok**: Bungee zaten yalnız büyük harf çiziyor,
          // üstelik Dart'ın varsayılan büyütmesi Türkçe'de `i`'yi `I` yapıp
          // "HAT BIRLEŞTIR" üretiyor.
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.tileTitle.copyWith(
            fontSize: fontSize,
            height: 1.05,
            letterSpacing: 0,
            color: color,
            // Sahne başlığın altından geçebiliyor; ince bir gölge metni
            // koyu kapaklarda ayakta tutuyor.
            shadows: shadow
                ? <Shadow>[
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
        SizedBox(height: fontSize * 0.34),
        Container(
          width: fontSize * 2.4,
          height: (fontSize * 0.2).clamp(2.5, 4.0),
          decoration: BoxDecoration(
            color: rule,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({required this.scene, required this.palette});

  final GameCoverScene scene;
  final GameCoverPalette palette;

  Color get _accent => palette.accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _background(canvas, size);

    switch (scene) {
      case GameCoverScene.blocks:
        _blocks(canvas, size);
      case GameCoverScene.quiz:
        _quiz(canvas, size);
      case GameCoverScene.merge:
        _merge(canvas, size);
      case GameCoverScene.tunnel:
        _tunnel(canvas, size);
      case GameCoverScene.drop:
        _drop(canvas, size);
      case GameCoverScene.lanes:
        _lanes(canvas, size);
      case GameCoverScene.snake:
        _snake(canvas, size);
      case GameCoverScene.locked:
        _locked(canvas, size);
    }
  }

  // --- Ortak araçlar ---

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[palette.top, palette.bottom],
        ).createShader(rect),
    );
  }

  /// Kalın konturlu, üstü aydınlık "oyuncak" blok.
  ///
  /// Referans kapakların ortak dili: düz dolgu, üstte açık bir bant, altta
  /// koyu bir bant ve belirgin kontur. Gölge/degrade yığmadan hacim veriyor.
  void _chunky(
    Canvas canvas,
    Rect rect,
    double radius,
    Color color, {
    double outline = 0,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = color);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.30),
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - rect.height * 0.22,
        rect.width,
        rect.height * 0.22,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.restore();

    if (outline > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outline
          ..color = Colors.black.withValues(alpha: 0.28),
      );
    }
  }

  /// Kalın konturlu daire — aynı dilin yuvarlak hâli.
  void _chunkyCircle(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - radius,
        center.dy - radius,
        radius * 2,
        radius * 0.62,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.13
        ..color = Colors.black.withValues(alpha: 0.25),
    );
  }

  Paint _stroke(double width, Color tone, {double alpha = 1}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = tone.withValues(alpha: alpha);

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color tone,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: fontSize,
          color: tone,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// Uygulamanın gerçek trenini verilen dikdörtgene çizer.
  void _train(Canvas canvas, Rect rect, {int wagons = 2, double angle = 0}) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (angle != 0) canvas.rotate(angle);
    final painter = MetroTrainPainter(color: _accent, wagons: wagons);
    final height = rect.height;
    final width =
        height * MetroTrainPainter.defaultWagonAspect * wagons +
        height * MetroTrainPainter.couplingRatio * (wagons - 1);
    canvas.translate(-width / 2, -height / 2);
    painter.paint(canvas, Size(width, height));
    canvas.restore();
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final step = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = min(travelled + dash, total);
      canvas.drawLine(from + step * travelled, from + step * end, paint);
      travelled = end + gap;
    }
  }

  // --- Blok Metro ---
  //
  // Sahne: ızgaranın bir köşesi, yerleşmiş kalın bloklar ve **havada duran**
  // bir parça. Oyunun tamamı bu: parçayı al, yerleştir, satırı temizle.
  void _blocks(Canvas canvas, Size size) {
    final cell = size.width * 0.185;
    final gap = cell * 0.10;
    final originX = size.width * 0.13;
    final originY = size.height * 0.46;

    Rect cellAt(int c, int r) => Rect.fromLTWH(
      originX + c * cell,
      originY + r * cell,
      cell - gap,
      cell - gap,
    );

    // Boş ızgara zemini.
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 4; c++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellAt(c, r), Radius.circular(cell * 0.20)),
          Paint()..color = Colors.black.withValues(alpha: 0.26),
        );
      }
    }

    // Yerleşmiş bloklar.
    const placed = <Point<int>>[
      Point<int>(0, 1),
      Point<int>(0, 2),
      Point<int>(1, 2),
      Point<int>(2, 2),
    ];
    for (final p in placed) {
      _chunky(canvas, cellAt(p.x, p.y), cell * 0.20, _accent, outline: 1.6);
    }

    // Temizlenmek üzere olan satır: parlak ton.
    final bright = Color.lerp(_accent, Colors.white, 0.42)!;
    _chunky(canvas, cellAt(3, 2), cell * 0.20, bright, outline: 1.6);

    // Havadaki parça: hafif eğik, altında gölge — yerleşmeyi bekliyor.
    final piece = Rect.fromLTWH(
      originX + cell * 2.35,
      originY - cell * 0.62,
      cell - gap,
      cell - gap,
    );
    canvas.save();
    canvas.translate(piece.center.dx, piece.center.dy);
    canvas.rotate(-0.16);
    canvas.translate(-piece.center.dx, -piece.center.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        piece.translate(3, 7),
        Radius.circular(cell * 0.20),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    _chunky(canvas, piece, cell * 0.20, bright, outline: 1.8);
    canvas.restore();
  }

  // --- Metro Bilgi ---
  //
  // Sahne: eğik bir soru kartı ve altında dört şık, biri işaretli. Oyun
  // bugün böyle: dört şıktan birini seç. Durak ilerlemesi anlatılmıyor,
  // çünkü bugünkü oyunda öyle bir kural yok.
  void _quiz(Canvas canvas, Size size) {
    final card = Rect.fromCenter(
      center: Offset(size.width * 0.52, size.height * 0.50),
      width: size.width * 0.58,
      height: size.height * 0.30,
    );

    canvas.save();
    canvas.translate(card.center.dx, card.center.dy);
    canvas.rotate(-0.07);
    canvas.translate(-card.center.dx, -card.center.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        card.translate(4, 9),
        Radius.circular(size.width * 0.07),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    _chunky(canvas, card, size.width * 0.07, _accent, outline: 2);
    _label(
      canvas,
      '?',
      card.center,
      card.height * 0.70,
      LineTheme.readableOn(_accent),
    );
    canvas.restore();

    // Dört şık: alt alta iki sıra, sağdakilerden biri işaretli.
    final optionWidth = size.width * 0.30;
    final optionHeight = size.height * 0.085;
    final left = size.width * 0.16;
    final top = size.height * 0.72;
    final columnGap = size.width * 0.06;
    final rowGap = size.height * 0.045;

    for (var i = 0; i < 4; i++) {
      final rect = Rect.fromLTWH(
        left + (i % 2) * (optionWidth + columnGap),
        top + (i ~/ 2) * (optionHeight + rowGap),
        optionWidth,
        optionHeight,
      );
      final chosen = i == 2;
      _chunky(
        canvas,
        rect,
        optionHeight * 0.42,
        chosen
            ? Color.lerp(_accent, Colors.white, 0.45)!
            : Colors.white.withValues(alpha: 0.14),
        outline: chosen ? 1.6 : 0,
      );
    }
  }

  // --- Hat Birleştir ---
  //
  // Sahne: iki eş M1 karosu arkada, önlerinde bir boy büyük M2 karosu.
  // Kurallar birebir 2048 ama kimlik **tren karoları**; o yüzden sayı değil
  // tren ve hat kodu gösteriliyor.
  void _merge(Canvas canvas, Size size) {
    final small = size.width * 0.27;
    final smallY = size.height * 0.46;

    void tile(Offset center, double side, String code, Color color) {
      final rect = Rect.fromCenter(center: center, width: side, height: side);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.translate(3, 7),
          Radius.circular(side * 0.24),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.28),
      );
      _chunky(canvas, rect, side * 0.24, color, outline: 2);
      _train(
        canvas,
        Rect.fromCenter(
          center: center.translate(0, -side * 0.08),
          width: side * 0.68,
          height: side * 0.26,
        ),
        wagons: side > small ? 2 : 1,
      );
      _label(
        canvas,
        code,
        center.translate(0, side * 0.27),
        side * 0.21,
        LineTheme.readableOn(color),
      );
    }

    final dim = Color.lerp(_accent, palette.bottom, 0.42)!;
    tile(Offset(size.width * 0.28, smallY), small, 'M1', dim);
    tile(Offset(size.width * 0.60, smallY), small, 'M1', dim);

    // Birleşme oku.
    final arrowY = smallY + small * 0.72;
    final arrow = _stroke(3, Colors.white, alpha: 0.75);
    canvas.drawLine(
      Offset(size.width * 0.34, arrowY),
      Offset(size.width * 0.44, arrowY),
      arrow,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, arrowY),
      Offset(size.width * 0.52, arrowY),
      arrow,
    );

    // Sonuç: öne çıkan büyük karo.
    tile(
      Offset(size.width * 0.56, size.height * 0.80),
      size.width * 0.40,
      'M2',
      _accent,
    );
  }

  // --- Ray Uçuşu ---
  //
  // Sahne: iki tünel duvarı, aralarındaki açıklık ve ona doğru yükselen
  // tren. Kontrol dokunmayla yukarı vurmak; kesik yörünge onu anlatıyor.
  void _tunnel(Canvas canvas, Size size) {
    // Duvarlar kartın **içinde** duruyor: sağ kenara dayandığında kırpılmış
    // gibi okunuyor ve geçidin iki yakası olduğu anlaşılmıyordu.
    final wallLeft = size.width * 0.60;
    final wallWidth = size.width * 0.29;
    final gapCenter = size.height * 0.62;
    final gapHeight = size.height * 0.24;

    final wallColor = Color.lerp(_accent, Colors.black, 0.45)!;
    for (final rect in <Rect>[
      Rect.fromLTWH(
        wallLeft,
        size.height * 0.16,
        wallWidth,
        gapCenter - gapHeight / 2 - size.height * 0.16,
      ),
      Rect.fromLTWH(
        wallLeft,
        gapCenter + gapHeight / 2,
        wallWidth,
        size.height * 0.94 - (gapCenter + gapHeight / 2),
      ),
    ]) {
      _chunky(canvas, rect, wallWidth * 0.16, wallColor, outline: 2);
      // Duvarın açıklığa bakan ucunda parlak bir bant: geçit burası.
      final lip = rect.top < gapCenter
          ? Rect.fromLTWH(
              rect.left,
              rect.bottom - size.height * 0.022,
              rect.width,
              size.height * 0.022,
            )
          : Rect.fromLTWH(rect.left, rect.top, rect.width, size.height * 0.022);
      canvas.drawRect(lip, Paint()..color = _accent);
    }

    // Yörünge: aşağıdan açıklığa yükselen kesik yay.
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.90)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.86,
        size.width * 0.34,
        gapCenter + size.height * 0.02,
      );
    final metric = path.computeMetrics().first;
    var travelled = 0.0;
    final trail = _stroke(3, Colors.white, alpha: 0.5);
    while (travelled < metric.length) {
      final end = min(travelled + 9, metric.length);
      canvas.drawPath(metric.extractPath(travelled, end), trail);
      travelled = end + 7;
    }

    // Tren geçidin **ağzında**: burnu açıklığa girmiş durumda.
    _train(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.50, gapCenter - size.height * 0.005),
        width: size.width * 0.40,
        height: size.height * 0.145,
      ),
      angle: -0.26,
    );
  }

  // --- Hat Düşür ---
  //
  // Sahne: önde büyük bir M3 rozeti, arkasında küçükler, tepeden düşen yeni
  // rozet ve kesik tehlike çizgisi. Kaybetme koşulu görünür durumda.
  void _drop(Canvas canvas, Size size) {
    final dangerY = size.height * 0.40;
    _dashedLine(
      canvas,
      Offset(size.width * 0.10, dangerY),
      Offset(size.width * 0.90, dangerY),
      _stroke(3, AppColors.danger, alpha: 0.9),
    );

    // Düşmekte olan rozet ve iz.
    final fallingR = size.width * 0.085;
    final falling = Offset(size.width * 0.70, dangerY + fallingR * 1.5);
    final trail = _stroke(3, Colors.white, alpha: 0.35);
    for (final dx in <double>[-fallingR * 0.45, fallingR * 0.45]) {
      canvas.drawLine(
        Offset(falling.dx + dx, falling.dy - fallingR * 1.7),
        Offset(falling.dx + dx, falling.dy - fallingR * 2.9),
        trail,
      );
    }
    _chunkyCircle(canvas, falling, fallingR, _accent);

    // Yığın: arkada küçükler, önde büyük.
    final baseY = size.height * 0.92;
    final dim = Color.lerp(_accent, palette.bottom, 0.35)!;
    final mid = Color.lerp(_accent, Colors.white, 0.18)!;

    final smallR = size.width * 0.105;
    final smallC = Offset(size.width * 0.20, baseY - smallR);
    _chunkyCircle(canvas, smallC, smallR, dim);
    _label(canvas, 'M1', smallC, smallR * 0.58, LineTheme.readableOn(dim));

    final midR = size.width * 0.145;
    final midC = Offset(size.width * 0.78, baseY - midR);
    _chunkyCircle(canvas, midC, midR, mid);
    _label(canvas, 'M2', midC, midR * 0.55, LineTheme.readableOn(mid));

    final bigR = size.width * 0.215;
    final bigC = Offset(size.width * 0.48, baseY - bigR);
    _chunkyCircle(canvas, bigC, bigR, _accent);
    _label(canvas, 'M3', bigC, bigR * 0.52, LineTheme.readableOn(_accent));
  }

  // --- Ray Değiştir ---
  //
  // Sahne: üç ray, yan raylarda kapalı geçit, ortada tren ve yön oku. Oyun
  // tam olarak bu: üç şeritten birinde kal, kapalı olandan kaç.
  void _lanes(Canvas canvas, Size size) {
    const lanes = 3;
    final laneWidth = size.width * 0.22;
    final spacing = size.width * 0.07;
    final totalWidth = lanes * laneWidth + (lanes - 1) * spacing;
    final startX = (size.width - totalWidth) / 2;
    final top = size.height * 0.30;
    final bottom = size.height * 0.96;

    double laneCenter(int i) =>
        startX + i * (laneWidth + spacing) + laneWidth / 2;

    final railPaint = _stroke(3, Colors.white, alpha: 0.30);
    final sleeperPaint = _stroke(4, Colors.white, alpha: 0.16);
    for (var i = 0; i < lanes; i++) {
      final center = laneCenter(i);
      for (final dx in <double>[-laneWidth * 0.30, laneWidth * 0.30]) {
        canvas.drawLine(
          Offset(center + dx, top),
          Offset(center + dx, bottom),
          railPaint,
        );
      }
      for (var y = top + 12; y < bottom; y += (bottom - top) / 6) {
        canvas.drawLine(
          Offset(center - laneWidth * 0.36, y),
          Offset(center + laneWidth * 0.36, y),
          sleeperPaint,
        );
      }
    }

    // Kapalı raylar.
    for (final index in <int>[0, 2]) {
      final barrier = Rect.fromCenter(
        center: Offset(laneCenter(index), size.height * 0.46),
        width: laneWidth * 1.06,
        height: size.height * 0.11,
      );
      _chunky(
        canvas,
        barrier,
        barrier.height * 0.30,
        AppColors.blocker,
        outline: 2,
      );
      final stripe = _stroke(3.2, AppColors.danger);
      canvas.drawLine(
        barrier.topLeft.translate(barrier.width * 0.20, barrier.height * 0.30),
        barrier.bottomRight.translate(
          -barrier.width * 0.20,
          -barrier.height * 0.30,
        ),
        stripe,
      );
    }

    // Tren ortada, altında şerit değiştirme oku.
    _train(
      canvas,
      Rect.fromCenter(
        center: Offset(laneCenter(1), size.height * 0.72),
        width: laneWidth * 1.15,
        height: size.height * 0.17,
      ),
      angle: -pi / 2,
    );

    final arrowY = size.height * 0.90;
    final arrowPaint = _stroke(3.4, Colors.white, alpha: 0.85);
    final tip = Offset(laneCenter(2), arrowY);
    canvas.drawLine(
      Offset(laneCenter(1) + laneWidth * 0.1, arrowY),
      tip,
      arrowPaint,
    );
    canvas.drawLine(tip.translate(-9, -7), tip, arrowPaint);
    canvas.drawLine(tip.translate(-9, 7), tip, arrowPaint);
  }

  // --- Yolcu Topla ---
  //
  // Sahne: ızgara, kalın kıvrılmış tren gövdesi ve önünde bekleyen yolcu.
  // Gövdenin uzunluğu oyunun büyüme mekaniğini anlatıyor.
  void _snake(Canvas canvas, Size size) {
    const columns = 5;
    const rows = 4;
    final cell = min(size.width * 0.175, size.height * 0.15);
    final originX = (size.width - cell * columns) / 2;
    final originY = size.height * 0.42;

    Offset cellCenter(int c, int r) =>
        Offset(originX + c * cell + cell / 2, originY + r * cell + cell / 2);

    final dot = Paint()..color = Colors.white.withValues(alpha: 0.16);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        canvas.drawCircle(cellCenter(c, r), cell * 0.075, dot);
      }
    }

    const body = <Point<int>>[
      Point<int>(0, 3),
      Point<int>(0, 2),
      Point<int>(1, 2),
      Point<int>(2, 2),
      Point<int>(2, 1),
      Point<int>(3, 1),
    ];
    final path = Path();
    for (var i = 0; i < body.length; i++) {
      final center = cellCenter(body[i].x, body[i].y);
      if (i == 0) {
        path.moveTo(center.dx, center.dy);
      } else {
        path.lineTo(center.dx, center.dy);
      }
    }

    // Kontur + gövde: kalın çift geçiş, referans kapakların kalın konturlu
    // dili.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.72
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.58
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _accent,
    );

    // Vagon bağlantıları.
    for (var i = 1; i < body.length; i++) {
      final a = cellCenter(body[i - 1].x, body[i - 1].y);
      final b = cellCenter(body[i].x, body[i].y);
      canvas.drawCircle(
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2),
        cell * 0.09,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    // Lokomotif penceresi.
    canvas.drawCircle(
      cellCenter(body.last.x, body.last.y),
      cell * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    // Yolcu: baş ve omuz silueti.
    final passenger = cellCenter(4, 3);
    final discR = cell * 0.36;
    _chunkyCircle(canvas, passenger, discR, Colors.white);
    final figure = Paint()..color = palette.bottom;
    canvas.drawCircle(
      passenger.translate(0, -discR * 0.32),
      discR * 0.27,
      figure,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: passenger.translate(0, discR * 0.56),
        width: discR * 1.10,
        height: discR * 1.12,
      ),
      pi,
      pi,
      true,
      figure,
    );
  }

  // --- Kilitli oyun ---
  //
  // Asma kilit değil **kapalı istasyon**: raylar devam ediyor ama önlerinde
  // şeritli bir inşaat bariyeri var, üstünde YAKINDA tabelası. Stok kilit
  // simgesi kartı bir hata ekranı gibi gösteriyordu; kapalı peron oyunun
  // kendi dünyasından ve "henüz açılmadı" demenin metroya ait yolu.
  void _locked(Canvas canvas, Size size) {
    final rail = _stroke(3, Colors.white, alpha: 0.16);
    final sleeper = _stroke(4, Colors.white, alpha: 0.09);
    final centerX = size.width / 2;
    final laneWidth = size.width * 0.34;

    for (final dx in <double>[-laneWidth / 2, laneWidth / 2]) {
      canvas.drawLine(
        Offset(centerX + dx, size.height * 0.40),
        Offset(centerX + dx, size.height * 0.98),
        rail,
      );
    }
    for (var y = size.height * 0.46; y < size.height * 0.98; y += 34) {
      canvas.drawLine(
        Offset(centerX - laneWidth * 0.62, y),
        Offset(centerX + laneWidth * 0.62, y),
        sleeper,
      );
    }

    // Bariyer: köşegen uyarı şeritleri, kartın enine yakın.
    final barrier = Rect.fromCenter(
      center: Offset(centerX, size.height * 0.56),
      width: size.width * 0.74,
      height: size.height * 0.085,
    );
    final rr = RRect.fromRectAndRadius(
      barrier,
      Radius.circular(barrier.height * 0.28),
    );
    canvas.drawRRect(rr, Paint()..color = AppColors.gameGlyphBox);
    canvas.save();
    canvas.clipRRect(rr);
    final stripe = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.55)
      ..strokeWidth = barrier.height * 0.34
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    for (
      var x = barrier.left - barrier.height;
      x < barrier.right + barrier.height * 2;
      x += barrier.height * 0.72
    ) {
      canvas.drawLine(
        Offset(x, barrier.bottom + 2),
        Offset(x + barrier.height, barrier.top - 2),
        stripe,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.30),
    );

    // Bariyerin iki ayağı.
    final legPaint = Paint()..color = AppColors.gameGlyphBox;
    for (final dx in <double>[-barrier.width * 0.36, barrier.width * 0.36]) {
      canvas.drawRect(
        Rect.fromLTWH(
          centerX + dx - 4,
          barrier.bottom - 2,
          8,
          size.height * 0.10,
        ),
        legPaint,
      );
    }

    // Tabela: kısa direk ve üstünde YAKINDA.
    final sign = Rect.fromCenter(
      center: Offset(centerX, size.height * 0.36),
      width: size.width * 0.52,
      height: size.height * 0.075,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX - 3, sign.bottom, 6, size.height * 0.055),
      legPaint,
    );
    final signRR = RRect.fromRectAndRadius(
      sign,
      Radius.circular(sign.height * 0.26),
    );
    canvas.drawRRect(signRR, legPaint);
    canvas.drawRRect(
      signRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.textMuted.withValues(alpha: 0.45),
    );
    _label(
      canvas,
      'YAKINDA',
      sign.center,
      sign.height * 0.46,
      AppColors.textMuted,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.palette.accent != palette.accent;
}
