import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../application/rail_lay_controller.dart';
import '../domain/rail_lay_state.dart';

/// Kabartmanın derinliği, hücre cinsinden. Tahtanın altında bu kadar ek
/// yer ayrılır.
const double railLayBoardDepth = 0.16;

/// Tahta: yüzen bir plaka, üzerinde karolar, döşenen raylar ve metro.
///
/// Duvarlar çizilmiyor; arka plandaki Galata sahnesi aralardan görünüyor ve
/// koridor ağı videodaki gibi havada duran bir plaka olarak okunuyor.
/// Kabartma blursuz: plakanın kaydırılmış koyu bir kopyası yan yüz, onun
/// da altında daha koyu bir gölge.
class RailLayPainter extends CustomPainter {
  const RailLayPainter({required this.controller, required this.lineColor});

  final RailLayController controller;

  /// Bu bölümün hattı: döşenen kareler ve metronun şeridi bu renkte.
  final Color lineColor;

  /// Metro gövdesi nötr (Yolcu Topla vagonunun dili): hat rengi yalnızca
  /// şeritte, yoksa döşenmiş karenin üzerinde kaybolurdu.
  static const Color _carBody = Color(0xFFEDEFF2);
  static const Color _carOutline = Color(0xFF7D8590);
  static const Color _carWindow = Color(0xFF29323D);

  @override
  void paint(Canvas canvas, Size size) {
    final level = controller.level;
    if (size.isEmpty) return;
    final cell = size.width / level.width;
    final depth = cell * railLayBoardDepth;

    _paintPlate(canvas, level, cell, depth);
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final point = math.Point<int>(x, y);
        if (!level.isOpen(point)) continue;
        _paintTile(canvas, point, cell, controller.paintAt(point));
      }
    }
    _paintMetro(canvas, cell);
  }

  void _paintPlate(
    Canvas canvas,
    RailLayLevel level,
    double cell,
    double depth,
  ) {
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.38);
    final side = Paint()..color = const Color(0xFF0F1115);
    final top = Paint()..color = AppColors.boardBackground;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        if (!level.isOpen(math.Point<int>(x, y))) continue;
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        canvas.drawRect(rect.shift(Offset(depth * 0.4, depth * 1.6)), shadow);
      }
    }
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        if (!level.isOpen(math.Point<int>(x, y))) continue;
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        canvas.drawRect(rect.shift(Offset(0, depth)), side);
      }
    }
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        if (!level.isOpen(math.Point<int>(x, y))) continue;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), top);
      }
    }
  }

  void _paintTile(Canvas canvas, math.Point<int> point, double cell, int bits) {
    final gap = cell * 0.06;
    final rect = Rect.fromLTWH(
      point.x * cell + gap,
      point.y * cell + gap,
      cell - gap * 2,
      cell - gap * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.16));

    if (bits == 0) {
      canvas.drawRRect(rrect, Paint()..color = AppColors.emptyCell);
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..color = AppColors.cellGrid.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }

    canvas.drawRRect(rrect, Paint()..color = lineColor);
    // Blok Metro'nun "üst ışık" kapağı: düz rengi kabartır.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.42),
        topLeft: rrect.tlRadius,
        topRight: rrect.trRadius,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    final center = Offset((point.x + 0.5) * cell, (point.y + 0.5) * cell);
    if (bits & railLayHorizontal != 0) {
      _paintRails(canvas, center, cell, horizontal: true);
    }
    if (bits & railLayVertical != 0) {
      _paintRails(canvas, center, cell, horizontal: false);
    }
    if (bits == railLayStation) {
      // Başlangıç karesi: henüz ray yok, küçük bir durak halkası.
      canvas.drawCircle(
        center,
        cell * 0.14,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.05,
      );
    }
  }

  /// İki ray ve traversler. Hücre kenarından kenarına çizilir ki komşu
  /// döşenmiş karelerin rayları aralıktan geçerek birleşsin.
  void _paintRails(
    Canvas canvas,
    Offset center,
    double cell, {
    required bool horizontal,
  }) {
    final half = cell / 2;
    final gauge = cell * 0.17;
    final tie = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = cell * 0.07
      ..strokeCap = StrokeCap.round;
    for (final t in <double>[-0.3, 0, 0.3]) {
      final a = horizontal
          ? Offset(center.dx + t * cell, center.dy - gauge * 1.4)
          : Offset(center.dx - gauge * 1.4, center.dy + t * cell);
      final b = horizontal
          ? Offset(center.dx + t * cell, center.dy + gauge * 1.4)
          : Offset(center.dx + gauge * 1.4, center.dy + t * cell);
      canvas.drawLine(a, b, tie);
    }

    // Sarı gibi açık hat renklerinde beyaz ray kaybolmasın diye altında
    // ince koyu bir kontur.
    final under = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = cell * 0.075;
    final rail = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = cell * 0.045;
    for (final side in <double>[-1, 1]) {
      final a = horizontal
          ? Offset(center.dx - half, center.dy + side * gauge)
          : Offset(center.dx + side * gauge, center.dy - half);
      final b = horizontal
          ? Offset(center.dx + half, center.dy + side * gauge)
          : Offset(center.dx + side * gauge, center.dy + half);
      canvas.drawLine(a, b, under);
      canvas.drawLine(a, b, rail);
    }
  }

  /// Üstten görünen tek kabinli metro, gidiş yönüne dönük.
  void _paintMetro(Canvas canvas, double cell) {
    final position = controller.visualPosition;
    final center = Offset(
      (position.dx + 0.5) * cell,
      (position.dy + 0.5) * cell,
    );
    final angle = switch (controller.facing) {
      RailLayDirection.right => 0.0,
      RailLayDirection.down => math.pi / 2,
      RailLayDirection.left => math.pi,
      RailLayDirection.up => -math.pi / 2,
    };

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final length = cell * 0.84;
    final width = cell * 0.62;
    final bodyRect = Rect.fromCenter(
      center: Offset.zero,
      width: length,
      height: width,
    );
    final body = RRect.fromRectAndCorners(
      bodyRect,
      topLeft: Radius.circular(width * 0.18),
      bottomLeft: Radius.circular(width * 0.18),
      topRight: Radius.circular(width * 0.45),
      bottomRight: Radius.circular(width * 0.45),
    );

    // Gölge: sağ alta düşer (dönmeden bağımsız görünsün diye dönüş geri
    // alınarak çizilir).
    canvas.save();
    canvas.rotate(-angle);
    canvas.translate(cell * 0.04, cell * 0.08);
    canvas.rotate(angle);
    canvas.drawRRect(
      body,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.restore();

    canvas.drawRRect(body, Paint()..color = _carBody);

    // Tavandaki hat şeridi: metronun hangi hatta döşediğini söyler.
    canvas.drawRect(
      Rect.fromLTRB(-length * 0.42, -width * 0.11, length * 0.22, width * 0.11),
      Paint()..color = lineColor,
    );
    // Klima kutusu.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-length * 0.22, 0),
          width: length * 0.18,
          height: width * 0.44,
        ),
        Radius.circular(width * 0.06),
      ),
      Paint()..color = const Color(0xFFD5D9DF),
    );
    // Ön cam.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          length * 0.24,
          -width * 0.34,
          length * 0.40,
          width * 0.34,
        ),
        Radius.circular(width * 0.1),
      ),
      Paint()..color = _carWindow,
    );
    // Farlar.
    final lamp = Paint()..color = const Color(0xFFFFF1B8);
    for (final side in <double>[-1, 1]) {
      canvas.drawCircle(
        Offset(length * 0.45, side * width * 0.3),
        cell * 0.035,
        lamp,
      );
    }
    canvas.drawRRect(
      body,
      Paint()
        ..color = _carOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * 0.03),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RailLayPainter oldDelegate) => true;
}
