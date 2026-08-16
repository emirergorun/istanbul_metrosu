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

/// Temizlenen satır/sütunların kısa parlama efekti.
@immutable
class BoardFlash {
  const BoardFlash({required this.rows, required this.columns});

  final List<int> rows;
  final List<int> columns;

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

    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final value = board.valueAt(r, c);
        final rrect = _cellRRect(r, c);

        if (value == kEmptyCell) {
          canvas.drawRRect(rrect, emptyPaint);
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

  void _paintFlash(Canvas canvas) {
    final value = flash.value;
    if (value == null || value.isEmpty) return;

    final t = flashAnimation.value.clamp(0.0, 1.0);
    final alpha = (1.0 - t) * 0.85;
    if (alpha <= 0) return;

    final paint = Paint()..color = Colors.white.withValues(alpha: alpha);
    final shrink = 1.0 - t * 0.35;

    void drawCell(int r, int c) {
      final rect = _cellRect(r, c);
      final scaled = Rect.fromCenter(
        center: rect.center,
        width: rect.width * shrink,
        height: rect.height * shrink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, Radius.circular(cellSize * 0.20)),
        paint,
      );
    }

    for (final r in value.rows) {
      for (var c = 0; c < board.cols; c++) {
        drawCell(r, c);
      }
    }
    for (final c in value.columns) {
      for (var r = 0; r < board.rows; r++) {
        drawCell(r, c);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.board != board || oldDelegate.cellSize != cellSize;
}
