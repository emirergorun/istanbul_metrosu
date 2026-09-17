import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/utils/formatters.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/clear_result.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/combo.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/streak.dart';
import 'package:istanbul_metro_game/features/journey/models/station_progress.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

/// Yüksek skor ve uzun koşu dayanıklılığı.
///
/// Combo payı ve streak bonusu geldikten sonra sayılar eskisinden hızlı
/// büyüyor. Bu testler büyümenin bir yeri **bozmadığını** kontrol ediyor:
/// çarpanların tavanda durduğunu, skorun geri gitmediğini, durak sayısının
/// taşmadığını ve uzun bir koşunun sonuna kadar tutarlı kaldığını.
void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  group('çarpan tavanları', () {
    test('combo ne kadar büyürse büyüsün çarpan tavanı aşmaz', () {
      for (final combo in <int>[10, 100, 10000, 1 << 30]) {
        final result = calculateScore(
          placedCells: 1,
          clearedRows: 1,
          clearedColumns: 0,
          combo: combo,
        );
        expect(result.multiplier, ScoreRules.comboMaxMultiplier);
        expect(result.points, greaterThan(0));
      }
    });

    test('streak bonusu tavanda sabitlenir', () {
      final capped = calculateScore(
        placedCells: 0,
        clearedRows: 1,
        clearedColumns: 0,
        combo: 1,
        streak: ScoreRules.streakMaxLevel,
      );
      for (final streak in <int>[50, 5000, 1 << 30]) {
        final result = calculateScore(
          placedCells: 0,
          clearedRows: 1,
          clearedColumns: 0,
          combo: 1,
          streak: streak,
        );
        expect(result.streakBonus, capped.streakBonus);
      }
    });

    test('yolculuk kazancı hamle başına tavanlıdır', () {
      var maxGain = 0;
      for (final tier in ClearTier.values) {
        for (final combo in <int>[0, 5, 50, 100000]) {
          for (final streak in <int>[0, 5, 50, 100000]) {
            final gain = JourneyRules.secondsFor(
              tier: tier,
              combo: combo,
              streak: streak,
            );
            expect(gain, greaterThanOrEqualTo(0));
            if (gain > maxGain) maxGain = gain;
          }
        }
      }

      final ceiling =
          JourneyRules.secondsPerTier[ClearTier.mega]! +
          JourneyRules.comboBonusCap +
          JourneyRules.streakBonusCap;
      expect(maxGain, ceiling);
    });

    test('döküm uç değerlerde de toplamla tutarlı', () {
      final result = calculateScore(
        placedCells: 64,
        clearedRows: 8,
        clearedColumns: 8,
        combo: 99999,
        streak: 99999,
        isSprint: true,
      );

      expect(
        result.placementPoints +
            result.linePoints +
            result.comboBonus +
            result.streakBonus,
        result.points,
      );
      expect(result.points, greaterThan(0));
    });
  });

  group('sayaçlar taşmaz', () {
    test('combo binlerce hamlede de tutarlı kalır', () {
      var combo = const ComboState();
      for (var i = 0; i < 5000; i++) {
        combo = combo.register(didClear: true);
      }
      expect(combo.value, 5000);
      expect(combo.best, 5000);
      expect(combo.movesSinceLastClear, 0);

      // Pay aşılınca en yüksek değer korunarak sıfırlanır.
      for (var i = 0; i <= ScoreRules.comboGraceMoves; i++) {
        combo = combo.register(didClear: false);
      }
      expect(combo.value, 0);
      expect(combo.best, 5000);
    });

    test('streak binlerce tepside de tutarlı kalır', () {
      var streak = const StreakState();
      for (var i = 0; i < 3000; i++) {
        streak = streak.register(didClear: true);
      }
      expect(streak.value, greaterThan(0));
      expect(streak.best, streak.value);
      expect(streak.piecesInSet, lessThan(3));
    });

    test('skor biçimlendirme büyük sayılarda bozulmaz', () {
      expect(Formatters.score(0), '0');
      expect(Formatters.score(999), '999');
      expect(Formatters.score(1000), '1.000');
      expect(Formatters.score(1234567), '1.234.567');
      expect(Formatters.score(1000000000), '1.000.000.000');
    });
  });

  group('uzun koşu', () {
    test('maraton rotada oyun sonuna kadar tutarlı kalır', () {
      // M4 uçtan uca: en uzun rota, en çok durak.
      final journey = routes
          .estimate('m4_kadikoy', 'm4_sabiha_gokcen_havalimani')
          .journey!;
      final controller = GameController(
        journey: journey,
        generator: PieceGenerator(random: Random(11)),
        tick: const Duration(days: 1),
      )..start();
      addTearDown(controller.dispose);

      var previousScore = 0;
      var previousStations = 0;
      var moves = 0;

      while (controller.status == GameStatus.playing && moves < 4000) {
        // Zaman da aksın; durak geçişleri ve varış gerçekten tetiklensin.
        controller.debugAdvanceSeconds(4);
        if (controller.status != GameStatus.playing) break;

        final board = controller.session.board;
        var placed = false;
        for (var i = 0; i < controller.tray.length && !placed; i++) {
          final piece = controller.tray[i];
          if (piece == null) continue;
          final spot = findFirstLegalPosition(board, piece);
          if (spot == null) continue;
          controller.place(i, spot.row, spot.col);
          placed = true;
          moves++;
        }
        if (!placed) {
          // Hamle kalmadı. Hak varsa oyun hemen bitmez, geri alma teklif
          // edilir; bu koşuda teklif reddedilir ve oyun kapanır.
          if (controller.awaitingUndo) controller.acceptGameOver();
          break;
        }

        final session = controller.session;

        expect(
          controller.score,
          greaterThanOrEqualTo(previousScore),
          reason: 'skor hiçbir hamlede geri gitmemeli',
        );
        expect(
          controller.stationsPassed,
          greaterThanOrEqualTo(previousStations),
          reason: 'geçilen durak sayısı azalamaz',
        );
        expect(
          controller.stationsPassed,
          lessThanOrEqualTo(journey.stopCount),
          reason: 'durak sayısı rotanın durak sayısını aşamaz',
        );
        expect(controller.progress, inInclusiveRange(0.0, 1.0));
        expect(controller.remainingSeconds, greaterThanOrEqualTo(0));
        expect(session.combo, greaterThanOrEqualTo(0));
        expect(session.bestCombo, greaterThanOrEqualTo(session.combo));
        expect(session.bestStreak, greaterThanOrEqualTo(session.streak));

        previousScore = controller.score;
        previousStations = controller.stationsPassed;
      }

      expect(moves, greaterThan(20), reason: 'koşu anlamlı uzunlukta olmalı');
      expect(
        controller.status.isFinished,
        isTrue,
        reason: 'koşu ya varışla ya hamle bitişiyle kapanmalı',
      );

      // Rekorlar koşunun kendi sayılarıyla tutarlı.
      final session = controller.session;
      expect(session.bestCombo, greaterThanOrEqualTo(0));
      expect(session.bestStreak, greaterThanOrEqualTo(0));
      expect(controller.stationsPassed, lessThanOrEqualTo(journey.stopCount));
    });

    test('varıştan sonra durak ilerlemesi son durakta kalır', () {
      final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
      final stations = metro.stationsOfLine(journey.lineId);

      // Yolculuk bonusu süreyi tahmini sürenin üstüne taşıyabilir.
      for (final overshoot in <double>[1.0, 1.5, 4.0]) {
        final progress = stationProgressFor(
          journey: journey,
          lineStations: stations,
          progress: overshoot,
        )!;

        expect(progress.stationsPassed, journey.stopCount);
        expect(progress.departed.id, journey.destination.id);
        expect(progress.approaching, isNull);
      }
    });
  });
}
