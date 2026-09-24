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

  static const Color body = Color(0xFFECE7DE);
  static const Color roof = Color(0xFFF8F5EF);
  static const Color bodyEdge = Color(0xFFC4BCAF);
  static const Color window = Color(0xFF2A2E36);

  static const Color target = Color(0xFFE5392F);
  static const Color targetRoof = Color(0xFFF1564B);
  static const Color targetEdge = Color(0xFFA9241C);
  static const Color targetWindow = Color(0xFF2B1416);
  static const Color targetStripe = Color(0xFFFFE9E3);

  static const Color tunnelRing = Color(0xFF4B515C);
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
  /// Sağda tünel için küçük bir pay bırakılıyor: tünel tahtanın dışına
  /// taşan tek öge ve kırpılmamalı. Pay bilerek dar — tahta ekranın
  /// kahramanı, genişlik ona gitsin.
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
  static const double frameFactor = 0.16;

  /// Tünelin çerçeveden dışarı taşan kısmı, hücre cinsinden.
  static const double tunnelFactor = 0.3;

  /// Tünel kemerinin kalınlığı, hücre cinsinden.
  static const double archFactor = 0.09;

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

  /// Tünel ağzının karanlık içi: hedef satırında, ızgaranın sağ kenarından
  /// kemerin iç yüzüne kadar. Metro buraya girer.
  Rect tunnelMouth(int exitRow) {
    final top = origin.dy + exitRow * cell;
    final arch = archFactor * cell;
    return Rect.fromLTRB(
      grid.right,
      top + cell * 0.1,
      frame.right + tunnelFactor * cell - arch,
      top + cell * 0.9,
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
      Radius.circular(g.cell * 0.3),
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

  /// Izgara: tek parça zemin ve ince derzler — depo zeminindeki karolar.
  ///
  /// Otuz altı ayrı yuvarlak kutu yerine tek yüzey: hücreler yine sayılır
  /// ama tahta metroların önüne geçmez.
  void _paintCells(Canvas canvas, EscapeGeometry g) {
    final grid = g.grid;
    canvas.drawRRect(
      RRect.fromRectAndRadius(grid, Radius.circular(g.cell * 0.14)),
      Paint()..color = EscapePalette.cell,
    );
    final joint = Paint()
      ..color = EscapePalette.boardFill
      ..strokeWidth = math.max(1.5, g.cell * 0.035);
    for (var i = 1; i < g.columns; i++) {
      final x = grid.left + i * g.cell;
      canvas.drawLine(Offset(x, grid.top), Offset(x, grid.bottom), joint);
    }
    for (var i = 1; i < g.rows; i++) {
      final y = grid.top + i * g.cell;
      canvas.drawLine(Offset(grid.left, y), Offset(grid.right, y), joint);
    }
  }

  /// Hedef satırı: tünelin hemen önünde üç küçük ok — çıkışın yönü.
  ///
  /// Başka süs yok: yolun kendisini metrolar ve tünel zaten anlatıyor.
  void _paintExitLane(Canvas canvas, EscapeGeometry g) {
    final row = layout.exitRow;
    final y = g.origin.dy + (row + 0.5) * g.cell;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, g.cell * 0.05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final h = g.cell * 0.11;
    for (var i = 0; i < 3; i++) {
      final x = g.grid.right - g.cell * (0.62 - i * 0.17);
      paint.color = EscapePalette.signal.withValues(alpha: 0.22 + i * 0.14);
      canvas.drawPath(
        Path()
          ..moveTo(x - h * 0.7, y - h)
          ..lineTo(x, y)
          ..lineTo(x - h * 0.7, y + h),
        paint,
      );
    }
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

  /// Tünelin ağzı: içe doğru koyulaşan karanlık ve tek renk kemer.
  ///
  /// Metrolardan **sonra** çizilir: tünele giren kırmızı metro karanlığın
  /// altında kalır, gerçekten içeri girmiş gibi görünür. Metro kaybolurken
  /// kemer bir an sinyal sarısına döner — bölümün bittiği an.
  void _paintTunnelFront(Canvas canvas, EscapeGeometry g) {
    final mouth = g.tunnelMouth(layout.exitRow);
    final round = Radius.circular(mouth.height * 0.5);

    // İçe doğru karanlık: ağızda şeffaf, derinde tam siyah.
    canvas.drawRRect(
      RRect.fromRectAndCorners(mouth, topRight: round, bottomRight: round),
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

    // Kemer: ağzı üstten, sağdan ve alttan saran düz bir halka.
    final ring = EscapeGeometry.archFactor * g.cell;
    final outer = Rect.fromLTRB(
      g.frame.right - ring,
      mouth.top - ring,
      mouth.right + ring,
      mouth.bottom + ring,
    );
    final arch = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          outer,
          topRight: Radius.circular(outer.height * 0.5),
          bottomRight: Radius.circular(outer.height * 0.5),
        ),
      )
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(outer.left - 1, mouth.top, mouth.right, mouth.bottom),
          topRight: round,
          bottomRight: round,
        ),
      )
      ..fillType = PathFillType.evenOdd;
    final glow = exitProgress <= 0.55
        ? 0.0
        : math.sin(math.pi * ((exitProgress - 0.55) / 0.45).clamp(0.0, 1.0));
    canvas.drawPath(
      arch,
      Paint()
        ..color = Color.lerp(
          EscapePalette.tunnelRing,
          EscapePalette.signal,
          glow,
        )!,
    );
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
  /// pencereler. Kırmızı metroyu ayıran renk **tek başına değil**: iki
  /// vagonu ayıran körük ve tünele bakan sivri burundaki ok yalnız onda
  /// var — renk körü oyuncu da hedefi biçiminden tanır.
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

    // Gölge: yalnız kalkan metroda belirgin — parmağın altındaki metro
    // tahtadan kalkmış görünsün.
    canvas.drawRRect(
      shape.shift(Offset(0, c * (lifted ? 0.12 : 0.04))),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.45 : 0.3)
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
