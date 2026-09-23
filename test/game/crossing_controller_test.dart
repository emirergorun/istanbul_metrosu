import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/widgets/metro_train.dart';
import 'package:istanbul_metro_game/features/games/crossing/application/crossing_controller.dart';
import 'package:istanbul_metro_game/features/games/crossing/domain/crossing_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/models/station.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/journey_points.dart';
import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

List<MetroLine> allLines() => MetroFixture.load().lines();

CrossingController controllerFor({int seed = 1}) {
  return CrossingController(
    journey: shortJourney(),
    recordToBeat: 0,
    lines: allLines(),
    random: Random(seed),
    // Gerçek zamanlayıcı testte hiç tetiklenmesin; zaman `step` ile akar.
    tick: const Duration(hours: 1),
  )..start();
}

/// Tahtadaki bütün trenleri siler.
///
/// Hareket ve puan testleri trafikten bağımsız: tren gelip gelmemesi
/// tohuma kalsaydı testler kendi kendine kırılırdı.
void clearTraffic(CrossingController controller) {
  for (final row in controller.rows) {
    row.trains.clear();
  }
}

/// Oyuncuyu [near] civarındaki ilk peron satırına koyar.
///
/// `debugSetPlayer` oyuncuyu gelişigüzel bir satıra bırakır; ray satırına
/// denk gelirse ilk karede tren altında kalır ve test asıl ölçtüğü şeye
/// hiç gelemez.
int parkOnPlatform(CrossingController controller, int near) {
  controller.debugSetPlayer(crossingColumns ~/ 2, near);
  for (var index = near; index < near + 10; index++) {
    if (controller.rowAt(index)?.isTrack == false) {
      controller.debugSetPlayer(crossingColumns ~/ 2, index);
      return index;
    }
  }
  fail('$near civarında peron satırı yok');
}

/// Oyuncuyu satır satır ileri taşıyıp üretilen tahtayı toplar.
///
/// Satırlar oyuncu ilerledikçe üretiliyor ve geride kalanlar siliniyor;
/// bütün tahtayı görmenin tek yolu ilerlerken not almak.
List<CrossingRow> walk(CrossingController controller, int rows) {
  final seen = <CrossingRow>[];
  for (var index = 0; index <= rows; index++) {
    controller.debugSetPlayer(crossingColumns ~/ 2, index);
    final row = controller.rowAt(index);
    if (row != null) seen.add(row);
  }
  return seen;
}

void main() {
  group('karşıdan karşıya — tahta', () {
    test('oyuncu ortadaki peronda başlar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      expect(controller.column, crossingColumns ~/ 2);
      expect(controller.row, 0);
      expect(controller.rowsCrossed, 0);
      expect(controller.score, 0);
      for (var index = 0; index < crossingStartSafeRows; index++) {
        expect(controller.rowAt(index)!.kind, CrossingRowKind.platform);
      }
    });

    test('art arda üçten fazla ray satırı gelmez', () {
      for (var seed = 0; seed < 5; seed++) {
        final controller = controllerFor(seed: seed);
        addTearDown(controller.dispose);

        var streak = 0;
        for (final row in walk(controller, 300)) {
          streak = row.isTrack ? streak + 1 : 0;
          expect(
            streak,
            lessThanOrEqualTo(crossingMaxTrackStreak),
            reason:
                '${row.index}. satırda $streak ray üst üste geldi; oyuncunun '
                'duracak peronu kalmıyor',
          );
        }
      }
    });

    test('her ray satırında trafik var ve zorluk arttıkça hızlanıyor', () {
      final controller = controllerFor(seed: 3);
      addTearDown(controller.dispose);

      final rows = walk(controller, 300);
      final tracks = rows.where((CrossingRow r) => r.isTrack).toList();
      expect(tracks, isNotEmpty);
      for (final row in tracks) {
        expect(row.trains, isNotEmpty, reason: '${row.index}. satır boş');
        expect(row.speed, greaterThan(0));
      }

      final early = tracks.where((CrossingRow r) => r.index < 20);
      final late = tracks.where(
        (CrossingRow r) => r.index > CrossingConfig.hardenAfterRows,
      );
      double meanSpeed(Iterable<CrossingRow> rows) =>
          rows.map((CrossingRow r) => r.speed).reduce((a, b) => a + b) /
          rows.length;
      expect(meanSpeed(late), greaterThan(meanSpeed(early)));
    });

    test('trenler arası boşluk her zaman geçilebilir', () {
      // En zor ayardaki pencere bütün satırlar için alt sınır: satır
      // kolayken boşluk daha da büyük oluyor.
      final hardest = CrossingConfig.forRows(CrossingConfig.hardenAfterRows);
      final controller = controllerFor(seed: 7);
      addTearDown(controller.dispose);

      parkOnPlatform(controller, 120);
      // Trafiğin akması, tren doğması ve silinmesi için 20 saniye.
      controller.step(1200);

      for (final row in controller.rows.where((CrossingRow r) => r.isTrack)) {
        final positions =
            row.trains
                .map(
                  (t) => (
                    tail: row.trackPosition(t),
                    head: row.trackPosition(t) + t.length,
                  ),
                )
                .toList()
              ..sort((a, b) => a.tail.compareTo(b.tail));
        for (var i = 1; i < positions.length; i++) {
          final gap = positions[i].tail - positions[i - 1].head;
          expect(
            gap / row.speed,
            greaterThanOrEqualTo(hardest.gapSeconds - 0.001),
            reason:
                '${row.index}. satırda iki tren arasında yalnızca '
                '${(gap / row.speed).toStringAsFixed(2)} saniyelik boşluk var',
          );
        }
      }
    });

    test('çarpışma kutusu ekrandaki trenle aynı uzunlukta', () {
      // Domain kendi sabitleriyle hesaplıyor; ortak tren çizimi değişirse
      // oyuncu görmediği bir trene çarpardı.
      expect(crossingWagonAspect, MetroTrainPainter.defaultWagonAspect);
      expect(crossingCouplingRatio, MetroTrainPainter.couplingRatio);
      for (var cars = 1; cars <= 3; cars++) {
        expect(
          crossingTrainLengthCells(cars),
          closeTo(
            MetroTrain.widthFor(height: crossingTrainHeightCells, wagons: cars),
            1e-9,
          ),
        );
      }
    });
  });

  group('karşıdan karşıya — hat sırası', () {
    /// Trenler kimlik sırasıyla doğuyor; dağıtım sırası budur.
    List<String> spawnOrder(CrossingController controller, int frames) {
      final byId = <int, String>{};
      void collect() {
        for (final row in controller.rows) {
          for (final train in row.trains) {
            byId[train.id] = train.line.id;
          }
        }
      }

      collect();
      for (var i = 0; i < frames; i++) {
        controller.step();
        collect();
      }
      final ids = byId.keys.toList()..sort();
      return <String>[for (final id in ids) byId[id]!];
    }

    test('aynı hat arka arkaya iki kez gelmez', () {
      for (var seed = 0; seed < 4; seed++) {
        final controller = controllerFor(seed: seed);
        addTearDown(controller.dispose);
        parkOnPlatform(controller, 80);

        final order = spawnOrder(controller, 900);
        expect(order.length, greaterThan(40));
        for (var i = 1; i < order.length; i++) {
          expect(
            order[i],
            isNot(order[i - 1]),
            reason: '$i. tren de ${order[i]} — üst üste aynı hat',
          );
        }
      }
    });

    test('bir hat on trenlik pencerede ikiden fazla görünmez', () {
      // Kullanıcının istediği kural: "geçtiği üst üste 5 tren de M2
      // olmasın". Torba yöntemi bundan çok daha fazlasını garanti ediyor —
      // her hat on trende en çok iki kez geçebilir, çünkü bir pencere en
      // fazla iki torbaya değer.
      final controller = controllerFor(seed: 11);
      addTearDown(controller.dispose);
      parkOnPlatform(controller, 80);

      final order = spawnOrder(controller, 900);
      final lineCount = allLines().length;
      expect(order.length, greaterThan(lineCount * 2));

      for (var i = 0; i + 10 <= order.length; i++) {
        final counts = <String, int>{};
        for (final id in order.sublist(i, i + 10)) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
        final worst = counts.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        expect(
          worst.value,
          lessThanOrEqualTo(2),
          reason:
              '$i. trenden itibaren on trenin ${worst.value} tanesi '
              '${worst.key}',
        );
      }

      // Uzun koşuda bütün hatlar sahneye çıkar; kimse unutulmuyor.
      expect(order.toSet().length, lineCount);
    });
  });

  group('karşıdan karşıya — hareket ve puan', () {
    test('ileri adım puan yazar, geri adım yazmaz', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);

      controller.move(CrossingDirection.forward);
      controller.step(20);
      expect(controller.row, 1);
      expect(controller.rowsCrossed, 1);
      final afterForward = controller.score;
      expect(afterForward, greaterThan(0));

      controller.move(CrossingDirection.back);
      controller.step(20);
      expect(controller.row, 0);
      expect(controller.score, afterForward);

      // Aynı satıra tekrar çıkmak da puan vermez.
      controller.move(CrossingDirection.forward);
      controller.step(20);
      expect(controller.row, 1);
      expect(controller.score, afterForward);
    });

    test('peron ve ray satırları farklı puan verir', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);

      final raws = <int>[];
      for (var target = 1; target <= 10; target++) {
        clearTraffic(controller);
        controller.move(CrossingDirection.forward);
        controller.step(20);
        final row = controller.rowAt(controller.row)!;
        raws.add(row.isTrack ? crossingTrackPoints : crossingPlatformPoints);
      }

      expect(raws, contains(crossingTrackPoints));
      expect(raws, contains(crossingPlatformPoints));
      expect(controller.score, journeyPoints(CrossingController.id, raws));
    });

    test('kenara dayanınca hamle yutulur, oyun sürer', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);
      controller.debugSetPlayer(0, 0);

      controller.move(CrossingDirection.left);
      controller.step(20);

      expect(controller.column, 0);
      expect(controller.facing, CrossingDirection.left);
      expect(controller.status, GameStatus.playing);
    });

    test('silinmiş satırlara geri dönülemez', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);
      final start = parkOnPlatform(controller, 20);

      for (var i = 0; i < 10; i++) {
        clearTraffic(controller);
        controller.move(CrossingDirection.back);
        controller.step(20);
      }

      expect(controller.status, GameStatus.playing);
      expect(controller.row, controller.backLimit);
      expect(controller.row, start - crossingPlayerViewRow);
    });

    test('zıplarken figür iki hücrenin arasında durur', () {
      // Ekran katmanı konumu buradan okuyor: ara değer olmadan oyuncu
      // hücreden hücreye ışınlanırdı.
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);
      clearTraffic(controller);

      controller.move(CrossingDirection.forward);
      controller.step(4); // ~0,067 sn: zıplamanın ortası

      expect(controller.isHopping, isTrue);
      expect(controller.hopProgress, greaterThan(0));
      expect(controller.hopProgress, lessThan(1));
      expect(controller.visualRow, greaterThan(0));
      expect(controller.visualRow, lessThan(1));

      controller.step(20);
      expect(controller.visualRow, 1);
      expect(controller.hopProgress, 1);
    });

    test('zıplama sırasında gelen hamle kuyruğa alınır', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);
      final startColumn = controller.column;

      controller.move(CrossingDirection.forward);
      controller.step(4); // zıplamanın ortası
      expect(controller.isHopping, isTrue);

      controller.move(CrossingDirection.right);
      controller.step(30);

      expect(controller.row, 1);
      expect(controller.column, startColumn + 1);
      expect(controller.isHopping, isFalse);
    });

    test('dört ray geçişinde bir durak ilerlemesi işlenir', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);
      expect(controller.journeySession.hasStationProgress, isFalse);

      var guard = 0;
      while (controller.tracksCrossed < crossingRowsPerStation &&
          guard++ < 60) {
        clearTraffic(controller);
        controller.move(CrossingDirection.forward);
        controller.step(20);
      }

      expect(controller.tracksCrossed, crossingRowsPerStation);
      // Durak bonusu hakkı: bir sonraki durak geçilince skora yazılır.
      expect(controller.journeySession.hasStationProgress, isTrue);
    });
  });

  group('karşıdan karşıya — bitiş', () {
    /// Oyuncuyu bir ray satırına koyar ve o satırı döndürür.
    CrossingRow moveToTrack(CrossingController controller) {
      for (var index = crossingStartSafeRows; index < 200; index++) {
        final row = controller.rowAt(index);
        if (row != null && row.isTrack) {
          controller.debugSetPlayer(4, index);
          return controller.rowAt(index)!;
        }
        controller.debugSetPlayer(4, index);
      }
      fail('ray satırı bulunamadı');
    }

    test('trene çarpınca oyun biter', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);

      final row = moveToTrack(controller);
      controller.debugSetTrains(row.index, <CrossingTrain>[
        controller.debugTrain(x: controller.column.toDouble()),
      ]);
      controller.step();

      expect(controller.status, GameStatus.gameOver);
      expect(controller.crashed, isTrue);
    });

    test('beklemek oyunu bitirmez', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);

      // Peronda otuz saniye: kovalayan yok, kamera kendi başına kaymıyor.
      controller.step(1800);

      expect(controller.status, GameStatus.playing);
      expect(controller.row, 0);
    });

    test('zıplamanın ilk yarısında çıkılan hücre esas alınır', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);

      final row = moveToTrack(controller);
      // Oyuncu peronda, hedef rayda tam karşısına bir tren koyuyoruz.
      controller.debugSetPlayer(4, row.index - 1);
      clearTraffic(controller);
      controller.debugSetTrains(row.index, <CrossingTrain>[
        controller.debugTrain(x: 4),
      ]);

      controller.move(CrossingDirection.forward);
      controller.step(2); // zıplamanın ilk yarısı
      expect(controller.status, GameStatus.playing);

      controller.step(10); // ikinci yarı: artık hedef hücre sayılır
      expect(controller.status, GameStatus.gameOver);
    });

    test('yeniden başlayınca tahta sıfırlanır', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);
      controller.debugSetPlayer(4, 30);
      controller.move(CrossingDirection.forward);
      controller.step(20);

      controller.restart();

      expect(controller.row, 0);
      expect(controller.column, crossingColumns ~/ 2);
      expect(controller.rowsCrossed, 0);
      expect(controller.tracksCrossed, 0);
      expect(controller.crashed, isFalse);
      expect(controller.rowAt(0)!.kind, CrossingRowKind.platform);
    });
  });

  group('karşıdan karşıya — zorluk', () {
    test('rampa monoton ve tavanda sabit', () {
      final easy = CrossingConfig.forRows(0);
      final mid = CrossingConfig.forRows(CrossingConfig.hardenAfterRows ~/ 2);
      final hard = CrossingConfig.forRows(CrossingConfig.hardenAfterRows);
      final beyond = CrossingConfig.forRows(CrossingConfig.hardenAfterRows * 5);

      expect(easy.trackChance, lessThan(mid.trackChance));
      expect(mid.trackChance, lessThan(hard.trackChance));
      expect(easy.maxSpeed, lessThan(hard.maxSpeed));
      expect(easy.gapSeconds, greaterThan(hard.gapSeconds));
      expect(beyond.gapSeconds, hard.gapSeconds);
      expect(beyond.maxSpeed, hard.maxSpeed);

      // En zor ayarda bile boşluk bir zıplamanın birkaç katı.
      expect(hard.gapSeconds, greaterThan(crossingHopSeconds * 4));
    });
  });
}
