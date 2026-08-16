import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../domain/block_piece.dart';

/// Tek bir parçayı verilen hücre boyutunda çizer.
///
/// Hem tepside (küçük) hem de sürükleme sırasında (board ölçeğinde) kullanılır.
class PieceView extends StatelessWidget {
  const PieceView({
    super.key,
    required this.piece,
    required this.cellSize,
    this.opacity = 1.0,
  });

  final BlockPiece piece;
  final double cellSize;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: piece.width * cellSize,
      height: piece.height * cellSize,
      child: CustomPaint(
        painter: _PiecePainter(
          piece: piece,
          cellSize: cellSize,
          opacity: opacity,
        ),
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter({
    required this.piece,
    required this.cellSize,
    required this.opacity,
  });

  final BlockPiece piece;
  final double cellSize;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = cellSize * 0.07;
    final radius = Radius.circular(cellSize * 0.22);
    final color = AppColors.forCellValue(piece.colorIndex);

    for (final cell in piece.cells) {
      final rect = Rect.fromLTWH(
        cell.col * cellSize + gap,
        cell.row * cellSize + gap,
        cellSize - gap * 2,
        cellSize - gap * 2,
      );
      final rrect = RRect.fromRectAndRadius(rect, radius);

      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: opacity),
      );

      // Üst kenarda hafif parlaklık: hücreler düz renk lekesi gibi durmasın.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.42),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.10 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_PiecePainter oldDelegate) =>
      oldDelegate.piece != piece ||
      oldDelegate.cellSize != cellSize ||
      oldDelegate.opacity != opacity;
}
