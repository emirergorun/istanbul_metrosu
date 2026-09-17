import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/clear_result.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';

void main() {
  group('calculateScore', () {
    test('sadece yerleştirme: hücre başına 1 puan', () {
      final result = calculateScore(
        placedCells: 4,
        clearedRows: 0,
        clearedColumns: 0,
        combo: 0,
      );

      expect(result.points, 4);
      expect(result.linesCleared, 0);
      expect(result.tier, ClearTier.none);
    });

    test('tek satır: 5 hücre + 10 puan', () {
      final result = calculateScore(
        placedCells: 5,
        clearedRows: 1,
        clearedColumns: 0,
        combo: 1,
      );

      expect(result.points, 5 + 10);
      expect(result.multiplier, 1);
      expect(result.tier, ClearTier.single);
    });

    test('tek sütun satırla aynı değerde', () {
      final row = calculateScore(
        placedCells: 3,
        clearedRows: 1,
        clearedColumns: 0,
        combo: 1,
      );
      final column = calculateScore(
        placedCells: 3,
        clearedRows: 0,
        clearedColumns: 1,
        combo: 1,
      );

      expect(row.points, column.points);
    });

    test('aynı hamlede 2 line: 30 bonus', () {
      final result = calculateScore(
        placedCells: 2,
        clearedRows: 1,
        clearedColumns: 1,
        combo: 1,
      );

      // 2 yerleştirme + (10 + 10 + 30) * 1
      expect(result.points, 2 + 50);
      expect(result.linesCleared, 2);
      expect(result.tier, ClearTier.double);
    });

    test('aynı hamlede 3+ line: 60 bonus', () {
      final result = calculateScore(
        placedCells: 3,
        clearedRows: 2,
        clearedColumns: 1,
        combo: 1,
      );

      // 3 yerleştirme + (30 + 60) * 1
      expect(result.points, 3 + 90);
      expect(result.linesCleared, 3);
      expect(result.tier, ClearTier.triple);
    });

    test('4 line 3+ bonusunu kullanır ve mega kademesidir', () {
      final result = calculateScore(
        placedCells: 0,
        clearedRows: 2,
        clearedColumns: 2,
        combo: 1,
      );

      expect(result.points, 40 + 60);
      expect(result.tier, ClearTier.mega);
    });

    group('combo', () {
      test('combo line puanını çarpar, yerleştirme puanını çarpmaz', () {
        final result = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 3,
        );

        // 4 + 10 * 3
        expect(result.points, 4 + 30);
        expect(result.multiplier, 3);
        expect(result.comboBonus, 20);
      });

      test('çarpan tavanı aşılmaz', () {
        final capped = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          combo: ScoreRules.comboMaxMultiplier + 5,
        );

        expect(capped.multiplier, ScoreRules.comboMaxMultiplier);
        expect(capped.points, 10 * ScoreRules.comboMaxMultiplier);
      });

      test('temizlik yoksa combo puana etki etmez', () {
        final result = calculateScore(
          placedCells: 2,
          clearedRows: 0,
          clearedColumns: 0,
          combo: 5,
        );

        expect(result.points, 2);
        expect(result.comboBonus, 0);
      });
    });

    group('streak', () {
      test('streak her seviyesi için sabit bonus ekler', () {
        final result = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 1,
          streak: 3,
        );

        expect(result.streakBonus, 3 * ScoreRules.streakBonusPerLevel);
        expect(result.points, 10 + 3 * ScoreRules.streakBonusPerLevel);
      });

      test('streak bonusu tavanda durur', () {
        final result = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 1,
          streak: ScoreRules.streakMaxLevel + 20,
        );

        expect(
          result.streakBonus,
          ScoreRules.streakMaxLevel * ScoreRules.streakBonusPerLevel,
        );
      });

      test('temizlik yoksa streak bonusu verilmez', () {
        final result = calculateScore(
          placedCells: 2,
          clearedRows: 0,
          clearedColumns: 0,
          combo: 0,
          streak: 8,
        );

        expect(result.streakBonus, 0);
        expect(result.points, 2);
      });
    });

    group('sprint', () {
      test('son durak sprintinde puanlar iki katı', () {
        final normal = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 1,
        );
        final sprint = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 1,
          isSprint: true,
        );

        expect(sprint.points, normal.points * 2);
      });

      test('sprint yerleştirme puanını da çarpar', () {
        final sprint = calculateScore(
          placedCells: 3,
          clearedRows: 0,
          clearedColumns: 0,
          combo: 0,
          isSprint: true,
        );
        expect(sprint.points, 6);
      });

      test('döküm toplamla tutarlıdır', () {
        final result = calculateScore(
          placedCells: 4,
          clearedRows: 1,
          clearedColumns: 1,
          combo: 3,
          streak: 2,
          isSprint: true,
        );

        expect(
          result.placementPoints +
              result.linePoints +
              result.comboBonus +
              result.streakBonus,
          result.points,
        );
      });
    });
  });

  group('ClearTier', () {
    test('line sayısından kademe', () {
      expect(ClearTier.of(0), ClearTier.none);
      expect(ClearTier.of(1), ClearTier.single);
      expect(ClearTier.of(2), ClearTier.double);
      expect(ClearTier.of(3), ClearTier.triple);
      expect(ClearTier.of(4), ClearTier.mega);
      expect(ClearTier.of(9), ClearTier.mega);
    });

    test('şiddet kademeyle artar', () {
      expect(ClearTier.none.intensity, 0);
      expect(ClearTier.mega.intensity, greaterThan(ClearTier.single.intensity));
    });

    test('her kademenin bir etiket kaydı var', () {
      for (final tier in ClearTier.values) {
        expect(kClearTierLabels.containsKey(tier), isTrue, reason: tier.name);
      }
    });
  });

  group('JourneyRules', () {
    test('temizlik yoksa saniye kazancı yok', () {
      expect(
        JourneyRules.secondsFor(tier: ClearTier.none, combo: 9, streak: 9),
        0,
      );
    });

    test('kademe büyüdükçe kazanç artar', () {
      final single = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: 1,
        streak: 0,
      );
      final mega = JourneyRules.secondsFor(
        tier: ClearTier.mega,
        combo: 1,
        streak: 0,
      );
      expect(mega, greaterThan(single));
    });

    test('combo bonusu eşiğin altında verilmez', () {
      final below = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: JourneyRules.comboBonusStartsAt - 1,
        streak: 0,
      );
      final atThreshold = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: JourneyRules.comboBonusStartsAt,
        streak: 0,
      );

      expect(below, JourneyRules.secondsPerTier[ClearTier.single]);
      expect(atThreshold, below + 1);
    });

    test('combo ve streak bonusları tavanda durur', () {
      final maxed = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: 99,
        streak: 99,
      );

      expect(
        maxed,
        JourneyRules.secondsPerTier[ClearTier.single]! +
            JourneyRules.comboBonusCap +
            JourneyRules.streakBonusCap,
      );
    });
  });
}
