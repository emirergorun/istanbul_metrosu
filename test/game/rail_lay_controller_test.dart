import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/application/rail_lay_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/data/rail_lay_levels.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/journey_points.dart';
import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

RailLayController controllerFor({int startLevel = 1, LocalStore? store}) {
  return RailLayController(
    journey: shortJourney(),
    recordToBeat: 0,
    startLevel: startLevel,
    store: store,
    // Gerçek zamanlayıcı testte hiç tetiklenmesin; zaman `step` ile akar.
    tick: const Duration(hours: 1),
  )..start();
}

/// Sağa iki kare, aşağı iki kare: iki kayışta biten L.
RailLayLevel lLevel({int number = 1}) =>
    RailLayLevel.parse(<String>['S..', '##.', '##.'], number: number);

/// Kayış sonu kadar kare ilerletir (20 hücre/sn, kare 1/60 sn).
void finishSlide(RailLayController controller) => controller.step(30);

void main() {
  group('ray döşe — kayış', () {
    test('kaydedilen bölümden başlar, başlangıç karesi döşenmiş', () {
      final controller = controllerFor(startLevel: 5);
      addTearDown(controller.dispose);

      expect(controller.levelNumber, 5);
      expect(controller.paintedCount, 1);
      expect(controller.position, controller.level.start);
      expect(controller.score, 0);
    });

    test('kareler metro geçtikçe birer birer döşenir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel());

      controller.swipe(RailLayDirection.right);
      controller.step(2); // ~0,67 hücre: ilk kare döşendi, ikincisi değil
      expect(controller.isSliding, isTrue);
      expect(controller.paintedCount, 2);
      expect(controller.visualPosition.dx, greaterThan(0));
      expect(controller.visualPosition.dx, lessThan(2));

      finishSlide(controller);
      expect(controller.isSliding, isFalse);
      expect(controller.position, const Point<int>(2, 0));
      expect(controller.paintedCount, 3);
      expect(
        controller.paintAt(const Point<int>(1, 0)) & railLayHorizontal,
        isNonZero,
      );
    });

    test('duvara dayalı yöne kaydırmak hiçbir şeyi değiştirmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel());
      final bumps = controller.bumpPulse;

      controller.swipe(RailLayDirection.up);
      finishSlide(controller);

      expect(controller.bumpPulse, bumps + 1);
      expect(controller.moves, 0);
      expect(controller.paintedCount, 1);
      expect(controller.position, controller.level.start);
    });

    test('kayış sürerken gelen kaydırma kuyruğa alınır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel());

      controller.swipe(RailLayDirection.right);
      controller.step(1);
      controller.swipe(RailLayDirection.down);
      controller.step(30);

      expect(controller.moves, 2);
      expect(controller.levelsCleared, 1);
    });
  });

  group('ray döşe — bölüm sonu', () {
    test('bölüm puanı bir kez yazılır, sıradaki bölüm yüklenir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel(number: 3));

      controller.swipe(RailLayDirection.right);
      finishSlide(controller);
      controller.swipe(RailLayDirection.down);
      finishSlide(controller);

      final award = journeyPoints(RailLayController.id, <int>[5]);
      expect(controller.levelsCleared, 1);
      expect(controller.lastAward, award);
      expect(controller.score, award);
      expect(controller.isCelebrating, isTrue);
      expect(controller.journeySession.hasStationProgress, isTrue);

      // Kutlama sırasında girdi alınmaz.
      controller.swipe(RailLayDirection.left);
      expect(controller.isSliding, isFalse);

      controller.step(80);
      expect(controller.isCelebrating, isFalse);
      expect(controller.levelNumber, 4);
      expect(controller.paintedCount, 1);
      expect(controller.score, award);
    });

    test('yarım kalan bölüm puan yazmaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel());

      controller.swipe(RailLayDirection.right);
      finishSlide(controller);

      expect(controller.paintedCount, 3);
      expect(controller.score, 0);
    });

    test('biten bölüm kalıcı kayda yazılır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();
      expect(store.railLayLevel, 1);

      final controller = controllerFor(store: store);
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel(number: 9));
      controller.swipe(RailLayDirection.right);
      finishSlide(controller);
      controller.swipe(RailLayDirection.down);
      finishSlide(controller);
      await Future<void>.delayed(Duration.zero);

      expect(store.railLayLevel, 10);
    });

    test('kutlamada "baştan" biten bölümü yeniden açmaz', () {
      // Aynı bölüm yeniden açılsaydı ikinci kez puanlanırdı.
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel(number: 6));
      controller.swipe(RailLayDirection.right);
      finishSlide(controller);
      controller.swipe(RailLayDirection.down);
      finishSlide(controller);
      expect(controller.isCelebrating, isTrue);

      controller.restart();

      expect(controller.levelNumber, 7);
      expect(controller.isCelebrating, isFalse);
    });
  });

  group('ray döşe — baştan al ve sıkışma', () {
    test('baştan al döşemeyi sıfırlar, puan yazmaz, bölüm aynı kalır', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel(number: 4));
      controller.swipe(RailLayDirection.right);
      finishSlide(controller);

      controller.restartLevel();

      expect(controller.levelNumber, 4);
      expect(controller.paintedCount, 1);
      expect(controller.position, controller.level.start);
      expect(controller.score, 0);
    });

    test('motorun yeniden başlatması mevcut bölümde kalır', () {
      final controller = controllerFor(startLevel: 12);
      addTearDown(controller.dispose);

      controller.restart();

      expect(controller.levelNumber, 12);
      expect(controller.status, GameStatus.playing);
    });

    test(
      'döşenemeyecek kare kalınca sıkıştı işareti birkaç hamle sonra yanar',
      () {
        // Sağ üstteki iki kare arasında gidip gelinebiliyor ama alttaki
        // koridora hiçbir duruştan inilemiyor.
        final controller = controllerFor();
        addTearDown(controller.dispose);
        controller.debugLoadLevel(
          RailLayLevel.parse(<String>['S..#', '#.##', '#...']),
        );

        controller.swipe(RailLayDirection.right);
        finishSlide(controller);
        expect(controller.isDead, isTrue);
        expect(controller.isStuck, isFalse);

        for (var i = 0; i < railLayStuckHintMoves; i++) {
          controller.swipe(
            i.isEven ? RailLayDirection.left : RailLayDirection.right,
          );
          finishSlide(controller);
        }
        expect(controller.isStuck, isTrue);

        controller.restartLevel();
        expect(controller.isDead, isFalse);
        expect(controller.isStuck, isFalse);
      },
    );

    test('tuzak hamlesinden sonra uyarı hemen değil, üç hamle sonra gelir', () {
      // Yukarı kaymak cazip ama metro dikey hatta bir daha ortada duramaz;
      // sol taraf döşenemez kalır. Kullanıcı isteği: oyuncu bunu önce
      // kendisi fark etsin; uyarı ancak birkaç hamle sonra gelsin.
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(
        RailLayLevel.parse(<String>['##.#', '##.#', '..S#', '.#.#']),
      );

      controller.swipe(RailLayDirection.up);
      finishSlide(controller);
      expect(controller.isDead, isTrue);
      expect(controller.isStuck, isFalse, reason: 'ilk hamlede uyarı yok');

      // Duvara dayalı kaydırma hamle sayılmaz.
      controller.swipe(RailLayDirection.right);
      finishSlide(controller);
      expect(controller.isStuck, isFalse);

      controller.swipe(RailLayDirection.down);
      finishSlide(controller);
      controller.swipe(RailLayDirection.up);
      finishSlide(controller);
      expect(controller.isStuck, isFalse, reason: 'iki hamle sonra hâlâ yok');

      controller.swipe(RailLayDirection.down);
      finishSlide(controller);
      expect(controller.isStuck, isTrue, reason: 'üçüncü hamlede uyarı');
    });

    test('doğru hamlede sıkıştı işareti yanmaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(
        RailLayLevel.parse(<String>['##.#', '##.#', '..S#', '.#.#']),
      );

      controller.swipe(RailLayDirection.left);
      finishSlide(controller);

      expect(controller.isDead, isFalse);
      expect(controller.isStuck, isFalse);
    });

    test('bölüm puanı düşünmeyi de sayar', () {
      final controller = controllerFor(startLevel: 3);
      addTearDown(controller.dispose);
      final level = controller.level;

      for (final direction in level.solution) {
        controller.swipe(direction);
        finishSlide(controller);
      }

      expect(level.points, level.openCount + 3 * level.solution.length);
      expect(
        controller.score,
        journeyPoints(RailLayController.id, <int>[level.points]),
      );
    });

    test('son bölümden sonra en zor bölümlere dönülür', () {
      final controller = controllerFor(startLevel: RailLayLevels.count + 1);
      addTearDown(controller.dispose);

      expect(controller.levelNumber, RailLayLevels.count + 1);
      expect(
        controller.level.open,
        RailLayLevels.byNumber(
          RailLayLevels.count - RailLayLevels.loopLength + 1,
        ).open,
      );
    });

    test('çözülebilir bölümde sıkıştı işareti yanmaz', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      controller.debugLoadLevel(lLevel());

      controller.swipe(RailLayDirection.right);
      finishSlide(controller);

      expect(controller.isStuck, isFalse);
    });

    test('beklemek ya da duvara kaydırmak oyunu bitirmez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      for (var i = 0; i < 20; i++) {
        controller.swipe(RailLayDirection.values[i % 4]);
        controller.step(40);
      }
      controller.step(1200);

      expect(controller.status, GameStatus.playing);
    });
  });

  group('ray döşe — üretilen bölümler', () {
    test('kaydedilen çözümle oynanan bölüm biter', () {
      final controller = controllerFor(startLevel: 15);
      addTearDown(controller.dispose);
      final solution = controller.level.solution;

      for (final direction in solution) {
        controller.swipe(direction);
        finishSlide(controller);
      }

      expect(controller.levelsCleared, 1);
      expect(controller.score, greaterThan(0));
    });
  });
}
