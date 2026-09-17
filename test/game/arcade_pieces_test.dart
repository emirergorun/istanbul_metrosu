import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';

/// Arcade parça seti: büyük parçalar ve tahtaya göre gelme sıklıkları.
///
/// Eldeki set en fazla 5 hücreydi; tek hamlede birden çok hattı temizlemek
/// neredeyse yalnızca şansa kalıyordu. Büyük parçalar hem risk hem ödül
/// getirir — ama sabit olasılıkla dağıtıldıklarında tahta doluyken oyunu
/// bitiriyor, boşken ise hiç görünmüyorlardı.
void main() {
  const bigIds = <String>['square3', 'rect23', 'rect32', 'h5', 'v5'];

  group('katalog', () {
    test('3x3 kare katalogda ve tam dokuz hücre', () {
      final square = PieceShapes.byId('square3');

      expect(square, isNotNull);
      expect(square!.size, 9);
      expect(square.width, 3);
      expect(square.height, 3);
    });

    test('büyük parçaların hepsi katalogda', () {
      for (final id in bigIds) {
        expect(PieceShapes.byId(id), isNotNull, reason: id);
      }
    });

    test('yeni şekillerin hepsi geçerli ve normalize', () {
      for (final piece in PieceShapes.all) {
        expect(piece.isValidShape, isTrue, reason: piece.id);
      }
    });

    test('şekil kimlikleri benzersiz', () {
      final ids = PieceShapes.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('her şekil 8x8 tahtaya sığar', () {
      final board = Board.empty();
      for (final piece in PieceShapes.all) {
        expect(
          findFirstLegalPosition(board, piece),
          isNotNull,
          reason: '${piece.id} boş tahtaya konabilmeli',
        );
      }
    });

    test('S ve Z zikzakları birbirinin aynısı değil', () {
      final s = PieceShapes.byId('s4')!;
      final z = PieceShapes.byId('z4')!;
      expect(s.cells, isNot(z.cells));
    });
  });

  group('tahtaya göre sıklık', () {
    /// [fill] doluluğunda üretilen parçaların yüzde kaçı büyük.
    double bigShare(double fill, {int draws = 20000}) {
      final generator = PieceGenerator(random: Random(7));
      var big = 0;
      for (var i = 0; i < draws; i++) {
        final piece = generator.nextPiece(
          DifficultyProfiles.standard,
          fill: fill,
        );
        if (bigIds.contains(piece.id)) big++;
      }
      return big / draws;
    }

    test('boş tahtada büyük parça gelir', () {
      expect(bigShare(0), greaterThan(0.05));
    });

    test('tahta doldukça büyük parça seyrekleşir', () {
      final empty = bigShare(0);
      final half = bigShare(0.5);
      final full = bigShare(0.85);

      expect(half, lessThan(empty));
      expect(full, lessThan(half));
    });

    test('dolu tahtada bile tamamen kesilmez', () {
      // Kesilseydi oyuncu tahtayı bilerek doldurup büyük parçadan
      // kaçınabilirdi; kural "seyrekleşir", "biter" değil.
      expect(bigShare(1.0), greaterThan(0));
    });

    test('sıklık katsayıları doğru yönde', () {
      expect(
        PieceGenerator.openBoardHardBoost,
        greaterThan(PieceGenerator.fullBoardHardBoost),
      );
    });
  });

  group('büyük parça oyunu bozmaz', () {
    test('3x3 bir hamlede üç satır ve üç sütunu birden besler', () {
      // Sağ alt 3x3 dışında her yeri dolu tahta: 3x3 konunca üç satır ve
      // üç sütun birden tamamlanır.
      final grid = List<List<int>>.generate(
        8,
        (r) => List<int>.generate(8, (c) => (r >= 5 && c >= 5) ? 0 : 1),
      );
      final board = Board.fromGrid(grid);
      final square = PieceShapes.byId('square3')!;

      expect(canPlace(board, square, 5, 5), isTrue);

      final placed = placePiece(board, square, 5, 5);
      expect(findCompletedRows(placed).length, 8);
      expect(findCompletedColumns(placed).length, 8);
    });

    test('tepsi üretimi büyük parçalarla da fairness kuralını korur', () {
      // Dar bir tahta: yalnızca birkaç hücre boş.
      final grid = List<List<int>>.generate(
        8,
        (r) => List<int>.generate(8, (c) => (r == 7 && c >= 5) ? 0 : 1),
      );
      final board = Board.fromGrid(grid);

      for (var seed = 0; seed < 30; seed++) {
        final tray = PieceGenerator(
          random: Random(seed),
        ).generateTray(board, DifficultyProfiles.standard);

        expect(
          hasAnyLegalMove(board, tray),
          isTrue,
          reason: 'dar tahtada bile konabilir parça gelmeli (seed $seed)',
        );
      }
    });
  });
}
