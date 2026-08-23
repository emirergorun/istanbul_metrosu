import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/domain/metro_tile.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

List<List<MetroTile?>> emptyGrid(int size) => List<List<MetroTile?>>.generate(
  size,
  (_) => List<MetroTile?>.filled(size, null),
);

void main() {
  group('hat birleştirme', () {
    test('M1 + M1 sola kayınca M2 olur', () {
      final controller = MetroMergeController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      )..start();
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][0] = const MetroTile(colorIndex: 0, rank: 1);
      grid[0][1] = const MetroTile(colorIndex: 0, rank: 1);
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isTrue);
      expect(outcome.merges, 1);
      expect(controller.grid[0][0]?.lineLabel, 'M2');
      expect(controller.grid[0][0]?.rank, 2);
    });

    test('M2 + M2 sola kayınca M3 olur', () {
      final controller = MetroMergeController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(2),
      )..start();
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][0] = const MetroTile(colorIndex: 0, rank: 2);
      grid[0][1] = const MetroTile(colorIndex: 0, rank: 2);
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isTrue);
      expect(outcome.merges, 1);
      expect(controller.grid[0][0]?.lineLabel, 'M3');
      expect(controller.grid[0][0]?.rank, 3);
    });
  });
}
