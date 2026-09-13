import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../domain/block_piece.dart';
import '../../domain/board.dart';

/// Sürükleme sırasında board üzerinde gösterilen ön izleme.
@immutable
class BoardPreview {
  const BoardPreview({
    required this.piece,
    required this.row,
    required this.col,
    required this.isValid,
  });

  final BlockPiece piece;
  final int row;
  final int col;
  final bool isValid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardPreview &&
          other.piece == piece &&
          other.row == row &&
          other.col == col &&
          other.isValid == isValid);

  @override
  int get hashCode => Object.hash(piece, row, col, isValid);
}

/// Temizlenen satır/sütunların patlama efekti.
@immutable
class BoardFlash {
  const BoardFlash({
    required this.rows,
    required this.columns,
    this.cellValues = const <int, int>{},
  });

  final List<int> rows;
  final List<int> columns;

  /// Temizlenen hücrelerin silinmeden önceki renk değerleri
  /// (`satır * sütunSayısı + sütun` -> değer). Parçacıklar blokların kendi
  /// renginde savrulsun diye taşınır.
  final Map<int, int> cellValues;

  bool get isEmpty => rows.isEmpty && columns.isEmpty;
}

/// 8x8 oyun tahtası.
///
/// Performans: tek [CustomPaint]. Sürükleme ön izlemesi ve temizleme
/// animasyonu widget rebuild etmeden `repaint` listenable üzerinden çizilir.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.board,
    required this.cellSize,
    required this.preview,
    required this.flash,
    required this.flashAnimation,
  });

  final Board board;
  final double cellSize;
  final ValueListenable<BoardPreview?> preview;
  final ValueListenable<BoardFlash?> flash;
  final Animation<double> flashAnimation;

  double get width => board.cols * cellSize;
  double get height => board.rows * cellSize;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, height),
        painter: _BoardPainter(
          board: board,
          cellSize: cellSize,
          preview: preview,
          flash: flash,
          flashAnimation: flashAnimation,
          repaint: Listenable.merge(<Listenable>[
            preview,
            flash,
            flashAnimation,
          ]),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.cellSize,
    required this.preview,
    required this.flash,
    required this.flashAnimation,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Board board;
  final double cellSize;
  final ValueListenable<BoardPreview?> preview;
  final ValueListenable<BoardFlash?> flash;
  final Animation<double> flashAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCells(canvas);
    _paintPreview(canvas);
    _paintFlash(canvas);
  }

  Rect _cellRect(int row, int col) {
    final gap = cellSize * 0.06;
    return Rect.fromLTWH(
      col * cellSize + gap,
      row * cellSize + gap,
      cellSize - gap * 2,
      cellSize - gap * 2,
    );
  }

  RRect _cellRRect(int row, int col) => RRect.fromRectAndRadius(
    _cellRect(row, col),
    Radius.circular(cellSize * 0.20),
  );

  void _paintCells(Canvas canvas) {
    final emptyPaint = Paint()..color = AppColors.emptyCell;
    // Izgara boş hücrenin dolgusuyla değil bu ince çizgiyle çiziliyor;
    // gerekçesi `AppColors.cellGrid` üzerinde. Çizgi hücre sınırının tam
    // üstüne oturmasın diye yarım kalınlık içeri alınır.
    final gridPaint = Paint()
      ..color = AppColors.cellGrid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final value = board.valueAt(r, c);
        final rrect = _cellRRect(r, c);

        if (value == kEmptyCell) {
          canvas.drawRRect(rrect, emptyPaint);
          canvas.drawRRect(rrect.deflate(0.5), gridPaint);
          continue;
        }

        final color = AppColors.forCellValue(value);
        canvas.drawRRect(rrect, Paint()..color = color);

        // Engel hücresi: yalnız renkle değil, desenle de ayrışsın.
        if (value == kBlockerCell) {
          _paintBlockerHatch(canvas, rrect);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                rrect.left,
                rrect.top,
                rrect.width,
                rrect.height * 0.42,
              ),
              Radius.circular(cellSize * 0.20),
            ),
            Paint()..color = Colors.white.withValues(alpha: 0.10),
          );
        }
      }
    }
  }

  void _paintBlockerHatch(Canvas canvas, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.6;
    for (var x = -rrect.height; x < rrect.width; x += 6) {
      canvas.drawLine(
        Offset(rrect.left + x, rrect.bottom),
        Offset(rrect.left + x + rrect.height, rrect.top),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintPreview(Canvas canvas) {
    final value = preview.value;
    if (value == null) return;

    final piece = value.piece;
    final color = value.isValid
        ? AppColors.forCellValue(piece.colorIndex)
        : AppColors.danger;

    // Geçerli yerleştirmede tamamlanacak satır/sütunları da vurgula.
    if (value.isValid) {
      _paintCompletionHint(canvas, value);
    }

    for (final cell in piece.cells) {
      final r = value.row + cell.row;
      final c = value.col + cell.col;
      if (!board.contains(r, c)) continue;

      final rrect = _cellRRect(r, c);
      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: value.isValid ? 0.45 : 0.28),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  /// Bu hamle bir satır/sütun tamamlıyorsa o hattı hafifçe aydınlat.
  void _paintCompletionHint(Canvas canvas, BoardPreview value) {
    final grid = board.toGrid();
    for (final cell in value.piece.cells) {
      final r = value.row + cell.row;
      final c = value.col + cell.col;
      // Taşan hücre atlanır — `return` olsaydı tek bir taşma yüzünden
      // ipucunun tamamı çizilmezdi.
      if (r < 0 || r >= board.rows || c < 0 || c >= board.cols) continue;
      grid[r][c] = 1;
    }
    final hypothetical = Board.fromGrid(grid);
    final paint = Paint()..color = AppColors.success.withValues(alpha: 0.16);

    for (final r in findCompletedRows(hypothetical)) {
      canvas.drawRect(
        Rect.fromLTWH(0, r * cellSize, board.cols * cellSize, cellSize),
        paint,
      );
    }
    for (final c in findCompletedColumns(hypothetical)) {
      canvas.drawRect(
        Rect.fromLTWH(c * cellSize, 0, cellSize, board.rows * cellSize),
        paint,
      );
    }
  }

  /// Patlama: parlama → şok dalgası → savrulan parçacıklar.
  ///
  /// Üç katman üst üste bindiği için temizlik "kayboldu" değil "patladı" gibi
  /// okunuyor. Parçacık yönleri hücre konumundan türetilen deterministik bir
  /// sözde-rastgeleden gelir; her karede yeniden üretilmediği için parçacıklar
  /// titremez.
  void _paintFlash(Canvas canvas) {
    final value = flash.value;
    if (value == null || value.isEmpty) return;

    final t = flashAnimation.value.clamp(0.0, 1.0);
    if (t >= 1) return;

    final cells = <({int row, int col})>[];
    for (final r in value.rows) {
      for (var c = 0; c < board.cols; c++) {
        cells.add((row: r, col: c));
      }
    }
    for (final c in value.columns) {
      for (var r = 0; r < board.rows; r++) {
        if (value.rows.contains(r)) continue; // kesişim iki kez patlamasın
        cells.add((row: r, col: c));
      }
    }

    _paintBurstCore(canvas, cells, t);
    _paintShockwave(canvas, value, t);
    _paintParticles(canvas, value, cells, t);
  }

  /// İlk anda hücrenin yerinde kalan beyaz çekirdek; hızla sönüp küçülür.
  void _paintBurstCore(
    Canvas canvas,
    List<({int row, int col})> cells,
    double t,
  ) {
    final k = (t / 0.35).clamp(0.0, 1.0);
    if (k >= 1) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 * (1 - k));
    final grow = 1.0 + k * 0.25;

    for (final cell in cells) {
      final rect = _cellRect(cell.row, cell.col);
      final scaled = Rect.fromCenter(
        center: rect.center,
        width: rect.width * grow,
        height: rect.height * grow,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(cellSize * 0.20)),
        paint,
      );
    }
  }

  /// Temizlenen her hattın ortasından yayılan halka.
  void _paintShockwave(Canvas canvas, BoardFlash flash, double t) {
    final k = (t / 0.7).clamp(0.0, 1.0);
    if (k >= 1) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cellSize * 0.10 * (1 - k)
      ..color = Colors.white.withValues(alpha: 0.5 * (1 - k));

    final maxRadius = board.cols * cellSize * 0.55;
    for (final r in flash.rows) {
      final center = Offset(board.cols * cellSize / 2, (r + 0.5) * cellSize);
      canvas.drawCircle(center, maxRadius * k, paint);
    }
    for (final c in flash.columns) {
      final center = Offset((c + 0.5) * cellSize, board.rows * cellSize / 2);
      canvas.drawCircle(center, maxRadius * k, paint);
    }
  }

  /// Hücre başına savrulan enkaz. Yerçekimi var: yukarı çıkıp aşağı düşerler.
  void _paintParticles(
    Canvas canvas,
    BoardFlash flash,
    List<({int row, int col})> cells,
    double t,
  ) {
    const perCell = 5;
    final fade = (1 - t) * (1 - t);
    if (fade <= 0.01) return;

    for (final cell in cells) {
      final origin = _cellRect(cell.row, cell.col).center;
      final key = cell.row * board.cols + cell.col;
      final colorValue = flash.cellValues[key] ?? 0;
      final color = colorValue > 0
          ? AppColors.forCellValue(colorValue)
          : Colors.white;

      for (var i = 0; i < perCell; i++) {
        final seed = key * 31 + i * 7;
        final angle = _pseudoRandom(seed) * 2 * math.pi;
        final speed = (0.55 + _pseudoRandom(seed + 1) * 0.75) * cellSize * 2.4;
        final spin = 0.6 + _pseudoRandom(seed + 2) * 0.8;

        // Konum: düz savrulma + yerçekimi.
        final dx = math.cos(angle) * speed * t;
        final dy = math.sin(angle) * speed * t + cellSize * 5.0 * t * t;
        final size = cellSize * 0.17 * spin * (1 - t);
        if (size <= 0.2) continue;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: origin + Offset(dx, dy),
              width: size,
              height: size,
            ),
            Radius.circular(size * 0.3),
          ),
          Paint()..color = color.withValues(alpha: fade),
        );
      }
    }
  }

  /// Deterministik sözde-rastgele, 0..1. Aynı tohum her karede aynı değeri
  /// verir; yoksa parçacıklar her frame'de yer değiştirir.
  double _pseudoRandom(int seed) {
    var x = (seed * 1103515245 + 12345) & 0x7fffffff;
    x = (x >> 16) ^ x;
    return ((x * 2654435761) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.board != board || oldDelegate.cellSize != cellSize;
}
