import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';

void main() {
  group('calculateScore', () {
    test('sadece yerleştirme: hücre başına 1 puan', () {
      final result = calculateScore(
        placedCells: 4,
        clearedRows: 0,
        clearedColumns: 0,
        currentCombo: 0,
      );

      expect(result.points, 4);
      expect(result.linesCleared, 0);
      expect(result.combo, 0);
    });

    test('tek satır: 5 hücre + 10 puan', () {
      final result = calculateScore(
        placedCells: 5,
        clearedRows: 1,
        clearedColumns: 0,
        currentCombo: 0,
      );

      expect(result.points, 5 + 10);
      expect(result.combo, 1);
      expect(result.multiplier, 1);
    });

    test('tek sütun satırla aynı değerde', () {
      final row = calculateScore(
        placedCells: 3,
        clearedRows: 1,
        clearedColumns: 0,
        currentCombo: 0,
      );
      final column = calculateScore(
        placedCells: 3,
        clearedRows: 0,
        clearedColumns: 1,
        currentCombo: 0,
      );

      expect(row.points, column.points);
    });

    test('aynı hamlede 2 line: 30 bonus', () {
      final result = calculateScore(
        placedCells: 2,
        clearedRows: 1,
        clearedColumns: 1,
        currentCombo: 0,
      );

      // 2 yerleştirme + (10 + 10 + 30) * 1
      expect(result.points, 2 + 50);
      expect(result.linesCleared, 2);
    });

    test('aynı hamlede 3+ line: 60 bonus', () {
      final result = calculateScore(
        placedCells: 3,
        clearedRows: 2,
        clearedColumns: 1,
        currentCombo: 0,
      );

      // 3 yerleştirme + (30 + 60) * 1
      expect(result.points, 3 + 90);
      expect(result.linesCleared, 3);
    });

    test('4 line 3+ bonusunu kullanır', () {
      final result = calculateScore(
        placedCells: 0,
        clearedRows: 2,
        clearedColumns: 2,
        currentCombo: 0,
      );

      expect(result.points, 40 + 60);
    });

    group('combo', () {
      test('ardışık temizlikte combo artar', () {
        final first = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          currentCombo: 0,
        );
        final second = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          currentCombo: first.combo,
        );

        expect(first.combo, 1);
        expect(second.combo, 2);
      });

      test('combo line puanını çarpar, yerleştirme puanını çarpmaz', () {
        final result = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          currentCombo: 2,
        );

        // 4 + 10 * 3
        expect(result.points, 4 + 30);
        expect(result.multiplier, 3);
      });

      test('son durak sprintinde puanlar iki katı', () {
        final normal = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          currentCombo: 0,
        );
        final sprint = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          currentCombo: 0,
          isSprint: true,
        );

        expect(sprint.points, normal.points * 2);
        expect(
          sprint.combo,
          normal.combo,
          reason: 'sprint combo’yu değiştirmez',
        );
      });

      test('sprint yerleştirme puanını da çarpar', () {
        final sprint = calculateScore(
          placedCells: 3,
          clearedRows: 0,
          clearedColumns: 0,
          currentCombo: 0,
          isSprint: true,
        );
        expect(sprint.points, 6);
      });

      test('temizlik yoksa combo sıfırlanır', () {
        final result = calculateScore(
          placedCells: 2,
          clearedRows: 0,
          clearedColumns: 0,
          currentCombo: 5,
        );

        expect(result.combo, 0);
        expect(result.points, 2);
      });
    });
  });
}
