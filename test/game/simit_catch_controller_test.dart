import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/simit_catch/application/simit_catch_controller.dart';
import 'package:istanbul_metro_game/features/games/simit_catch/domain/simit_catch_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/journey_points.dart';
import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

SimitCatchController controllerFor({int seed = 1}) {
  return SimitCatchController(
    journey: shortJourney(),
    recordToBeat: 0,
    random: Random(seed),
    // Gerçek zamanlayıcı testte hiç tetiklenmesin; zaman `step` ile akar.
    tick: const Duration(hours: 1),
  )..start();
}

/// Martının önünde [ahead] kadar ileride, [y] yüksekliğinde düz bir simit.
///
/// [scroll] sahnenin o ana kadar aktığı yol: simitler dünya
/// koordinatında duruyor.
Simit simitAt(double ahead, {double y = 0.5, int id = 0, double scroll = 0}) =>
    Simit(
      id: id,
      x: scroll + simitCatchBirdX + ahead,
      y: y,
      halfWidth: SimitCatchConfig.forSimits(0).halfWidth,
      tilt: 0,
    );

/// Kanatsız düşüşün [drop] kadar inmesi için geçen süre (ilk kademe).
double fallSeconds(double drop) =>
    sqrt(2 * drop / SimitCatchConfig.forSimits(0).gravity);

/// Martıyı, simidin ortası altından geçerken simidin hizasına inecek
/// şekilde simidin üstüne koyar.
void dropInto(SimitCatchController c, {double drop = 0.08, int id = 0}) {
  final speed = SimitCatchConfig.forSimits(0).speed;
  c.debugSetFlight(
    birdY: 0.5 - drop,
    velocity: 0,
    simits: <Simit>[
      simitAt(fallSeconds(drop) * speed, id: id, scroll: c.scroll),
    ],
  );
}

void main() {
  group('simit kap — uçuş', () {
    test('ilk kanada kadar sahne durur, martı yerinde süzülür', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      final first = c.simits.first.x;

      c.step(2);

      expect(c.isWaiting, isTrue);
      expect(c.scroll, 0);
      expect(c.simits.first.x, first);
      expect(c.status, GameStatus.playing);
    });

    test('kanat martıyı yukarı iter ve sahneyi başlatır', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      final y = c.birdY;

      c.flap();
      expect(c.isWaiting, isFalse);
      expect(c.velocity, lessThan(0));
      expect(c.flapPulse, 1);

      c.step(0.1);
      expect(c.birdY, lessThan(y));
      expect(c.scroll, greaterThan(0));
    });

    test('tavan öldürmez, martı orada durur', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.debugSetFlight(birdY: 0.05, velocity: -2, simits: <Simit>[]);

      c.step(0.1);

      expect(c.status, GameStatus.playing);
      expect(c.birdY, greaterThanOrEqualTo(simitCatchBirdRadius));
    });

    test('denize düşmek oyunu bitirir', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.debugSetFlight(birdY: 0.8, velocity: 1, simits: <Simit>[]);

      c.step(0.3);

      expect(c.status, GameStatus.gameOver);
      expect(c.endReason, SimitCatchEnd.sea);
    });

    test('yeni simitler sahnenin dışında, bandın içinde doğar', () {
      final c = controllerFor(seed: 7);
      addTearDown(c.dispose);
      c.flap();

      for (var i = 0; i < 40 && c.status == GameStatus.playing; i++) {
        c.debugSetFlight(birdY: 0.4, velocity: 0);
        c.step(0.25);
      }

      final simits = c.simits;
      expect(simits.last.x, greaterThan(c.birdWorldX + 0.9));
      for (final simit in simits) {
        expect(
          simit.y,
          inInclusiveRange(simitCatchTopLane, simitCatchBottomLane),
        );
      }
      for (var i = 1; i < simits.length; i++) {
        expect(simits[i].x - simits[i - 1].x, greaterThan(0.35));
      }
    });
  });

  group('simit kap — geçiş', () {
    test('yukarıdan geçiş sayılır; kenara değmeden TAM İSABET', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      dropInto(c);

      c.step(0.5);

      expect(c.status, GameStatus.playing);
      expect(c.simitsPassed, 1);
      expect(c.swishes, 1);
      expect(c.streak, 1);
      expect(c.lastAwardSwish, isTrue);
      expect(c.score, journeyPoints(SimitCatchController.id, <int>[2]));
      expect(c.lastAward, c.score);
      expect(c.journeySession.hasStationProgress, isTrue);
    });

    test('aşağıdan yukarı geçiş sayılmaz', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.debugSetFlight(birdY: 0.6, velocity: -1.2, simits: <Simit>[simitAt(0)]);

      c.step(0.15);

      expect(c.birdY, lessThan(0.5));
      expect(c.simitsPassed, 0);
      expect(c.score, 0);
    });

    test('kenara değen geçiş 1 puan, seriyi sıfırlar', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      dropInto(c);
      c.simits.first.touched = true;

      c.step(0.5);

      expect(c.simitsPassed, 1);
      expect(c.swishes, 0);
      expect(c.streak, 0);
      expect(c.lastAwardSwish, isFalse);
      expect(c.score, journeyPoints(SimitCatchController.id, <int>[1]));
    });

    test('kenar martıyı sektirir ama oyunu bitirmez', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      final halfWidth = SimitCatchConfig.forSimits(0).halfWidth;
      // Sol kenar halkası tam martının altında.
      c.debugSetFlight(
        birdY: 0.5 - simitCatchBirdRadius - simitCatchRimRadius - 0.01,
        velocity: 0.8,
        simits: <Simit>[simitAt(halfWidth)],
      );

      c.step(0.05);

      expect(c.velocity, lessThan(0));
      expect(c.simits.first.touched, isTrue);
      expect(c.bumpPulse, 1);
      expect(c.status, GameStatus.playing);
    });

    test('seri primi büyür ve dördüncüde durur', () {
      expect(simitCatchPoints(swish: false, streak: 0), 1);
      expect(simitCatchPoints(swish: true, streak: 1), 2);
      expect(simitCatchPoints(swish: true, streak: 3), 4);
      expect(
        simitCatchPoints(swish: true, streak: simitCatchMaxStreakBonus),
        5,
      );
      expect(simitCatchPoints(swish: true, streak: 12), 5);
    });

    test('art arda TAM İSABET seriyi büyütür', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      for (var i = 0; i < 3; i++) {
        dropInto(c, id: i);
        c.step(0.5);
      }

      expect(c.streak, 3);
      expect(c.bestStreak, 3);
      expect(c.score, journeyPoints(SimitCatchController.id, <int>[2, 3, 4]));
    });

    test('simidi kaçırmak oyunu bitirir', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.debugSetFlight(birdY: 0.3, velocity: 0, simits: <Simit>[simitAt(0)]);

      c.step(1.2);

      expect(c.status, GameStatus.gameOver);
      expect(c.endReason, SimitCatchEnd.missed);
      expect(c.simits.first.state, SimitState.missed);
      expect(c.score, 0);
    });

    test('baştan başlamak uçuşu ve seriyi sıfırlar', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      dropInto(c);
      c.step(0.5);
      c.debugSetFlight(birdY: 0.8, velocity: 1, simits: <Simit>[]);
      c.step(0.3);
      expect(c.status, GameStatus.gameOver);

      c.restart();

      expect(c.status, GameStatus.playing);
      expect(c.isWaiting, isTrue);
      expect(c.endReason, isNull);
      expect(c.simitsPassed, 0);
      expect(c.streak, 0);
      expect(c.scroll, 0);
    });
  });

  group('simit kap — zorluk', () {
    test('geçilen simitle sertleşir, tepe noktasında durur', () {
      final easy = SimitCatchConfig.forSimits(0);
      final hard = SimitCatchConfig.forSimits(simitCatchHardenAfter);

      expect(hard.speed, greaterThan(easy.speed));
      expect(hard.spacing, lessThan(easy.spacing));
      expect(hard.halfWidth, lessThan(easy.halfWidth));
      expect(hard.maxRise, greaterThan(easy.maxRise));
      expect(
        SimitCatchConfig.forSimits(simitCatchHardenAfter * 3).speed,
        hard.speed,
      );
    });

    test('en dar simitte de martı kenarlara değmeden sığar', () {
      final hard = SimitCatchConfig.forSimits(simitCatchHardenAfter);
      final opening = hard.halfWidth - simitCatchRimRadius;
      expect(opening, greaterThan(simitCatchBirdRadius * 2));
    });
  });
}
