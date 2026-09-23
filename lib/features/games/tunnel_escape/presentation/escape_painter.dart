import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/escape_board.dart';
import '../domain/escape_piece.dart';

/// Tünele Kaç'ın renkleri — yalnız bu oyunun tahtasında.
///
/// Uygulamanın koyu, soğuk nötrlerinden türüyor (tahta [AppColors]
/// yüzeyleriyle aynı aileden); metrolar ise sıcak bir kırık beyaz. Kırmızı
/// metro tek doygun kırmızı: ekranda "senin metron" başka hiçbir şeyle
/// karışmasın.
abstract final class EscapePalette {
  static const Color boardFill = Color(0xFF181B20);
  static const Color boardEdge = Color(0xFF3A3F48);
  static const Color cell = Color(0xFF1F2329);
  static const Color exitLane = Color(0xFF232026);

  static const Color body = Color(0xFFECE7DE);
  static const Color roof = Color(0xFFF8F5EF);
  static const Color bodyEdge = Color(0xFFC4BCAF);
  static const Color window = Color(0xFF2A2E36);
  static const Color light = Color(0xFFFFF1C2);

  static const Color target = Color(0xFFE5392F);
  static const Color targetRoof = Color(0xFFF1564B);
  static const Color targetEdge = Color(0xFFA9241C);
  static const Color targetWindow = Color(0xFF2B1416);
  static const Color targetStripe = Color(0xFFFFE9E3);

  static const Color tunnelRing = Color(0xFF4B515C);
  static const Color tunnelRingLight = Color(0xFF626976);
  static const Color tunnelMouth = Color(0xFF050607);
  static const Color signal = Color(0xFFF5C518);
}

/// Izgara uzayından ekran uzayına çeviri.
///
/// Tahtanın bütün çizimi ve dokunuş okuması bu tek sınıftan geçiyor:
/// alan katmanı yalnız hücre bilir, piksel bilmez.
@immutable
class EscapeGeometry {
  const EscapeGeometry({
    required this.origin,
    required this.cell,
    required this.columns,
    required this.rows,
  });

  /// Verilen alana sığan en büyük tahta.
  ///
  /// Sağda tünel için yarım hücrelik pay bırakılıyor: tünel tahtanın
  /// dışına taşan tek öge ve kırpılmamalı.
  factory EscapeGeometry.fit(Size size, int columns, int rows) {
    final pad = frameFactor * 2;
    final cellByWidth = size.width / (columns + pad + tunnelFactor);
    final cellByHeight = size.height / (rows + pad);
    final cell = math.min(cellByWidth, cellByHeight);
    final boardWidth = (columns + pad) * cell;
    final boardHeight = (rows + pad) * cell;
    final totalWidth = boardWidth + tunnelFactor * cell;
    final left = (size.width - totalWidth) / 2 + frameFactor * cell;
    final top = (size.height - boardHeight) / 2 + frameFactor * cell;
    return EscapeGeometry(
      origin: Offset(left, top),
      cell: cell,
      columns: columns,
      rows: rows,
    );
  }

  /// Çerçeve kalınlığı, hücre cinsinden.
  static const double frameFactor = 0.22;

  /// Tünelin tahtadan dışarı taşan kısmı, hücre cinsinden.
  static const double tunnelFactor = 0.62;

  final Offset origin;
  final double cell;
  final int columns;
  final int rows;

  Rect get grid =>
      Rect.fromLTWH(origin.dx, origin.dy, columns * cell, rows * cell);

  Rect get frame => grid.inflate(frameFactor * cell);

  /// Metronun ekrandaki dikdörtgeni; [position] kesirli olabilir.
  Rect pieceRect(EscapePiece piece, double position) {
    final inset = cell * 0.07;
    final col = piece.isHorizontal ? position : piece.lane.toDouble();
    final row = piece.isHorizontal ? piece.lane.toDouble() : position;
    final w = (piece.isHorizontal ? piece.length : 1) * cell;
    final h = (piece.isHorizontal ? 1 : piece.length) * cell;
    return Rect.fromLTWH(
      origin.dx + col * cell + inset,
      origin.dy + row * cell + inset,
      w - inset * 2,
      h - inset * 2,
    );
  }

  /// Ekrandaki noktanın hücresi (tahta dışındaysa sınırda kırpılmaz).
  (int, int) cellAt(Offset point) => (
    ((point.dy - origin.dy) / cell).floor(),
    ((point.dx - origin.dx) / cell).floor(),
  );

  /// Tünel ağzının dikdörtgeni: hedef satırında, tahtanın sağ kenarında.
  Rect tunnelMouth(int exitRow) {
    final top = origin.dy + exitRow * cell;
    return Rect.fromLTWH(
      grid.right,
      top + cell * 0.08,
      frameFactor * cell + tunnelFactor * cell * 0.72,
      cell * 0.84,
    );
  }
}

/// Tahtayı, metroları ve tüneli çizer.
///
/// Tek geçişte: yüzlerce widget yerine bir boyacı. Konumlar kesirli
/// gelebilir (sürükleme, oturma, geri alma animasyonu); boyacı yalnız ne
/// verilirse onu çizer, hiçbir kural bilmez.
class EscapeBoardPainter extends CustomPainter {
  EscapeBoardPainter({
    required this.layout,
    required this.positions,
    required this.geometry,
    this.lifted,
    this.hintPiece,
    this.hintTo,
    this.hintPulse = 0,
    this.exitProgress = 0,
    this.axisCuePiece,
    this.axisCues = const (false, false),
  });

  final EscapeLayout layout;

  /// Ekranda görünen konumlar (kesirli olabilir), metro sırasıyla.
  final List<double> positions;
  final EscapeGeometry geometry;

  /// Parmağın altındaki metro: hafifçe kalkar.
  final int? lifted;

  /// İpucunun gösterdiği metro ve gideceği konum.
  final int? hintPiece;
  final int? hintTo;
  final double hintPulse;

  /// Kırmızı metronun tünele girişi, 0 → 1.
  final double exitProgress;

  /// Sürüklenen metronun gidebileceği yönleri gösteren küçük oklar:
  /// `(geri, ileri)` — geri sol/yukarı, ileri sağ/aşağı.
  final int? axisCuePiece;
  final (bool, bool) axisCues;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    _paintFrame(canvas, g);
    _paintCells(canvas, g);
    _paintExitLane(canvas, g);
    _paintTunnelBack(canvas, g);

    if (hintPiece != null && hintTo != null) {
      _paintHintGhost(canvas, g, hintPiece!, hintTo!);
    }

    // Kalkan metro en üstte çizilir: gölgesi komşularının üstüne düşer.
    for (var i = 0; i < layout.pieceCount; i++) {
      if (i == lifted || i == layout.targetIndex) continue;
      _paintPiece(canvas, g, i, positions[i], lifted: false);
    }
    if (lifted != layout.targetIndex) {
      _paintTarget(canvas, g);
    }
    if (lifted != null) {
      if (lifted == layout.targetIndex) {
        _paintTarget(canvas, g, lifted: true);
      } else {
        _paintPiece(canvas, g, lifted!, positions[lifted!], lifted: true);
      }
    }

    _paintTunnelFront(canvas, g);

    if (hintPiece != null) _paintHintRing(canvas, g, hintPiece!);
    if (axisCuePiece != null) _paintAxisCues(canvas, g, axisCuePiece!);
  }

  // --- Tahta ---

  void _paintFrame(Canvas canvas, EscapeGeometry g) {
    final frame = RRect.fromRectAndRadius(
      g.frame,
      Radius.circular(g.cell * 0.34),
    );
    canvas.drawRRect(
      frame.shift(Offset(0, g.cell * 0.06)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.cell * 0.12),
    );
    canvas.drawRRect(frame, Paint()..color = EscapePalette.boardFill);
    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = EscapePalette.boardEdge,
    );
  }

  void _paintCells(Canvas canvas, EscapeGeometry g) {
    final paint = Paint()..color = EscapePalette.cell;
    final inset = g.cell * 0.05;
    final radius = Radius.circular(g.cell * 0.16);
    for (var row = 0; row < g.rows; row++) {
      for (var col = 0; col < g.columns; col++) {
        final rect = Rect.fromLTWH(
          g.origin.dx + col * g.cell + inset,
          g.origin.dy + row * g.cell + inset,
          g.cell - inset * 2,
          g.cell - inset * 2,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
    }
  }

  /// Hedef satırı: tünele giden yol, çok hafif sıcak bir şerit ve tünelin
  /// hemen önünde üç küçük ok.
  void _paintExitLane(Canvas canvas, EscapeGeometry g) {
    final row = layout.exitRow;
    final lane = Rect.fromLTWH(
      g.grid.left,
      g.origin.dy + row * g.cell + g.cell * 0.18,
      g.grid.width,
      g.cell * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lane, Radius.circular(g.cell * 0.2)),
      Paint()
        ..shader =
            ui.Gradient.linear(lane.centerLeft, lane.centerRight, <Color>[
              EscapePalette.signal.withValues(alpha: 0),
              EscapePalette.signal.withValues(alpha: 0.07),
            ]),
    );

    final y = g.origin.dy + (row + 0.5) * g.cell;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, g.cell * 0.05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final h = g.cell * 0.11;
    for (var i = 0; i < 3; i++) {
      final x = g.grid.right - g.cell * (0.62 - i * 0.17);
      paint.color = EscapePalette.signal.withValues(alpha: 0.28 + i * 0.16);
      canvas.drawPath(
        Path()
          ..moveTo(x - h * 0.7, y - h)
          ..lineTo(x, y)
          ..lineTo(x - h * 0.7, y + h),
        paint,
      );
    }

    // Peron kenarı: sağ kenar boyunca ince sarı çizgi, tünel ağzında kesik.
    final edge = Paint()
      ..color = EscapePalette.signal.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1.5, g.cell * 0.035)
      ..strokeCap = StrokeCap.round;
    final x = g.grid.right + g.frameInset * 0.5;
    final mouth = g.tunnelMouth(row);
    canvas.drawLine(
      Offset(x, g.grid.top + g.cell * 0.12),
      Offset(x, mouth.top - g.cell * 0.06),
      edge,
    );
    canvas.drawLine(
      Offset(x, mouth.bottom + g.cell * 0.06),
      Offset(x, g.grid.bottom - g.cell * 0.12),
      edge,
    );
  }

  /// Tünelin karanlık içi — metro buraya girer.
  void _paintTunnelBack(Canvas canvas, EscapeGeometry g) {
    final mouth = g.tunnelMouth(layout.exitRow);
    final inner = RRect.fromRectAndCorners(
      mouth,
      topRight: Radius.circular(mouth.height * 0.5),
      bottomRight: Radius.circular(mouth.height * 0.5),
    );
    canvas.drawRRect(inner, Paint()..color = EscapePalette.tunnelMouth);
  }

  /// Tünelin ağzı: dışa taşan kemer ve içe doğru koyulaşan karanlık.
  ///
  /// Metrolardan **sonra** çizilir: tünele giren kırmızı metro karanlığın
  /// altında kalır, gerçekten içeri girmiş gibi görünür.
  void _paintTunnelFront(Canvas canvas, EscapeGeometry g) {
    final mouth = g.tunnelMouth(layout.exitRow);

    // İçe doğru karanlık: ağızda şeffaf, derinde tam siyah.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        mouth,
        topRight: Radius.circular(mouth.height * 0.5),
        bottomRight: Radius.circular(mouth.height * 0.5),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(mouth.left, mouth.center.dy),
          Offset(mouth.right, mouth.center.dy),
          <Color>[
            EscapePalette.tunnelMouth.withValues(alpha: 0),
            EscapePalette.tunnelMouth.withValues(alpha: 0.9),
            EscapePalette.tunnelMouth,
          ],
          <double>[0, 0.45, 1],
        ),
    );

    // Kemer: ağzı üstten, sağdan ve alttan saran kalın bir halka.
    final ring = g.cell * 0.13;
    final outer = mouth.inflate(ring);
    final arch = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(outer.left, outer.top, outer.right, outer.bottom),
          topLeft: Radius.circular(ring * 0.6),
          bottomLeft: Radius.circular(ring * 0.6),
          topRight: Radius.circular(outer.height * 0.5),
          bottomRight: Radius.circular(outer.height * 0.5),
        ),
      )
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            mouth.left - ring * 1.2,
            mouth.top,
            mouth.right,
            mouth.bottom,
          ),
          topRight: Radius.circular(mouth.height * 0.5),
          bottomRight: Radius.circular(mouth.height * 0.5),
        ),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      arch,
      Paint()
        ..shader = ui.Gradient.linear(
          outer.topCenter,
          outer.bottomCenter,
          <Color>[EscapePalette.tunnelRingLight, EscapePalette.tunnelRing],
        ),
    );
    // Kemer taşları: halkada üç ince derz.
    final joint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = math.max(1, g.cell * 0.02);
    final c = Offset(mouth.right - mouth.height * 0.5, mouth.center.dy);
    for (final angle in <double>[-0.9, 0, 0.9]) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        c + dir * (mouth.height * 0.5),
        c + dir * (mouth.height * 0.5 + ring),
        joint,
      );
    }
  }

  // --- Metrolar ---

  void _paintPiece(
    Canvas canvas,
    EscapeGeometry g,
    int index,
    double position, {
    required bool lifted,
  }) {
    final piece = layout.pieces[index];
    var rect = g.pieceRect(piece, position);
    if (lifted) rect = _scaled(rect, 1.035);
    _paintBody(
      canvas,
      g,
      rect,
      horizontal: piece.isHorizontal,
      length: piece.length,
      lifted: lifted,
      body: EscapePalette.body,
      roof: EscapePalette.roof,
      edge: EscapePalette.bodyEdge,
      window: EscapePalette.window,
    );
  }

  void _paintTarget(Canvas canvas, EscapeGeometry g, {bool lifted = false}) {
    final index = layout.targetIndex;
    final piece = layout.pieces[index];
    // Tünele giriş hızlanarak: önce ağır, sonra karanlığa dalar.
    final travel =
        Curves.easeInCubic.transform(exitProgress.clamp(0, 1)) *
        (piece.length +
            EscapeGeometry.frameFactor +
            EscapeGeometry.tunnelFactor +
            0.4);
    var rect = g.pieceRect(piece, positions[index] + travel);
    if (lifted) rect = _scaled(rect, 1.035);

    canvas.save();
    if (exitProgress > 0) {
      // Tünelin dibinden öteye çizilmez.
      final mouth = g.tunnelMouth(layout.exitRow);
      canvas.clipRect(
        Rect.fromLTRB(g.frame.left, g.frame.top, mouth.right, g.frame.bottom),
      );
    }
    _paintBody(
      canvas,
      g,
      rect,
      horizontal: true,
      length: piece.length,
      lifted: lifted,
      body: EscapePalette.target,
      roof: EscapePalette.targetRoof,
      edge: EscapePalette.targetEdge,
      window: EscapePalette.targetWindow,
      isTarget: true,
    );
    canvas.restore();
  }

  /// Üstten görünen bir metro gövdesi.
  ///
  /// Dilbilgisi her metroda aynı: gölge, gövde, açık renk tavan, koyu
  /// pencereler, iki uçta farlar. Kırmızı metroyu ayıran renk **tek başına
  /// değil**: iki vagonu ayıran körük, tünele bakan sivri burun ve
  /// tavanındaki açık şerit yalnız onda var — renk körü oyuncu da hedefi
  /// biçiminden tanır.
  void _paintBody(
    Canvas canvas,
    EscapeGeometry g,
    Rect rect, {
    required bool horizontal,
    required int length,
    required bool lifted,
    required Color body,
    required Color roof,
    required Color edge,
    required Color window,
    bool isTarget = false,
  }) {
    final c = g.cell;
    final radius = Radius.circular(c * 0.26);
    final shape = isTarget
        ? RRect.fromRectAndCorners(
            rect,
            topLeft: radius,
            bottomLeft: radius,
            topRight: Radius.circular(c * 0.42),
            bottomRight: Radius.circular(c * 0.42),
          )
        : RRect.fromRectAndRadius(rect, radius);

    // Gölge: kalkan metroda daha uzak ve yumuşak.
    canvas.drawRRect(
      shape.shift(Offset(0, c * (lifted ? 0.12 : 0.05))),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.45 : 0.38)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          c * (lifted ? 0.16 : 0.06),
        ),
    );

    canvas.drawRRect(shape, Paint()..color = edge);
    final top = shape.deflate(c * 0.045).shift(Offset(0, -c * 0.02));
    canvas.drawRRect(top, Paint()..color = body);
    final roofRect = top.deflate(c * 0.08);
    canvas.drawRRect(roofRect, Paint()..color = roof);

    // Pencereler: hücre başına bir pencere, gövde boyunca.
    final windowPaint = Paint()..color = window;
    final along = horizontal ? rect.width : rect.height;
    final across = horizontal ? rect.height : rect.width;
    final unit = along / length;
    final winAlong = unit * (isTarget ? 0.42 : 0.46);
    final winAcross = across * 0.44;
    for (var i = 0; i < length; i++) {
      final centerAlong = unit * (i + 0.5);
      final center = horizontal
          ? Offset(rect.left + centerAlong, rect.center.dy - c * 0.02)
          : Offset(rect.center.dx, rect.top + centerAlong - c * 0.02);
      final w = horizontal ? winAlong : winAcross;
      final h = horizontal ? winAcross : winAlong;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: h),
          Radius.circular(c * 0.08),
        ),
        windowPaint,
      );
    }

    if (isTarget) {
      // Körük: iki vagonu ayıran ince koyu çizgi.
      final mid = rect.left + rect.width / 2;
      canvas.drawLine(
        Offset(mid, rect.top + c * 0.06),
        Offset(mid, rect.bottom - c * 0.06),
        Paint()
          ..color = edge
          ..strokeWidth = math.max(1.5, c * 0.045),
      );
      // Tavan şeridi: vagon boyunca açık renk ince bant.
      final stripe = Paint()
        ..color = EscapePalette.targetStripe.withValues(alpha: 0.85)
        ..strokeWidth = math.max(1.2, c * 0.035)
        ..strokeCap = StrokeCap.round;
      final y = rect.top + rect.height * 0.2;
      canvas.drawLine(
        Offset(rect.left + c * 0.22, y),
        Offset(rect.right - c * 0.3, y),
        stripe,
      );
      // Burun ok işareti: tünele bakan uçta küçük beyaz ok.
      final nose = Offset(rect.right - c * 0.16, rect.center.dy - c * 0.02);
      final s = c * 0.08;
      canvas.drawPath(
        Path()
          ..moveTo(nose.dx - s, nose.dy - s * 1.2)
          ..lineTo(nose.dx + s * 0.4, nose.dy)
          ..lineTo(nose.dx - s, nose.dy + s * 1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, c * 0.04)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = EscapePalette.targetStripe,
      );
    }

    // Farlar: iki uçta ikişer küçük ışık.
    final lightPaint = Paint()..color = EscapePalette.light;
    final r = c * 0.035;
    final offsetAcross = across * 0.26;
    for (final end in <double>[0.09, 0.91]) {
      if (isTarget && end > 0.5) continue; // burunda ok var
      for (final side in <double>[-1, 1]) {
        final p = horizontal
            ? Offset(
                rect.left + rect.width * end,
                rect.center.dy + side * offsetAcross,
              )
            : Offset(
                rect.center.dx + side * offsetAcross,
                rect.top + rect.height * end,
              );
        canvas.drawCircle(p, r, lightPaint);
      }
    }
  }

  Rect _scaled(Rect rect, double factor) => Rect.fromCenter(
    center: rect.center,
    width: rect.width * factor,
    height: rect.height * factor,
  );

  // --- İpucu ve yön işaretleri ---

  /// İpucunun hedef konumu: metronun gideceği yerde soluk bir iz.
  void _paintHintGhost(Canvas canvas, EscapeGeometry g, int index, int to) {
    final piece = layout.pieces[index];
    final rect = g.pieceRect(piece, to.toDouble());
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(g.cell * 0.26));
    canvas.drawRRect(
      shape,
      Paint()..color = EscapePalette.signal.withValues(alpha: 0.10),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, g.cell * 0.035)
        ..color = EscapePalette.signal.withValues(alpha: 0.55),
    );

    // Metrodan hedefe doğru ok.
    final from = g.pieceRect(piece, positions[index]).center;
    final dest = rect.center;
    final delta = dest - from;
    if (delta.distance < g.cell * 0.4) return;
    final dir = delta / delta.distance;
    final tip = dest - dir * (g.cell * 0.18);
    final base = from + dir * (g.cell * 0.55);
    if ((tip - base).distance < g.cell * 0.2) return;
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, g.cell * 0.06)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = EscapePalette.signal.withValues(alpha: 0.9);
    canvas.drawLine(base, tip, arrow);
    final normal = Offset(-dir.dy, dir.dx);
    final head = g.cell * 0.14;
    canvas.drawPath(
      Path()
        ..moveTo(
          tip.dx - dir.dx * head + normal.dx * head,
          tip.dy - dir.dy * head + normal.dy * head,
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - dir.dx * head - normal.dx * head,
          tip.dy - dir.dy * head - normal.dy * head,
        ),
      arrow,
    );
  }

  /// İpucunun metrosu: nabız gibi atan sarı halka.
  void _paintHintRing(Canvas canvas, EscapeGeometry g, int index) {
    final piece = layout.pieces[index];
    final rect = g
        .pieceRect(piece, positions[index])
        .inflate(g.cell * (0.04 + 0.05 * hintPulse));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(g.cell * 0.3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, g.cell * 0.055)
        ..color = EscapePalette.signal.withValues(
          alpha: 0.95 - 0.5 * hintPulse,
        ),
    );
  }

  /// Sürüklenen metronun uçlarında, gidebildiği yönde küçük oklar.
  void _paintAxisCues(Canvas canvas, EscapeGeometry g, int index) {
    final piece = layout.pieces[index];
    final rect = _scaled(g.pieceRect(piece, positions[index]), 1.035);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, g.cell * 0.045)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.75);
    final s = g.cell * 0.09;
    final gap = g.cell * 0.2;
    void chevron(Offset tip, Offset dir) {
      final normal = Offset(-dir.dy, dir.dx);
      canvas.drawPath(
        Path()
          ..moveTo(
            tip.dx - dir.dx * s + normal.dx * s,
            tip.dy - dir.dy * s + normal.dy * s,
          )
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - dir.dx * s - normal.dx * s,
            tip.dy - dir.dy * s - normal.dy * s,
          ),
        paint,
      );
    }

    final (back, forward) = axisCues;
    final horizontal = piece.isHorizontal;
    if (back) {
      chevron(
        horizontal
            ? Offset(rect.left - gap, rect.center.dy)
            : Offset(rect.center.dx, rect.top - gap),
        horizontal ? const Offset(-1, 0) : const Offset(0, -1),
      );
    }
    if (forward) {
      chevron(
        horizontal
            ? Offset(rect.right + gap, rect.center.dy)
            : Offset(rect.center.dx, rect.bottom + gap),
        horizontal ? const Offset(1, 0) : const Offset(0, 1),
      );
    }
  }

  @override
  bool shouldRepaint(EscapeBoardPainter old) => true;
}

extension on EscapeGeometry {
  double get frameInset => EscapeGeometry.frameFactor * cell;
}
