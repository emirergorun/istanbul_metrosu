import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

MergeDropController controllerFor({int seed = 1}) {
  return MergeDropController(
    journey: shortJourney(),
    recordToBeat: 0,
    random: Random(seed),
  )..start();
}

void main() {
  group('hat düşür', () {
    test('drop aktif rozeti oyun alanına ekler', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      final accepted = controller.drop();

      expect(accepted, isTrue);
      expect(controller.balls, hasLength(1));
    });

    test('iki M1 temas edince M2 olur', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 1, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 1, x: 0.52, y: 0.7),
      ]);

      controller.debugStep(0.01);

      expect(controller.balls, hasLength(1));
      expect(controller.balls.single.level, 2);
      expect(controller.balls.single.label, 'M2');
      expect(controller.merges, 1);
    });

    test('iki M6 temas edince M7 olur', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 6, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 6, x: 0.52, y: 0.7),
      ]);

      controller.debugStep(0.01);

      expect(controller.balls, hasLength(1));
      expect(controller.balls.single.level, mergeDropMaxLevel);
      expect(controller.balls.single.label, 'M7');
      expect(controller.maxLabel, 'M7');
    });

    test('iki M3 temas edince M4 olur', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 3, x: 0.58, y: 0.7),
      ]);

      controller.debugStep(0.01);

      expect(controller.balls, hasLength(1));
      expect(controller.balls.single.level, 4);
      expect(controller.balls.single.label, 'M4');
    });

    test('zemindeki rozet sekmeden sakinleşir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final radius = mergeDropRadiusForLevel(2);
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 2, x: 0.5, y: 1 - radius, vx: 0.01, vy: 0.4),
      ]);

      controller.debugStep(0.05);

      expect(controller.balls.single.y, closeTo(1 - radius, 0.0001));
      expect(controller.balls.single.vy, 0);
    });

    test('M7 en büyük seviye olduğu için birleşmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 7, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 7, x: 0.52, y: 0.7),
      ]);

      controller.debugStep(0.01);

      expect(controller.balls, hasLength(2));
      expect(controller.merges, 0);
    });
  });
}
