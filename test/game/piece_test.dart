import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/game/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/game/domain/cell.dart';
import 'package:istanbul_metro_game/features/game/domain/piece_shapes.dart';

void main() {
  group('parça kataloğu', () {
    test('tüm şekiller geçerli ve normalize', () {
      for (final piece in PieceShapes.all) {
        expect(
          piece.isValidShape,
          isTrue,
          reason: '${piece.id} geçersiz veya normalize değil',
        );
      }
    });

    test('hiçbir şekilde tekrar eden hücre yok', () {
      for (final piece in PieceShapes.all) {
        expect(
          piece.cells.toSet().length,
          piece.cells.length,
          reason: '${piece.id} tekrar eden hücre içeriyor',
        );
      }
    });

    test('şekil id’leri benzersiz', () {
      final ids = PieceShapes.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('havuzlar doğru zorlukla etiketlenmiş', () {
      for (final piece in PieceShapes.easy) {
        expect(piece.difficulty, PieceDifficulty.easy);
      }
      for (final piece in PieceShapes.medium) {
        expect(piece.difficulty, PieceDifficulty.medium);
      }
      for (final piece in PieceShapes.hard) {
        expect(piece.difficulty, PieceDifficulty.hard);
      }
    });
  });

  group('boyut hesabı', () {
    test('1x1', () {
      expect(PieceShapes.dot.width, 1);
      expect(PieceShapes.dot.height, 1);
      expect(PieceShapes.dot.size, 1);
    });

    test('1x4 yatay', () {
      expect(PieceShapes.h4.width, 4);
      expect(PieceShapes.h4.height, 1);
      expect(PieceShapes.h4.size, 4);
    });

    test('4x1 dikey', () {
      expect(PieceShapes.v4.width, 1);
      expect(PieceShapes.v4.height, 4);
    });

    test('L-5 3x3 kutuya sığar ve 5 hücredir', () {
      expect(PieceShapes.l5a.width, 3);
      expect(PieceShapes.l5a.height, 3);
      expect(PieceShapes.l5a.size, 5);
    });

    test('T-5 3x3 kutuya sığar ve 5 hücredir', () {
      expect(PieceShapes.t5Down.width, 3);
      expect(PieceShapes.t5Down.height, 3);
      expect(PieceShapes.t5Down.size, 5);
    });
  });

  test('cellsAt parçayı doğru öteler', () {
    final cells = PieceShapes.l3a.cellsAt(2, 3);
    expect(cells, containsAll(<Cell>[Cell(2, 3), Cell(3, 3), Cell(3, 4)]));
  });

  test('withColor renk dışında şekli değiştirmez', () {
    final colored = PieceShapes.h3.withColor(5);
    expect(colored.colorIndex, 5);
    expect(colored.cells, PieceShapes.h3.cells);
    expect(colored.id, PieceShapes.h3.id);
  });

  test('geçersiz şekil isValidShape ile yakalanır', () {
    const duplicated = BlockPiece(
      id: 'bozuk',
      difficulty: PieceDifficulty.easy,
      cells: <Cell>[Cell(0, 0), Cell(0, 0)],
    );
    const notNormalized = BlockPiece(
      id: 'kaymis',
      difficulty: PieceDifficulty.easy,
      cells: <Cell>[Cell(1, 1)],
    );

    expect(duplicated.isValidShape, isFalse);
    expect(notNormalized.isValidShape, isFalse);
  });
}
