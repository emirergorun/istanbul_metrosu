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

    test('45 geçişten sonra M11 trenine dönüşür (son hat, artık ilerlemez)', () {
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
    });

    test('ray sınırına çarpmak oyunu bitirir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetFlight(trainY: 0.01, velocity: 0);

      controller.debugStep(0.01);

      expect(controller.status, GameStatus.gameOver);
    });
  });

  group('kare zamanlaması', () {
    // Bu grup, fiziğin her Timer tetiklenişinde "tam olarak 16ms geçti"
    // varsaymak yerine gerçekte ne kadar süre geçtiğini ölçtüğünü
    // doğruluyor. Telefonlarda zamanlayıcı gerçek zamandan sapabiliyor
    // (arka plan kısıtlaması, GC duraklaması); sabit-dt varsayımı akışın
    // düzensiz/sarsıntılı görünmesine yol açan asıl sebepti.

    test('ilk ölçüm yalnızca referansı kurar, 0 döner', () {
      final controller = RailFlightController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);

      expect(controller.debugElapsedSecondsSince(DateTime(2026)), 0);
    });

    test('gecikmeli bir tik, sabit 16ms değil gerçek geçen süreyi döner', () {
      final controller = RailFlightController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      // Zamanlayıcı 30ms gecikmiş olsun (kırpma sınırının altında kalacak
      // kadar küçük — burada kırpma değil, ÖLÇÜMÜN doğruluğu test ediliyor).
      final t1 = t0.add(const Duration(milliseconds: 30));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(
        dt,
        closeTo(0.03, 0.001),
        reason: 'sabit-dt varsayımı burada hep 0.016 dönerdi',
      );
    });

    test('düzenli ~16ms aralıkta ölçülen süre tik hedefine yakın kalır', () {
      final controller = RailFlightController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      final t1 = t0.add(const Duration(milliseconds: 16));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(dt, closeTo(0.016, 0.001));
    });

    test('uzun bir donma tek adımda dev bir fizik sıçramasına izin vermez', () {
      final controller = RailFlightController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      // 2 saniyelik donma (arka plana alınma, GC duraklaması, vb.).
      final t1 = t0.add(const Duration(seconds: 2));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(
        dt,
        lessThanOrEqualTo(0.05),
        reason:
            'kırpma olmasa 2 saniyelik yerçekimi tek karede uygulanır, '
            'tren zeminin/tavanın "içine ışınlanırdı"',
      );
    });
  });
}
