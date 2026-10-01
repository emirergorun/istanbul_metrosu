import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/passport/domain/achievement.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import 'merge_drop_controller_test.dart' show shortJourney;

MergeDropController controllerFor({int seed = 1, List<int>? weights}) =>
    MergeDropController(
      journey: shortJourney(),
      recordToBeat: 0,
      random: Random(seed),
      spawnWeights: weights ?? mergeDropSpawnWeights,
      tick: const Duration(hours: 1),
    )..start();

void main() {
  group('Şimdi / sonra', () {
    test('bırakınca sonra şimdiye geçer, yeni sonra gelir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final next = controller.nextLevel;

      expect(controller.drop(), isTrue);

      expect(controller.currentLevel, next);
      expect(controller.balls.single.level, isNot(0));
    });

    test('aynı tohum aynı parça sırasını verir (meydan okuma)', () {
      List<int> sequence(int seed) {
        final c = controllerFor(seed: seed);
        final out = <int>[c.currentLevel, c.nextLevel];
        for (var i = 0; i < 8; i++) {
          c.debugSetBalls(const <DropBall>[]);
          c.debugStep(0.4);
          c.drop();
          out.add(c.nextLevel);
        }
        c.dispose();
        return out;
      }

      expect(sequence(42), sequence(42));
    });

    test('yeniden başlatma parçaları ve koşu sayaçlarını sıfırlar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 3, x: 0.52, y: 0.7),
      ]);
      controller.debugStep(0.01);
      expect(controller.bestChain, 1);

      controller.restart();

      expect(controller.balls, isEmpty);
      expect(controller.bestChain, 0);
      expect(controller.maxLevel, mergeDropMinLevel);
      expect(controller.takeEvents(), isEmpty);
      expect(controller.currentLevel, inInclusiveRange(1, 4));
      expect(controller.nextLevel, inInclusiveRange(1, 4));
    });
  });

  group('Doğum ağırlıkları', () {
    /// Bırakılan parçaların seviyesini sayar (yalnız kabul edilen bırakış).
    List<int> dropped(MergeDropController controller, int count, int levels) {
      final counts = List<int>.filled(levels + 1, 0);
      var done = 0;
      var guard = 0;
      while (done < count && guard++ < count * 4) {
        // Yolculuk süresi biterse oyun durur; ölçüm yeni koşuda sürer.
        if (controller.status != GameStatus.playing) controller.restart();
        controller.debugSetBalls(const <DropBall>[]);
        for (var i = 0; i < 7; i++) {
          controller.debugStep(0.05);
        }
        final level = controller.currentLevel;
        if (controller.drop()) {
          counts[level]++;
          done++;
        }
      }
      return counts;
    }

    test('M1 en sık, M4 en seyrek; hiçbir zaman M4\'ün üstü yok', () {
      final controller = controllerFor(seed: 7);
      addTearDown(controller.dispose);
      final counts = dropped(controller, 2000, 4);
      expect(counts[1], greaterThan(counts[2]));
      expect(counts[2], greaterThan(counts[3]));
      expect(counts[3], greaterThan(counts[4]));
      expect(counts[4], greaterThan(0));
      // Oran ağırlıklara yakın: M1 ~%40, M4 ~%10.
      expect(counts[1] / 2000, closeTo(0.4, 0.05));
      expect(counts[4] / 2000, closeTo(0.1, 0.03));
    });

    test('eşit ağırlık verilirse eşit dağılır', () {
      final controller = controllerFor(seed: 3, weights: const <int>[1, 1]);
      addTearDown(controller.dispose);
      final counts = dropped(controller, 1000, 2);
      expect(counts[1] / 1000, closeTo(0.5, 0.06));
    });
  });

  group('Puan', () {
    test('birleşme puanı seviyeyle katlanır', () {
      expect(mergeDropMergePoints(2), 10);
      expect(mergeDropMergePoints(5), 80);
      expect(mergeDropMergePoints(8), 640);
      expect(mergeDropMergePoints(11), 5120);
      // M8, M2'nin 64 katı — doğrusal puanda 4 kattı.
      expect(mergeDropMergePoints(8) / mergeDropMergePoints(2), 64);
    });

    test('zincir çarpanı adım adım artar ve tavanda durur', () {
      expect(mergeDropMergePoints(4, chain: 1), 40);
      expect(mergeDropMergePoints(4, chain: 2), 50);
      expect(mergeDropMergePoints(4, chain: 5), 80);
      expect(mergeDropMergePoints(4, chain: 9), 80, reason: 'tavan ×2');
    });
  });

  group('Zincir', () {
    test('birleşmeden doğan parça hemen birleşirse zincir ×2', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      // İki M2 birleşip M3 doğar; yanında bekleyen M3'e değer.
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 2, x: 0.40, y: 0.90),
        DropBall(id: 2, level: 2, x: 0.45, y: 0.90),
        DropBall(id: 3, level: 3, x: 0.55, y: 0.90),
      ]);
      for (var i = 0; i < 30; i++) {
        controller.debugStep(1 / 60);
      }
      final events = controller.takeEvents();
      expect(events.map((e) => e.level), containsAllInOrder(<int>[3, 4]));
      expect(events.last.chain, 2);
      expect(controller.bestChain, 2);
    });

    test('ilgisiz iki birleşme zincir sayılmaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 2, x: 0.10, y: 0.90),
        DropBall(id: 2, level: 2, x: 0.16, y: 0.90),
        DropBall(id: 3, level: 5, x: 0.70, y: 0.85),
        DropBall(id: 4, level: 5, x: 0.80, y: 0.85),
      ]);
      controller.debugStep(1 / 60);
      final events = controller.takeEvents();
      expect(events, hasLength(2));
      expect(events.every((e) => e.chain == 1), isTrue);
    });

    test('pencere geçtikten sonraki birleşme zinciri sürdürmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: 0.9, chain: 3, bornAt: 0),
        DropBall(id: 2, level: 3, x: 0.55, y: 0.9),
      ]);
      // Koşu saati pencereyi aşsın.
      controller.debugStep(mergeDropChainWindow + 0.2);
      expect(controller.takeEvents().single.chain, 1);
    });
  });

  group('Birleşme olayı', () {
    test('konum, ebeveynler, puan ve yeni en büyük hat taşır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugSetBalls(const <DropBall>[
        DropBall(id: 1, level: 6, x: 0.5, y: 0.7),
        DropBall(id: 2, level: 6, x: 0.52, y: 0.7),
      ]);
      controller.debugStep(0.01);
      final event = controller.takeEvents().single;
      expect(event.level, 7);
      expect(event.parentA.$1, closeTo(0.5, 0.05));
      expect(event.parentB.$1, closeTo(0.52, 0.05));
      expect(event.points, greaterThan(0));
      expect(event.newRunMax, isTrue);
      expect(controller.takeEvents(), isEmpty, reason: 'olaylar bir kez');
    });

    test('M11 + M11 birleşmez, oyun sürer', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller
        ..setPoolAspect(mergeDropPoolAspect)
        ..debugSetBalls(const <DropBall>[
          DropBall(id: 1, level: 11, x: 0.27, y: 0.8),
          DropBall(id: 2, level: 11, x: 0.73, y: 0.8),
        ]);
      for (var i = 0; i < 60; i++) {
        controller.debugStep(1 / 60);
      }
      expect(controller.balls.where((b) => b.level == 11), hasLength(2));
      expect(controller.takeEvents(), isEmpty);
      expect(controller.status, GameStatus.playing);
    });
  });

  group('Tehlike', () {
    test('boş havuz sakin', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugStep(1 / 60);
      expect(controller.danger, MergeDropDanger.calm);
    });

    /// Zemindeki M11'in tam üstünde duran ikinci bir jeton.
    MergeDropController stacked(int topLevel) {
      final controller = controllerFor()..setPoolAspect(mergeDropPoolAspect);
      final h = controller.worldHeight;
      final bottom = mergeDropRadiusForLevel(11);
      final top = mergeDropRadiusForLevel(topLevel);
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 11, x: 0.5, y: h - bottom),
        DropBall(id: 2, level: topLevel, x: 0.5, y: h - 2 * bottom - top),
      ]);
      return controller;
    }

    test('çizgiye yaklaşan oturmuş yığın "yakın"', () {
      // M11 üstünde M9: tepe çizginin hemen altında.
      final controller = stacked(9);
      addTearDown(controller.dispose);
      for (var i = 0; i < 6; i++) {
        controller.debugStep(1 / 60);
      }
      expect(controller.danger, MergeDropDanger.near);
      expect(controller.status, GameStatus.playing);
    });

    test('çizgiyi aşan oturmuş yığın "kritik", bekleme sonunda biter', () {
      // M11 üstünde M10: tepe çizginin üstünde.
      final controller = stacked(10);
      addTearDown(controller.dispose);
      for (var i = 0; i < 3; i++) {
        controller.debugStep(1 / 60);
      }
      expect(controller.danger, MergeDropDanger.critical);
      expect(controller.status, GameStatus.playing, reason: 'bekleme payı');
      for (var i = 0; i < 30; i++) {
        controller.debugStep(1 / 60);
      }
      expect(controller.status, GameStatus.gameOver);
    });
  });

  test('rozet eşiği oyunun son seviyesiyle aynı', () {
    expect(Achievements.mergeDropMaxLevelForBadge, mergeDropMaxLevel);
    expect(Achievements.mergeDropM11.target, mergeDropMaxLevel);
  });

  test('çizim yarıçapı 0,9\'dan doğar, aşar ve oturur', () {
    const ball = DropBall(id: 1, level: 4, x: 0.5, y: 0.5, pop: 0);
    expect(ball.drawRadius / ball.radius, closeTo(0.9, 0.001));
    final peak = ball.copyWith(pop: 0.55);
    expect(peak.drawRadius / ball.radius, closeTo(1.08, 0.001));
    expect(ball.copyWith(pop: 1).drawRadius, ball.radius);
  });
}
