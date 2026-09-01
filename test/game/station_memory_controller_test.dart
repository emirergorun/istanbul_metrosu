import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/station_memory/application/station_memory_controller.dart';
import 'package:istanbul_metro_game/features/games/station_memory/domain/station_memory_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

StationMemoryController controllerFor({int seed = 1}) {
  return StationMemoryController(
    journey: shortJourney(),
    recordToBeat: 0,
    stationNames: const <String>[
      'Taksim',
      'Osmanbey',
      'Şişli-Mecidiyeköy',
      'Gayrettepe',
      'Levent',
      '4. Levent',
    ],
    random: Random(seed),
    showDuration: const Duration(hours: 1),
  )..start();
}

void main() {
  group('ezberleme süresi', () {
    test('dizi uzadıkça gösterim süresi de uzar', () {
      // Regresyon: süre sabit 1400 ms'ydi. Dizi 3 duraktan 7'ye çıkarken
      // ilk turda oyuncu bekliyor, son turlarda yedi durağı okumaya vakit
      // bulamıyordu.
      final controller = StationMemoryController(
        journey: shortJourney(),
        recordToBeat: 0,
        stationNames: const <String>[
          'Taksim',
          'Osmanbey',
          'Şişli-Mecidiyeköy',
          'Gayrettepe',
          'Levent',
          '4. Levent',
          'Sanayi',
        ],
        random: Random(3),
      )..start();
      addTearDown(controller.dispose);

      final ilkUzunluk = controller.round.sequence.length;
      final ilkSure = controller.currentShowDuration;

      // Turları doğru bilerek dizinin uzamasını sağla.
      for (var i = 0; i < 6; i++) {
        controller.debugFinishShowing();
        for (final station in List<String>.of(controller.round.sequence)) {
          expect(controller.choose(station), isTrue);
        }
      }

      expect(
        controller.round.sequence.length,
        greaterThan(ilkUzunluk),
        reason: 'dizi uzamadı, test anlamsız',
      );
      expect(controller.currentShowDuration, greaterThan(ilkSure));
    });

    test('durak başına süre sabit kalır', () {
      final controller = StationMemoryController(
        journey: shortJourney(),
        recordToBeat: 0,
        stationNames: const <String>[
          'Taksim',
          'Osmanbey',
          'Şişli-Mecidiyeköy',
          'Gayrettepe',
        ],
        random: Random(1),
      )..start();
      addTearDown(controller.dispose);

      final n = controller.round.sequence.length;
      expect(
        controller.currentShowDuration,
        StationMemoryController.showBase +
            StationMemoryController.showPerStation * n,
      );
    });
  });

  group('durak hafıza', () {
    test('gösterimden cevap moduna geçer', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      expect(controller.round.phase, StationMemoryPhase.showing);

      controller.debugFinishShowing();

      expect(controller.round.phase, StationMemoryPhase.answering);
    });

    test('doğru sıra skoru artırır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugFinishShowing();
      final sequence = List<String>.of(controller.round.sequence);

      for (final station in sequence) {
        expect(controller.choose(station), isTrue);
      }

      expect(controller.successes, 1);
      expect(controller.score, greaterThan(0));
      expect(controller.status, GameStatus.playing);
    });

    test('yanlış seçim oyunu bitirir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugFinishShowing();
      final wrong = controller.round.options.firstWhere(
        (station) => station != controller.round.sequence.first,
      );

      expect(controller.choose(wrong), isFalse);

      expect(controller.status, GameStatus.gameOver);
    });

    test('7 başarıdan sonra M2 seviyesine çıkar', () {
      final controller = controllerFor(seed: 4);
      addTearDown(controller.dispose);

      for (var i = 0; i < 7; i++) {
        controller.debugFinishShowing();
        final sequence = List<String>.of(controller.round.sequence);
        for (final station in sequence) {
          expect(controller.choose(station), isTrue);
        }
      }

      expect(controller.successes, 7);
      expect(controller.lineLabel, 'M2');
      expect(controller.lineLevel, 2);
    });
  });
}
