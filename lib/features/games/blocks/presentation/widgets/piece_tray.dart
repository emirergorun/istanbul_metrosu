import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../domain/block_piece.dart';
import '../../domain/board.dart';
import 'piece_view.dart';

/// Sürüklenen parçanın taşıdığı veri.
@immutable
class TrayDragData {
  const TrayDragData({required this.index, required this.piece});

  final int index;
  final BlockPiece piece;
}

/// 3'lü parça tepsisi.
///
/// Parmağın parçayı kapatmaması için sürükleme sırasında parça board
/// ölçeğinde ve parmağın biraz üstünde gösterilir.
class PieceTray extends StatelessWidget {
  const PieceTray({
    super.key,
    required this.pieces,
    required this.board,
    required this.boardCellSize,
    required this.enabled,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<BlockPiece?> pieces;
  final Board board;
  final double boardCellSize;
  final bool enabled;
  final ValueChanged<TrayDragData> onDragStarted;
  final VoidCallback onDragEnded;

  /// Tepsideki parçalar board ölçeğinden küçük gösterilir.
  double get _trayCellSize => boardCellSize * 0.62;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: boardCellSize * AppConstants.trayHeightFactor,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < pieces.length; i++)
            Expanded(
              child: _TraySlot(
                piece: pieces[i],
                index: i,
                board: board,
                boardCellSize: boardCellSize,
                trayCellSize: _trayCellSize,
                enabled: enabled,
                onDragStarted: onDragStarted,
                onDragEnded: onDragEnded,
              ),
            ),
        ],
      ),
    );
  }
}

class _TraySlot extends StatelessWidget {
  const _TraySlot({
    required this.piece,
    required this.index,
    required this.board,
    required this.boardCellSize,
    required this.trayCellSize,
    required this.enabled,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final BlockPiece? piece;
  final int index;
  final Board board;
  final double boardCellSize;
  final double trayCellSize;
  final bool enabled;
  final ValueChanged<TrayDragData> onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final current = piece;
    if (current == null) return const SizedBox.shrink();

    final placeable = canPlaceAnywhere(board, current);
    final child = Center(
      child: PieceView(
        piece: current,
        cellSize: trayCellSize,
        // Konulamayan parça soluklaşır: "neden oynayamıyorum?" hissini azaltır.
        opacity: placeable ? 1.0 : 0.32,
      ),
    );

    if (!enabled) return child;

    final data = TrayDragData(index: index, piece: current);

    return Draggable<TrayDragData>(
      data: data,
      dragAnchorStrategy: (draggable, context, position) => Offset(
        current.width * boardCellSize / 2,
        current.height * boardCellSize + boardCellSize * 0.55,
      ),
      feedback: PieceView(piece: current, cellSize: boardCellSize),
      childWhenDragging: Opacity(opacity: 0.18, child: child),
      onDragStarted: () => onDragStarted(data),
      onDragEnd: (_) => onDragEnded(),
      onDraggableCanceled: (_, _) => onDragEnded(),
      onDragCompleted: onDragEnded,
      child: child,
    );
  }
}

/// Tepsi arka planı — board ile tepsiyi görsel olarak ayırır.
class TrayBackground extends StatelessWidget {
  const TrayBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: child,
    );
  }
}
