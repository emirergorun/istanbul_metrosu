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
      controller.debugSetObstacles(passedObstacles(1));

      controller.step();

      expect(controller.passes, 1);
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
  });
}
