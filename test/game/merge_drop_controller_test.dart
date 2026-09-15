import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

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

    test('farklı seviyeden toplar birbirinin üstünde kararlı durur', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final bottomRadius = mergeDropRadiusForLevel(3);
      final topRadius = mergeDropRadiusForLevel(2);
      final bottomY = 1 - bottomRadius;
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: bottomY),
        DropBall(
          id: 2,
          level: 2,
          x: 0.5,
          y: bottomY - bottomRadius - topRadius,
        ),
      ]);

      for (var i = 0; i < 40; i++) {
        controller.debugStep(0.016);
      }

      final bottom = controller.balls.firstWhere((b) => b.level == 3);
      final top = controller.balls.firstWhere((b) => b.level == 2);

      // Alttaki top zeminden ayrılmamış.
      expect(bottom.y, closeTo(bottomY, 0.005));
      // Üstteki top hâlâ üstte ve iki top birbirinin içine gömülmemiş.
      expect(top.y, lessThan(bottom.y));
      final centerDistance = bottom.y - top.y;
      expect(centerDistance, closeTo(bottomRadius + topRadius, 0.01));
    });

    test('hızlı düşen top altındaki topun içinden geçip altına inmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final restingRadius = mergeDropRadiusForLevel(3);
      final restingY = 1 - restingRadius;
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: restingY),
        DropBall(id: 2, level: 2, x: 0.5, y: 0.15, vy: 2.4),
      ]);

      for (var i = 0; i < 60; i++) {
        controller.debugStep(0.016);
      }

      final resting = controller.balls.firstWhere((b) => b.level == 3);
      final fallen = controller.balls.firstWhere((b) => b.level == 2);

      // Zeminde duran top yerinden oynamamış — düşen top altına geçmemiş.
      expect(resting.y, closeTo(restingY, 0.01));
      expect(fallen.y, lessThan(resting.y));
    });

    test('yeni bırakılan top tehlike çizgisinin üstünde doğsa da anında '
        'kaybettirmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      final accepted = controller.drop();
      controller.debugStep(0.05);

      expect(accepted, isTrue);
      expect(controller.status, isNot(GameStatus.gameOver));
    });

    test('art arda bırakılan toplar oyunu saniyeler içinde bitirmez', () {
      // Regresyon: `settled` bayrağı eskiden "herhangi bir şeye değdi"
      // demekti ve çarpışma çözücüsü havada birbirine değen iki topa da
      // bunu basıyordu. Doğum noktası tehlike çizgisinin üstünde olduğu
      // için oyun ~0.9 saniyede bitiyordu. Tek top bırakan eski test bunu
      // göremiyordu; hata iki top ve ~0.25 saniye gerektiriyor.
      final controller = controllerFor();
      addTearDown(controller.dispose);

      for (var frame = 0; frame < 60 * 6; frame++) {
        if (controller.canDrop) {
          controller.moveAim(0.3 + (frame % 5) * 0.1);
          controller.drop();
        }
        controller.debugStep(1 / 60);
        if (controller.status == GameStatus.gameOver) break;
      }

      expect(
        controller.status,
        isNot(GameStatus.gameOver),
        reason: 'altı saniyelik normal oynayışta oyun bitmemeli',
      );
      expect(controller.merges, greaterThan(0));
    });

    test('doğum noktası doluyken yeni top bırakılamaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      // Bekleme süresini doldur ki tek engel doğum bölgesi olsun.
      controller.debugStep(0.4);
      expect(controller.canDrop, isTrue);

      // Doğum noktasının tam üstünde duran bir top koy.
      controller.moveAim(0.5);
      controller.debugSetBalls(<DropBall>[
        DropBall(
          id: 99,
          level: 1,
          x: 0.5,
          y: mergeDropRadiusForLevel(1) + 0.015,
        ),
      ]);

      expect(controller.canDrop, isFalse);
      expect(controller.drop(), isFalse);
    });

    test(
      'oturmuş bir top tehlike çizgisinde kalırsa kısa sürede kaybettirir',
      () {
        final controller = controllerFor();
        addTearDown(controller.dispose);
        // Zeminden tehlike çizgisinin üstüne kadar uzanan bir sütun.
        // M7 seçildi: en büyük seviye birleşmediği için sütun ayakta kalır
        // ve en üstteki top gerçekten "oturmuş" sayılır.
        final r = mergeDropRadiusForLevel(mergeDropMaxLevel);
        controller.debugSetBalls(<DropBall>[
          for (var i = 0; i < 4; i++)
            DropBall(
              id: i,
              level: mergeDropMaxLevel,
              x: 0.5,
              y: 1 - r - i * r * 2,
            ),
        ]);

        for (var i = 0; i < 90; i++) {
          controller.debugStep(0.016);
          if (controller.status == GameStatus.gameOver) break;
        }

        expect(controller.status, GameStatus.gameOver);
      },
    );

    test('havuz oranı değişince toplar havuz içinde kalır', () {
      // Regresyon: fizik izotropik bir dünyada çalışır (1 birim = havuz
      // genişliği, her iki eksende). Havuz dikey olduğunda dünya
      // yüksekliği 1'den büyüktür; çizim katmanı her iki ekseni de
      // genişlikle ölçekler. Eskiden x genişlikle, y yükseklikle,
      // yarıçap kısa kenarla çarpılıyordu — fizikte tam temas eden toplar
      // ekranda boşluklu görünüyordu.
      final controller = controllerFor();
      addTearDown(controller.dispose);
      expect(controller.worldHeight, 1.0);

      final r = mergeDropRadiusForLevel(2);
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 2, x: 0.5, y: 1 - r),
      ]);

      controller.setPoolAspect(1.6);

      expect(controller.worldHeight, 1.6);
      // Tehlike çizgisi havuz yüksekliğiyle ölçeklenir.
      expect(controller.dangerY, closeTo(mergeDropDangerLine * 1.6, 1e-9));
      // Top havuzun içinde kalmalı.
      final ball = controller.balls.single;
      expect(ball.y, lessThanOrEqualTo(controller.worldHeight - ball.radius));
      expect(ball.y, greaterThanOrEqualTo(ball.radius));
    });

    test('dikey havuzda üst üste duran toplar tam temas eder', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.setPoolAspect(1.6);

      final rBottom = mergeDropRadiusForLevel(3);
      final rTop = mergeDropRadiusForLevel(2);
      final floorY = controller.worldHeight - rBottom;
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 3, x: 0.5, y: floorY),
        DropBall(id: 2, level: 2, x: 0.5, y: floorY - rBottom - rTop),
      ]);

      for (var i = 0; i < 60; i++) {
        controller.debugStep(1 / 60);
      }

      final bottom = controller.balls.firstWhere((b) => b.level == 3);
      final top = controller.balls.firstWhere((b) => b.level == 2);
      final gap = (bottom.y - top.y) - (rBottom + rTop);

      // Merkez mesafesi yarıçap toplamına eşit olmalı: temas var, boşluk yok.
      expect(gap.abs(), lessThan(0.005), reason: 'toplar arasında boşluk var');
    });

    test('çarpışan toplar yapışmaz, hafifçe sekip ayrılır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final r2 = mergeDropRadiusForLevel(2);
      final r4 = mergeDropRadiusForLevel(4);
      controller.debugSetBalls(<DropBall>[
        DropBall(id: 1, level: 2, x: 0.4, y: 0.5, vx: 0.5),
        DropBall(id: 2, level: 4, x: 0.4 + r2 + r4, y: 0.5, vx: -0.5),
      ]);

      controller.debugStep(0.001);

      final a = controller.balls.firstWhere((b) => b.id == 1);
      final b = controller.balls.firstWhere((b) => b.id == 2);
      // Kütleler farklı (M4 çok daha ağır) olduğu için ikisi de yön
      // değiştirmeyebilir — b (ağır) yavaşlar, a (hafif) sert geri teper.
      // "Yapışmadıklarını" gösteren asıl işaret, göreli hızlarının artık
      // birbirinden uzaklaşıyor olması: esnek olmayan bir çarpışmada bu
      // sıfıra iner (yapışık kalır), sekmeyle pozitife döner (ayrılırlar).
      final relativeVxAfter = b.vx - a.vx;
      expect(relativeVxAfter, greaterThan(0));
    });
  });
}
