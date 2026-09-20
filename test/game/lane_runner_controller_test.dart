import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/application/lane_runner_controller.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/domain/lane_runner_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

LaneRunnerController controllerFor({int seed = 1}) {
  return LaneRunnerController(
    journey: shortJourney(),
    recordToBeat: 0,
    random: Random(seed),
    tick: const Duration(hours: 1),
  )..start();
}

List<LaneObstacle> passedObstacles(int count) {
  return List<LaneObstacle>.generate(
    count,
    (index) => LaneObstacle(id: index, lane: 0, y: laneRunnerTrainY + 0.09),
  );
}

void main() {
  group('ray değiştir', () {
    test('sağ ve sol ray değiştirme çalışır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      expect(controller.trainLane, 1);

      controller.moveRight();
      expect(controller.trainLane, 2);

      controller.moveLeft();
      expect(controller.trainLane, 1);
    });

    test('engel geçmek skoru artırır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      // Altı engel: ortak para biriminde tek bir geçiş bir puandan az
      // ediyor (oyun saniyede birkaç engel geçiriyor), kesirler birikince
      // skora yazılıyor.
      controller.debugSetObstacles(passedObstacles(6));

      controller.step();

      expect(controller.passes, 6);
      expect(controller.score, greaterThan(0));
    });

    test('çarpışma oyunu bitirir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetTrainLane(1);
      controller.debugSetObstacles(const <LaneObstacle>[
        LaneObstacle(id: 1, lane: 1, y: laneRunnerTrainY - 0.01),
      ]);

      controller.step();

      expect(controller.status, GameStatus.gameOver);
    });

    test('7 geçişten sonra M2 trenine dönüşür', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetObstacles(passedObstacles(7));

      controller.step();

      expect(controller.passes, 7);
      expect(controller.lineLabel, 'M2');
      expect(controller.lineLevel, 2);
    });

    test('ray değişimi anında ışınlanmaz, hedefe doğru yumuşak kayar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      controller.moveRight();
      expect(controller.trainLane, 2);
      // Hedef anında güncellenir ama görsel konum henüz oraya varmamış
      // olmalı — bu, "smooth değil" şikayetinin ana sebebiydi.
      expect(controller.trainLaneVisual, 1.0);

      controller.step();
      expect(controller.trainLaneVisual, greaterThan(1));
      expect(controller.trainLaneVisual, lessThan(2));

      for (var i = 0; i < 60; i++) {
        controller.step();
      }
      expect(controller.trainLaneVisual, closeTo(2, 0.01));
    });
  });

  group('kare zamanlaması', () {
    // Bu grup, Ray Uçuşu'nda uygulanan aynı düzeltmenin (gerçek geçen
    // süreyi ölçme, sabit-dt varsaymama) Ray Değiştir'e de uygulandığını
    // doğruluyor. Eskiden hız tamamen "kaç kere Timer tetiklendi"ye
    // bağlıydı — telefonda zamanlayıcı gerçek zamandan saptığında oyun
    // akışı düzensizleşiyordu.

    test('ilk ölçüm yalnızca referansı kurar, 0 döner', () {
      final controller = LaneRunnerController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);

      expect(controller.debugElapsedSecondsSince(DateTime(2026)), 0);
    });

    test('gecikmeli bir tik, sabit 16ms değil gerçek geçen süreyi döner', () {
      final controller = LaneRunnerController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      final t1 = t0.add(const Duration(milliseconds: 30));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(dt, closeTo(0.03, 0.001));
    });

    test('uzun bir donma tek adımda dev bir sıçramaya izin vermez', () {
      final controller = LaneRunnerController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      final t1 = t0.add(const Duration(seconds: 2));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(
        dt,
        lessThanOrEqualTo(0.05),
        reason:
            'kırpma olmasa engel bir karede çarpışma penceresini atlayıp '
            '"içinden geçebilirdi"',
      );
    });
  });
}
