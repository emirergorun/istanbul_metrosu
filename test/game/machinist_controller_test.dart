import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/machinist/application/machinist_controller.dart';
import 'package:istanbul_metro_game/features/games/machinist/domain/machinist_rules.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey longJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_yenikapi', 'm2_hacıosman').journey ??
      service.estimate('m2_taksim', 'm2_levent').journey!;
}

MachinistController controllerFor({int seed = 1}) {
  return MachinistController(
    journey: longJourney(),
    recordToBeat: 0,
    stationNames: const <String>['A', 'B', 'C'],
    random: Random(seed),
    tick: const Duration(hours: 1),
  )..start();
}

/// Frene tam zamanında basan sürücü: tam frende [target] metre sapmayla
/// durmayı hedefler. Tren durunca bırakır.
void driveToStop(MachinistController c, {double target = 0}) {
  final start = c.served + c.misses;
  var moved = false;
  for (var i = 0; i < 20000 && c.served + c.misses == start; i++) {
    // Tren durdu: yanaştı ya da işaretten önce kaldı.
    if (moved && c.speed == 0) break;
    moved = moved || c.speed > 0;
    final d = c.distanceToStop + target;
    final need = MachinistRules.brakingDistance(c.speed) * 1.18;
    if (need >= d - 0.3 && d < 250) {
      c
        ..setThrottle(false)
        ..setBrake(true);
    } else {
      c
        ..setBrake(false)
        ..setThrottle(true);
    }
    c.step(0.016);
  }
  c
    ..setThrottle(false)
    ..setBrake(false);
}

void main() {
  group('Makinist fiziği', () {
    test('gaz treni hızlandırır, azami hızda durur', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setThrottle(true);
      c.step(3);
      expect(c.speed, greaterThan(2));
      c.step(60);
      expect(c.speed, lessThanOrEqualTo(MachinistRules.maxSpeed));
    });

    test('fren treni durdurur; geri gitmez', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setThrottle(true);
      c.step(8);
      c
        ..setThrottle(false)
        ..setBrake(true);
      final at = c.position;
      c.step(20);
      expect(c.speed, 0);
      expect(c.position, greaterThanOrEqualTo(at));
    });

    test('iki pedal birden: fren kazanır', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setThrottle(true);
      c.step(6);
      final v = c.speed;
      c.setBrake(true);
      c.step(1);
      expect(c.speed, lessThan(v));
    });
  });

  group('Makinist kumanda kolu', () {
    test('kol yukarıda çeker, ortada boşta, aşağıda frenler', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setLever(1);
      c.step(6);
      final cruising = c.speed;
      expect(cruising, greaterThan(2));
      c.setLever(0);
      c.step(1);
      // Boşta: yalnız sürtünme, hız çok az düşer.
      expect(c.speed, lessThan(cruising + 0.5));
      expect(c.speed, greaterThan(cruising - 1));
      c.setLever(-1);
      c.step(20);
      expect(c.speed, 0);
    });

    test('yarım çekiş tam çekişten yavaş hızlandırır', () {
      final half = controllerFor()..setLever(0.5);
      final full = controllerFor()..setLever(1);
      addTearDown(half.dispose);
      addTearDown(full.dispose);
      half.step(5);
      full.step(5);
      expect(half.speed, lessThan(full.speed));
      expect(half.speed, greaterThan(0));
    });

    test('kademe adımları P4 ile B4 arasında kalır', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      for (var i = 0; i < 9; i++) {
        c.stepLever(1);
      }
      expect(c.leverNotch, MachinistRules.leverNotches);
      for (var i = 0; i < 20; i++) {
        c.stepLever(-1);
      }
      expect(c.leverNotch, -MachinistRules.leverNotches);
      expect(c.braking, isTrue);
    });

    test('yeniden başlatma kolu boşa alır', () {
      final c = controllerFor()..setLever(0.75);
      addTearDown(c.dispose);
      c.restart();
      expect(c.lever, 0);
    });
  });

  group('Makinist durakları', () {
    test('işarette duran tren yolcu alır ve puan yazar', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      driveToStop(c);
      expect(c.served, 1);
      expect(c.misses, 0);
      expect(c.lastResult!.grade, isNotNull);
      expect(c.lastResult!.error.abs(), lessThan(MachinistRules.stopTolerance));
      expect(c.score, greaterThan(0));
      expect(c.isDwelling, isTrue);
      expect(c.passengersTotal, greaterThan(0));
    });

    test('kapı döngüsünde gaz tutmaz, döngü bitince kalkar', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      driveToStop(c);
      c.setThrottle(true);
      c.step(1);
      expect(c.speed, 0);
      expect(c.doorOpen, greaterThan(0));
      c.step(MachinistRules.dwellSeconds);
      expect(c.isDwelling, isFalse);
      c.step(2);
      expect(c.speed, greaterThan(0));
    });

    test('işareti geçen tren durağı kaçırır', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setThrottle(true);
      while (c.misses == 0 && c.served == 0) {
        c.step(0.1);
      }
      expect(c.misses, 1);
      expect(c.lastResult!.missed, isTrue);
      expect(c.status, GameStatus.playing);
    });

    test('üç kaçırılan durakta oyun biter', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.setThrottle(true);
      while (c.status == GameStatus.playing) {
        c.step(0.1);
      }
      expect(c.misses, MachinistRules.maxMisses);
      expect(c.status, GameStatus.gameOver);
    });

    test('erken duran tren ipucu alır, ilerleyip yanaşabilir', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      driveToStop(c, target: -25);
      expect(c.served, 0);
      expect(c.misses, 0);
      expect(c.hintPulse, 1);
      driveToStop(c);
      expect(c.served, 1);
    });

    test('3-2-1 sayacı mesafeyle ilerler', () {
      expect(MachinistRules.countdownFor(400), isNull);
      expect(MachinistRules.countdownFor(140), 3);
      expect(MachinistRules.countdownFor(60), 2);
      expect(MachinistRules.countdownFor(20), 1);
      expect(MachinistRules.countdownFor(2), 0);
    });

    test('duruş notu sapmayla düşer', () {
      expect(StopGrade.forError(0.3), StopGrade.perfect);
      expect(StopGrade.forError(-1.2), StopGrade.great);
      expect(StopGrade.forError(2.5), StopGrade.good);
      expect(StopGrade.forError(-5), StopGrade.fair);
      expect(StopGrade.forError(7), isNull);
    });

    test('yeniden başlatma treni ilk istasyona koyar', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      driveToStop(c);
      c.restart();
      expect(c.position, 0);
      expect(c.served, 0);
      expect(c.target.index, 1);
    });

    test('istasyon adları hat sonunda geri döner', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      final names = c.stations.map((s) => s.name).take(4).toList();
      expect(names, <String>['A', 'B', 'C', 'B']);
    });
  });
}
