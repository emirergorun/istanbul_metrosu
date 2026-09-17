import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/clear_result.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

/// İyi oyun trenin hızını artırır.
///
/// Ürünün vaadi değişmedi: yolculuk hâlâ gerçek rotanın süresi kadar ve tek
/// final varış. Değişen şu — temizlik, combo ve streak yolculuğa saniye
/// katar, yani iyi oynayan oyuncu daha erken varır. Bu testler kuralın üç
/// sınırını koruyor: kazanç verilir, geri alma kazancı geri alır, kazanç
/// oyuncuya fazladan hamle vermez.
void main() {
  final routeService = RouteService(MetroFixture.load());

  Journey longJourney() =>
      routeService.estimate('m2_yenikapi', 'm2_haciosman').journey!;

  /// Son satırı tek hücre eksik bırakılmış tahta; tepside tek bir `dot`.
  ///
  /// Böylece bir sonraki hamlenin satırı tamamlayacağı kesindir ve test
  /// rastgele parçaya bağlı kalmaz.
  GameSession sessionOneCellFromClear(Journey journey) {
    final grid = List<List<int>>.generate(
      8,
      (_) => List<int>.filled(8, kEmptyCell),
    );
    for (var c = 0; c < 7; c++) {
      grid[7][c] = 1;
    }

    final dot = PieceShapes.byId('dot')!.withColor(1);
    return GameSession.initial(
      journey: journey,
      board: Board.fromGrid(grid),
      tray: <BlockPiece?>[dot, null, null],
    );
  }

  GameController controllerWith(GameSession session, {int elapsed = 0}) =>
      GameController(
        journey: session.journey,
        generator: PieceGenerator(random: Random(3)),
        // Gerçek zamanlayıcı testte çalışmasın; süre yalnızca hamlelerle
        // artsın.
        tick: const Duration(days: 1),
        resumeFrom: session,
        resumeProgress: ResumedProgress(
          score: 0,
          elapsedSeconds: elapsed,
          stationsPassed: 0,
          recordToBeat: 0,
          recordBeaten: false,
        ),
      );

  group('yolculuk kazancı', () {
    test('satır temizleyen hamle yolculuğa saniye katar', () {
      final journey = longJourney();
      final controller = controllerWith(sessionOneCellFromClear(journey))
        ..start();
      addTearDown(controller.dispose);

      final before = controller.elapsedSeconds;
      final outcome = controller.place(0, 7, 7);

      expect(outcome.didClear, isTrue);
      expect(outcome.tier, ClearTier.single);
      expect(
        outcome.journeySeconds,
        JourneyRules.secondsPerTier[ClearTier.single],
      );
      expect(controller.elapsedSeconds, before + outcome.journeySeconds);
    });

    test('temizlemeyen hamle süreye dokunmaz', () {
      final journey = longJourney();
      final controller = controllerWith(sessionOneCellFromClear(journey))
        ..start();
      addTearDown(controller.dispose);

      final before = controller.elapsedSeconds;
      // Satırı tamamlamayan bir yere koy.
      final outcome = controller.place(0, 0, 0);

      expect(outcome.didClear, isFalse);
      expect(outcome.journeySeconds, 0);
      expect(controller.elapsedSeconds, before);
    });

    test('geri alma kazanılan saniyeyi geri verir', () {
      final journey = longJourney();
      final controller = controllerWith(sessionOneCellFromClear(journey))
        ..start();
      addTearDown(controller.dispose);

      final before = controller.elapsedSeconds;
      final outcome = controller.place(0, 7, 7);
      expect(outcome.journeySeconds, greaterThan(0));

      expect(controller.undo(), isTrue);
      expect(
        controller.elapsedSeconds,
        before,
        reason: 'temizle-geri al döngüsü bedava zaman kazandırmamalı',
      );
    });

    test('geri alma yalnızca hamlenin kazancını siler, saati geri sarmaz', () {
      final journey = longJourney();
      final controller = controllerWith(
        sessionOneCellFromClear(journey),
        elapsed: 100,
      )..start();
      addTearDown(controller.dispose);

      controller.place(0, 7, 7);
      controller.undo();

      expect(controller.elapsedSeconds, 100);
    });

    test('art arda temizlik kazancı büyütür', () {
      final journey = longJourney();

      final single = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: 1,
        streak: 0,
      );
      final withCombo = JourneyRules.secondsFor(
        tier: ClearTier.single,
        combo: JourneyRules.comboBonusStartsAt,
        streak: 0,
      );

      expect(withCombo, greaterThan(single));
      expect(journey.estimatedSeconds, greaterThan(0));
    });
  });

  group('ClearResult', () {
    test('satır + sütun aynı hamlede: eşzamanlı işaretlenir', () {
      const result = ClearResult(
        clearedRows: <int>[3],
        clearedColumns: <int>[5],
        clearedCellValues: <int, int>{},
        comboIndex: 2,
        streakIndex: 1,
        scoreAwarded: 90,
        journeySecondsAwarded: 2,
      );

      expect(result.simultaneousClear, isTrue);
      expect(result.totalLines, 2);
      expect(result.tier, ClearTier.double);
    });

    test('yalnız satır temizliği eşzamanlı sayılmaz', () {
      const result = ClearResult(
        clearedRows: <int>[1, 2],
        clearedColumns: <int>[],
        clearedCellValues: <int, int>{},
        comboIndex: 1,
        streakIndex: 0,
        scoreAwarded: 50,
        journeySecondsAwarded: 2,
      );

      expect(result.simultaneousClear, isFalse);
      expect(result.tier, ClearTier.double);
    });

    test('temizliksiz sonuç boş', () {
      const result = ClearResult.none(
        comboIndex: 0,
        streakIndex: 0,
        scoreAwarded: 4,
      );

      expect(result.didClear, isFalse);
      expect(result.tier, ClearTier.none);
      expect(result.journeySecondsAwarded, 0);
      expect(result.clearedCellCount, 0);
    });
  });
}
