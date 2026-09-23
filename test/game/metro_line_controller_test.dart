import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/metro_line/application/metro_line_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_line/domain/metro_line_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() =>
    RouteService(MetroFixture.load()).estimate('m2_taksim', 'm2_levent').journey!;

MetroLineController controllerFor({int seed = 1}) => MetroLineController(
  journey: shortJourney(),
  recordToBeat: 0,
  random: Random(seed),
)..start();

void main() {
  group('Metro Hattı — üretici', () {
    test('üretilen her bulmaca çözüm sırasıyla tamamen boşalır', () {
      // Oyunun tek güvencesi bu: rastgele ama her zaman çözülebilir.
      for (var seed = 0; seed < 120; seed++) {
        final random = Random(seed);
        final size =
            metroLineMinSize + random.nextInt(metroLineMaxSize - metroLineMinSize + 1);
        final puzzle = generateMetroLinePuzzle(
          size: size,
          desiredTrains: 10,
          random: random,
        );
        expect(puzzle.trains, isNotEmpty, reason: 'tohum $seed: boş bulmaca');
        expect(
          puzzle.solution.length,
          puzzle.trains.length,
          reason: 'tohum $seed: çözüm tüm trenleri kapsamıyor',
        );

        final remaining = List<MetroLineTrain>.of(puzzle.trains);
        for (final id in puzzle.solution) {
          final train = remaining.firstWhere((t) => t.id == id);
          for (final cell in train.corridor(puzzle.size)) {
            final blocker = remaining
                .where((t) => t.id != id && t.cells.contains(cell))
                .toList();
            expect(
              blocker,
              isEmpty,
              reason:
                  'tohum $seed: $id çıkarken koridoru ${blocker.map((t) => t.id)} '
                  'tarafından kapalı',
            );
          }
          remaining.removeWhere((t) => t.id == id);
        }
        expect(remaining, isEmpty, reason: 'tohum $seed: tahta boşalmadı');
      }
    });

    test('trenler üst üste binmez ve tahtanın içinde kalır', () {
      for (var seed = 0; seed < 60; seed++) {
        final puzzle = generateMetroLinePuzzle(
          size: 7,
          desiredTrains: 12,
          random: Random(seed),
        );
        final seen = <Point<int>>{};
        for (final train in puzzle.trains) {
          for (final cell in train.cells) {
            expect(cell.x, inInclusiveRange(0, 6), reason: 'tohum $seed');
            expect(cell.y, inInclusiveRange(0, 6), reason: 'tohum $seed');
            expect(
              seen.add(cell),
              isTrue,
              reason: 'tohum $seed: $cell iki trende birden',
            );
          }
        }
      }
    });

    test('her trenin vagonları uç uca ve kendi koridoruna girmiyor', () {
      for (var seed = 0; seed < 60; seed++) {
        final puzzle = generateMetroLinePuzzle(
          size: 6,
          desiredTrains: 10,
          random: Random(seed),
        );
        for (final train in puzzle.trains) {
          expect(
            train.carCount,
            inInclusiveRange(metroLineMinCars, metroLineMaxCars),
            reason: 'tohum $seed',
          );
          for (var i = 1; i < train.cells.length; i++) {
            final a = train.cells[i - 1];
            final b = train.cells[i];
            expect(
              (a.x - b.x).abs() + (a.y - b.y).abs(),
              1,
              reason: 'tohum $seed: ${train.id} vagonları kopuk',
            );
          }
          // Kendi koridorundan geçen tren çıkarken kendi üstünden geçerdi.
          final corridor = train.corridor(puzzle.size).toSet();
          for (final cell in train.cells) {
            expect(
              corridor.contains(cell),
              isFalse,
              reason: 'tohum $seed: ${train.id} kendi koridorunda',
            );
          }
        }
      }
    });

    test('her trenin başı gittiği yöne bakar', () {
      // Regresyon: üretici başı rastgele çeviriyordu ve trenlerin %62'sinin
      // başı çıkış yönünden başka yana bakıyordu. Ok gövdenin son
      // parçasından türetildiği için yanlış yönü gösteriyor, gövdeye dik
      // düştüğünde de "ok kaybolmuş" gibi okunuyordu.
      for (var seed = 0; seed < 80; seed++) {
        final puzzle = generateMetroLinePuzzle(
          size: 8,
          desiredTrains: 14,
          random: Random(seed),
        );
        for (final train in puzzle.trains) {
          final step = train.direction.delta;
          expect(
            train.cells[1],
            Point<int>(train.head.x - step.x, train.head.y - step.y),
            reason:
                'tohum $seed: ${train.id} başı ${train.direction} yönüne '
                'bakmıyor',
          );
        }
      }
    });

    test('tahta hiçbir sırada kilitlenmez', () {
      // Tren çıkarmak yalnızca yer **açar**, hiçbir koridoru kapatmaz;
      // dolayısıyla oyuncu hangi sırayla oynarsa oynasın çıkarılabilecek
      // bir tren hep kalır. Oyuncu yalnızca yanlış dokunuşla can kaybeder,
      // sıralama hatasıyla tıkanmaz.
      for (var seed = 0; seed < 40; seed++) {
        final controller = controllerFor(seed: seed);
        addTearDown(controller.dispose);
        final random = Random(seed + 500);

        for (var step = 0; step < 40; step++) {
          if (controller.trains.isEmpty) break;
          final options = controller.trains
              .where(controller.canExit)
              .toList();
          expect(
            options,
            isNotEmpty,
            reason: 'tohum $seed: tahta kilitlendi (adım $step)',
          );
          controller.tap(options[random.nextInt(options.length)].id);
        }
      }
    });
  });

  group('Metro Hattı — oynanış', () {
    test('önü açık trene dokunmak onu çıkarır ve puan yazar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      final train = controller.solvableTrain()!;
      final before = controller.score;
      final left = controller.trainsLeft;

      expect(controller.tap(train.id), MetroLineTapResult.cleared);
      expect(controller.trainsLeft, left - 1);
      expect(controller.score, greaterThan(before));
      expect(controller.departing?.id, train.id);
    });

    test('önü kapalı trene dokunmak can götürür, treni çıkarmaz', () {
      final controller = controllerFor(seed: 3);
      addTearDown(controller.dispose);

      // Kapalı bir tren kuralım: A sağa çıkmak istiyor, önünde B duruyor.
      const blocked = MetroLineTrain(
        id: 1,
        cells: <Point<int>>[Point<int>(1, 2), Point<int>(0, 2)],
        direction: MetroLineDirection.right,
        lineIndex: 0,
      );
      const blocker = MetroLineTrain(
        id: 2,
        cells: <Point<int>>[Point<int>(3, 2), Point<int>(3, 3)],
        direction: MetroLineDirection.up,
        lineIndex: 1,
      );
      controller.debugSetPuzzle(
        const MetroLinePuzzle(
          size: 5,
          trains: <MetroLineTrain>[blocked, blocker],
          solution: <int>[2, 1],
        ),
      );

      final hearts = controller.hearts;
      final score = controller.score;

      expect(controller.tap(1), MetroLineTapResult.blocked);
      expect(controller.hearts, hearts - 1);
      expect(controller.trainsLeft, 2);
      expect(controller.score, score);

      // Engel kalkınca aynı tren çıkabilir.
      expect(controller.tap(2), MetroLineTapResult.cleared);
      expect(controller.tap(1), MetroLineTapResult.cleared);
      // Tahta boşaldığı için yeni seviye yüklendi; sayaç sıfırda kalmaz.
      expect(controller.completedLevels, 1);
    });

    test('canlar bitince oyun biter', () {
      final controller = controllerFor(seed: 4);
      addTearDown(controller.dispose);
      controller.debugSetPuzzle(
        const MetroLinePuzzle(
          size: 5,
          trains: <MetroLineTrain>[
            MetroLineTrain(
              id: 1,
              cells: <Point<int>>[Point<int>(1, 2), Point<int>(0, 2)],
              direction: MetroLineDirection.right,
              lineIndex: 0,
            ),
            MetroLineTrain(
              id: 2,
              cells: <Point<int>>[Point<int>(3, 2), Point<int>(3, 3)],
              direction: MetroLineDirection.up,
              lineIndex: 1,
            ),
          ],
          solution: <int>[2, 1],
        ),
      );

      for (var i = 0; i < metroLineHearts; i++) {
        expect(controller.status, GameStatus.playing, reason: 'dokunuş $i');
        controller.tap(1);
      }

      expect(controller.hearts, 0);
      expect(controller.status, GameStatus.gameOver);
    });

    test('tahta boşalınca yeni seviye gelir ve canlar yenilenir', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);
      controller.debugSetHearts(1);

      final level = controller.level;
      var guard = 0;
      while (controller.level == level && guard++ < 200) {
        final next = controller.solvableTrain();
        if (next == null) break;
        controller.tap(next.id);
      }

      expect(controller.level, level + 1);
      expect(controller.completedLevels, 1);
      expect(controller.hearts, metroLineHearts);
      expect(controller.trainsLeft, greaterThan(0));
    });

    test('seviye ilerledikçe tahta büyür', () {
      expect(MetroLineLevelPlan.forLevel(1).size, metroLineMinSize);
      expect(
        MetroLineLevelPlan.forLevel(30).size,
        metroLineMaxSize,
      );
      expect(
        MetroLineLevelPlan.forLevel(7).size,
        greaterThan(MetroLineLevelPlan.forLevel(1).size),
      );
    });

    test('ipucu her zaman çıkabilecek bir tren gösterir', () {
      final controller = controllerFor(seed: 6);
      addTearDown(controller.dispose);

      controller.requestHint();
      final id = controller.hintTrainId;
      expect(id, isNotNull);
      final train = controller.trains.firstWhere((t) => t.id == id);
      expect(controller.canExit(train), isTrue);
    });

    test('duraklatılmış oyunda dokunuş yok sayılır', () {
      final controller = controllerFor(seed: 7);
      addTearDown(controller.dispose);
      final train = controller.solvableTrain()!;
      controller.pause();

      expect(controller.tap(train.id), MetroLineTapResult.ignored);
      expect(controller.trainsLeft, controller.trainsInLevel);
    });
  });
}
