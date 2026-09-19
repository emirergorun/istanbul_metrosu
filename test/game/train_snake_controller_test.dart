import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/train_snake/application/train_snake_controller.dart';
import 'package:istanbul_metro_game/features/games/train_snake/domain/train_snake_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

TrainSnakeController controllerFor({int seed = 1}) {
  return TrainSnakeController(
    journey: shortJourney(),
    recordToBeat: 0,
    random: Random(seed),
    tick: const Duration(hours: 1),
  )..start();
}

void main() {
  group('yolcu topla', () {
    test('M1 treniyle, üç vagonla başlar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      expect(controller.lineLabel, 'M1');
      expect(controller.level, 1);
      expect(controller.body, hasLength(trainSnakeStartLength));
      expect(controller.passengersCollected, 0);
    });

    test('yolcuyu toplayınca vagon uzar ve skor artar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(5, 8),
        Point<int>(4, 8),
        Point<int>(3, 8),
      ], direction: SnakeDirection.right);
      final lengthBefore = controller.body.length;
      controller.debugSetPassenger(const Point<int>(6, 8));

      controller.step();

      expect(controller.passengersCollected, 1);
      expect(controller.body.length, lengthBefore + 1);
      expect(controller.body.first, const Point<int>(6, 8));
      expect(controller.score, greaterThan(0));
    });

    test('yolcu yoksa kuyruk ilerler, uzunluk değişmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(5, 8),
        Point<int>(4, 8),
        Point<int>(3, 8),
      ], direction: SnakeDirection.right);
      // Yolcuyu uzağa koy ki bu adımda toplanmasın.
      controller.debugSetPassenger(const Point<int>(9, 9));
      final lengthBefore = controller.body.length;

      controller.step();

      expect(controller.body.length, lengthBefore);
      expect(controller.body.first, const Point<int>(6, 8));
    });

    test('3 yolcu toplayınca M2 hattına geçer', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(3, 8),
        Point<int>(2, 8),
        Point<int>(1, 8),
      ], direction: SnakeDirection.right);

      for (var i = 0; i < 3; i++) {
        final headX = controller.body.first.x;
        controller.debugSetPassenger(Point<int>(headX + 1, 8));
        controller.step();
      }

      expect(controller.passengersCollected, 3);
      expect(controller.level, 2);
      expect(controller.lineLabel, 'M2');
    });

    test('yön kuyruklanır, bir sonraki adımda uygulanır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(5, 8),
        Point<int>(4, 8),
        Point<int>(3, 8),
      ], direction: SnakeDirection.right);
      controller.debugSetPassenger(const Point<int>(9, 9));

      controller.turn(SnakeDirection.down);
      controller.step();

      expect(controller.body.first, const Point<int>(5, 9));
    });

    test('tam ters yöne dönüş kendi boynuna çarpmayı önlemek için yok sayılır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(5, 8),
        Point<int>(4, 8),
        Point<int>(3, 8),
      ], direction: SnakeDirection.right);
      controller.debugSetPassenger(const Point<int>(9, 9));

      // Sağa giderken sola dönmek anında geriye, kendi boynuna gitmek
      // demektir — istek yok sayılmalı, tren sağa devam etmeli.
      controller.turn(SnakeDirection.left);
      controller.step();

      expect(controller.body.first, const Point<int>(6, 8));
    });

    test('sol duvara çarpınca oyun biter (ekranın diğer ucuna çıkmaz)', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBody(const <Point<int>>[
        Point<int>(0, 8),
        Point<int>(1, 8),
        Point<int>(2, 8),
      ], direction: SnakeDirection.left);
      controller.debugSetPassenger(const Point<int>(9, 9));

      controller.step();

      expect(controller.status, GameStatus.gameOver);
    });

    test('sağ/alt/üst duvara çarpınca da oyun biter', () {
      final rightWall = controllerFor()
        ..debugSetBody(<Point<int>>[
          Point<int>(trainSnakeColumns - 1, 8),
          Point<int>(trainSnakeColumns - 2, 8),
          Point<int>(trainSnakeColumns - 3, 8),
        ], direction: SnakeDirection.right)
        ..debugSetPassenger(const Point<int>(0, 0));
      addTearDown(rightWall.dispose);
      rightWall.step();
      expect(rightWall.status, GameStatus.gameOver);

      final topWall = controllerFor()
        ..debugSetBody(const <Point<int>>[
          Point<int>(5, 0),
          Point<int>(5, 1),
          Point<int>(5, 2),
        ], direction: SnakeDirection.up)
        ..debugSetPassenger(const Point<int>(0, 0));
      addTearDown(topWall.dispose);
      topWall.step();
      expect(topWall.status, GameStatus.gameOver);

      final bottomWall = controllerFor()
        ..debugSetBody(<Point<int>>[
          Point<int>(5, trainSnakeRows - 1),
          Point<int>(5, trainSnakeRows - 2),
          Point<int>(5, trainSnakeRows - 3),
        ], direction: SnakeDirection.down)
        ..debugSetPassenger(const Point<int>(0, 0));
      addTearDown(bottomWall.dispose);
      bottomWall.step();
      expect(bottomWall.status, GameStatus.gameOver);
    });

    test('kendi vagonuna çarpınca oyun biter', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      // Halka biçiminde bir gövde: sola dönünce baş kendi gövdesine gider.
      controller.debugSetBody(const <Point<int>>[
        Point<int>(2, 2),
        Point<int>(2, 1),
        Point<int>(1, 1),
        Point<int>(1, 2),
        Point<int>(1, 3),
      ], direction: SnakeDirection.left);
      controller.debugSetPassenger(const Point<int>(9, 9));

      controller.step();

      expect(controller.status, GameStatus.gameOver);
    });

    test('kuyruğun az önce boşalttığı hücreye girmek çarpışma sayılmaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      // 4 hücrelik bir halka: baş sola dönünce tam da kuyruğun durduğu
      // hücreye gider. Kuyruk aynı adımda oradan ayrılacağı için bu,
      // klasik yılan kuralı gereği çarpışma sayılmaz.
      controller.debugSetBody(const <Point<int>>[
        Point<int>(2, 2),
        Point<int>(2, 1),
        Point<int>(1, 1),
        Point<int>(1, 2),
      ], direction: SnakeDirection.left);
      controller.debugSetPassenger(const Point<int>(9, 9));

      controller.step();

      expect(controller.status, isNot(GameStatus.gameOver));
      expect(controller.body.first, const Point<int>(1, 2));
    });

    test('M11 üzerinde seviye sabitlenir, oyun bitmez', () {
      expect(trainSnakeLevelForPassengers(1000), trainSnakeMaxLevel);
      expect(trainSnakeLabelForLevel(trainSnakeMaxLevel), 'M11');
    });
  });

  group('kare zamanlaması', () {
    // Ray Değiştir/Ray Uçuşu'ndaki aynı düzeltmenin burada da uygulandığını
    // doğrular: hız "kaç kere Timer tetiklendi"ye değil ölçülen gerçek
    // süreye bağlı.
    test('ilk ölçüm yalnızca referansı kurar, 0 döner', () {
      final controller = TrainSnakeController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);

      expect(controller.debugElapsedSecondsSince(DateTime(2026)), 0);
    });

    test('uzun bir donma tek adımda dev bir sıçramaya izin vermez', () {
      final controller = TrainSnakeController(
        journey: shortJourney(),
        recordToBeat: 0,
        random: Random(1),
      );
      addTearDown(controller.dispose);
      final t0 = DateTime(2026);
      controller.debugElapsedSecondsSince(t0);

      final t1 = t0.add(const Duration(seconds: 2));
      final dt = controller.debugElapsedSecondsSince(t1);

      expect(dt, lessThanOrEqualTo(0.05));
    });
  });
}
