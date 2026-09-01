import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/application/rail_flight_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/domain/rail_flight_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

RailFlightController controllerFor({int seed = 1}) {
  return RailFlightController(
    journey: shortJourney(),
    recordToBeat: 0,
    random: Random(seed),
  )..start();
}

List<RailObstacle> passedObstacles(int count) {
  return List<RailObstacle>.generate(
    count,
    (_) => const RailObstacle(
      x: railFlightTrainX - railFlightObstacleWidth - 0.02,
      gapCenter: 0.5,
      gapHeight: 0.34,
    ),
  );
}

void main() {
  group('ray uçuşu', () {
    test('flap treni yukarı ivmelendirir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      controller.flap();

      expect(controller.velocity, lessThan(0));
    });

    test('engel geçmek skoru artırır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetFlight(
        trainY: 0.5,
        velocity: 0,
        obstacles: passedObstacles(1),
      );

      controller.debugStep(0.01);

      expect(controller.gatesPassed, 1);
      expect(controller.score, 1);
    });

    test('5 geçişten sonra M2 trenine dönüşür', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetFlight(
        trainY: 0.5,
        velocity: 0,
        obstacles: passedObstacles(5),
      );

      controller.debugStep(0.01);

      expect(controller.gatesPassed, 5);
      expect(controller.lineLabel, 'M2');
      expect(controller.lineLevel, 2);
    });

    test('10 geçişten sonra M3 trenine dönüşür', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetFlight(
        trainY: 0.5,
        velocity: 0,
        obstacles: passedObstacles(10),
      );

      controller.debugStep(0.01);

      expect(controller.gatesPassed, 10);
      expect(controller.lineLabel, 'M3');
      expect(controller.lineLevel, 3);
    });

    test(
      '45 geçişten sonra M11 trenine dönüşür (son hat, artık ilerlemez)',
      () {
        final controller = controllerFor();
        addTearDown(controller.dispose);
        controller.debugSetFlight(
          trainY: 0.5,
          velocity: 0,
          obstacles: passedObstacles(45),
        );

        controller.debugStep(0.01);

        expect(controller.gatesPassed, 45);
        expect(controller.lineLabel, 'M11');
        expect(controller.lineLevel, 10);
      },
    );

    test('ray sınırına çarpmak oyunu bitirir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetFlight(trainY: 0.01, velocity: 0);

      controller.debugStep(0.01);

      expect(controller.status, GameStatus.gameOver);
    });
  });
}
