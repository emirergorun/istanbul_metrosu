import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/constants/app_constants.dart';
import 'package:istanbul_metro_game/features/game/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/game/domain/board.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';

import '../helpers/board_helpers.dart';

void main() {
  group('PieceGenerator', () {
    test('tepsi her zaman 3 parça üretir', () {
      final generator = PieceGenerator(random: Random(7));
      final tray = generator.generateTray(
        Board.empty(),
        DifficultyProfiles.standard,
      );

      expect(tray.length, AppConstants.traySize);
    });

    test('üretilen parçalara renk atanır', () {
      final generator = PieceGenerator(random: Random(7));
      final tray = generator.generateTray(
        Board.empty(),
        DifficultyProfiles.mini,
      );

      for (final piece in tray) {
        expect(piece.colorIndex, greaterThan(0));
      }
    });

    test('fairness: dar board’da bile en az bir legal hamle bulunur', () {
      final generator = PieceGenerator(random: Random(3));

      // Sadece 3 hücrelik boşluk kalmış board.
      final board = boardFrom(<String>[
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXXXXX',
        'XXXXX...',
      ]);

      for (var i = 0; i < 50; i++) {
        final tray = generator.generateTray(board, DifficultyProfiles.marathon);
        expect(
          hasAnyLegalMove(board, tray),
          isTrue,
          reason: 'Tepside oynanabilir parça yok (deneme $i)',
        );
      }
    });

    test('aynı seed aynı tepsiyi üretir (deterministik)', () {
      final first = PieceGenerator(
        random: Random(99),
      ).generateTray(Board.empty(), DifficultyProfiles.standard);
      final second = PieceGenerator(
        random: Random(99),
      ).generateTray(Board.empty(), DifficultyProfiles.standard);

      expect(first.map((p) => p.id).toList(), second.map((p) => p.id).toList());
    });

    test('zor profil daha çok zor parça üretir', () {
      int hardCount(DifficultyProfile profile) {
        final generator = PieceGenerator(random: Random(11));
        var count = 0;
        for (var i = 0; i < 400; i++) {
          if (generator.nextPiece(profile).difficulty.name == 'hard') count++;
        }
        return count;
      }

      expect(
        hardCount(DifficultyProfiles.marathon),
        greaterThan(hardCount(DifficultyProfiles.mini)),
      );
    });
  });

  group('applyInitialBlockers', () {
    test('mini profilde engel yok', () {
      final generator = PieceGenerator(random: Random(1));
      final board = generator.applyInitialBlockers(
        Board.empty(),
        DifficultyProfiles.mini,
      );

      expect(board.filledCount, 0);
    });

    test('maraton profilinde engel eklenir ve oran makul', () {
      final generator = PieceGenerator(random: Random(1));
      final board = generator.applyInitialBlockers(
        Board.empty(),
        DifficultyProfiles.marathon,
      );

      final expected =
          (board.cellCount * DifficultyProfiles.marathon.initialBlockerRatio)
              .round();
      expect(board.filledCount, expected);
      expect(board.filledCount, lessThan(board.cellCount ~/ 4));
    });

    test('engelli board’da oyun başlangıcında hamle vardır', () {
      final generator = PieceGenerator(random: Random(5));
      final board = generator.applyInitialBlockers(
        Board.empty(),
        DifficultyProfiles.marathon,
      );
      final tray = generator.generateTray(board, DifficultyProfiles.marathon);

      expect(hasAnyLegalMove(board, tray), isTrue);
    });
  });
}
