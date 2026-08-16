import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('canPlace', () {
    test('boş board geçerli parçayı kabul eder', () {
      final board = Board.empty();
      expect(canPlace(board, PieceShapes.square2, 0, 0), isTrue);
      expect(canPlace(board, PieceShapes.l5a, 5, 5), isTrue);
    });

    test('board dışına taşan yerleştirme reddedilir', () {
      final board = Board.empty();

      // Sağ kenardan taşma: h4 sütun 5'ten başlarsa 5,6,7,8 gerekir.
      expect(canPlace(board, PieceShapes.h4, 0, 5), isFalse);
      // Alt kenardan taşma.
      expect(canPlace(board, PieceShapes.v4, 5, 0), isFalse);
      // Negatif koordinat.
      expect(canPlace(board, PieceShapes.dot, -1, 0), isFalse);
      expect(canPlace(board, PieceShapes.dot, 0, -1), isFalse);
      expect(canPlace(board, PieceShapes.dot, 8, 0), isFalse);
    });

    test('dolu hücreyle çakışan yerleştirme reddedilir', () {
      final board = boardFrom(<String>[
        '..X.....',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);

      expect(canPlace(board, PieceShapes.h3, 0, 0), isFalse);
      expect(canPlace(board, PieceShapes.h3, 1, 0), isTrue);
    });
  });

  group('placePiece', () {
    test('doğru hücreleri doldurur', () {
      final board = Board.empty();
      final next = placePiece(board, PieceShapes.l3a, 2, 3);

      expect(next.valueAt(2, 3), isNot(kEmptyCell));
      expect(next.valueAt(3, 3), isNot(kEmptyCell));
      expect(next.valueAt(3, 4), isNot(kEmptyCell));
      expect(next.filledCount, 3);
    });

    test('kaynak board mutasyona uğramaz', () {
      final board = Board.empty();
      placePiece(board, PieceShapes.square2, 0, 0);
      expect(board.filledCount, 0);
    });

    test('parçanın rengini hücreye yazar', () {
      final piece = PieceShapes.dot.withColor(4);
      final next = placePiece(Board.empty(), piece, 1, 1);
      expect(next.valueAt(1, 1), 4);
    });
  });

  group('tamamlanan hat tespiti', () {
    test('yatay dolu satır bulunur', () {
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'XXXXXXX.',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);

      expect(findCompletedRows(board), <int>[0]);
      expect(findCompletedColumns(board), isEmpty);
    });

    test('dikey dolu sütun bulunur', () {
      final board = boardFrom(<String>[
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
      ]);

      expect(findCompletedColumns(board), <int>[0]);
      expect(findCompletedRows(board), isEmpty);
    });

    test('aynı anda satır ve sütun bulunur', () {
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
      ]);

      expect(findCompletedRows(board), <int>[0]);
      expect(findCompletedColumns(board), <int>[0]);
    });
  });

  group('clearLines', () {
    test('satır ve sütun aynı anda temizlenir, kesişim iki kez silinmez', () {
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
        'X.......',
      ]);

      final cleared = clearLines(board, rows: <int>[0], columns: <int>[0]);
      expect(cleared.filledCount, 0);
    });

    test('temizlik diğer hücrelere dokunmaz', () {
      final board = boardFrom(<String>[
        'XXXXXXXX',
        '..XX....',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);

      final cleared = clearLines(board, rows: <int>[0]);
      expect(cleared.valueAt(0, 0), kEmptyCell);
      expect(cleared.valueAt(1, 2), isNot(kEmptyCell));
      expect(cleared.valueAt(1, 3), isNot(kEmptyCell));
      expect(cleared.filledCount, 2);
    });

    test('boş liste board’u değiştirmez', () {
      final board = boardFrom(<String>[
        'X.......',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(clearLines(board).filledCount, 1);
    });
  });

  test('engel hücresi dolu sayılır ve temizlenebilir', () {
    final grid = List<List<int>>.generate(8, (_) => List<int>.filled(8, 1));
    grid[0][0] = kBlockerCell;
    final board = Board.fromGrid(grid);

    expect(canPlace(board, PieceShapes.dot, 0, 0), isFalse);
    expect(findCompletedRows(board), contains(0));
    expect(clearLines(board, rows: <int>[0]).valueAt(0, 0), kEmptyCell);
  });
}
