import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/game/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/game/domain/board.dart';
import 'package:istanbul_metro_game/features/game/domain/piece_shapes.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('hasAnyLegalMove', () {
    test('boş board: hamle var', () {
      expect(
        hasAnyLegalMove(Board.empty(), <BlockPiece?>[
          PieceShapes.l5a,
          PieceShapes.h4,
          PieceShapes.dot,
        ]),
        isTrue,
      );
    });

    test('dolu board: hiçbir parça konamaz -> game over', () {
      final board = fullBoard();
      expect(
        hasAnyLegalMove(board, <BlockPiece?>[
          PieceShapes.dot,
          PieceShapes.h2,
          PieceShapes.square2,
        ]),
        isFalse,
      );
    });

    test('tek boş hücre varsa yalnız 1x1 sığar', () {
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXX.',
      ]);

      expect(canPlaceAnywhere(board, PieceShapes.dot), isTrue);
      expect(canPlaceAnywhere(board, PieceShapes.h2), isFalse);
      expect(hasAnyLegalMove(board, <BlockPiece?>[PieceShapes.h2]), isFalse);
      expect(
        hasAnyLegalMove(board, <BlockPiece?>[PieceShapes.h2, PieceShapes.dot]),
        isTrue,
      );
    });

    test('kullanılmış (null) tepsi slotları yok sayılır', () {
      expect(
        hasAnyLegalMove(Board.empty(), <BlockPiece?>[null, null]),
        isFalse,
      );
      expect(
        hasAnyLegalMove(Board.empty(), <BlockPiece?>[null, PieceShapes.dot]),
        isTrue,
      );
    });
  });

  group('findFirstLegalPosition', () {
    test('boş board’da (0,0) döner', () {
      final position = findFirstLegalPosition(Board.empty(), PieceShapes.dot);
      expect(position?.row, 0);
      expect(position?.col, 0);
    });

    test('yer yoksa null döner', () {
      expect(findFirstLegalPosition(fullBoard(), PieceShapes.dot), isNull);
    });
  });
}
