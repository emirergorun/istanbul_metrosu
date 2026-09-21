import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/domain/metro_tile.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() {
  final service = RouteService(MetroFixture.load());
  return service.estimate('m2_taksim', 'm2_levent').journey!;
}

MetroMergeController controllerFor({int seed = 1}) => MetroMergeController(
  journey: shortJourney(),
  recordToBeat: 0,
  random: Random(seed),
)..start();

List<List<MetroTile?>> emptyGrid(int size) => List<List<MetroTile?>>.generate(
  size,
  (_) => List<MetroTile?>.filled(size, null),
);

int tileCount(MetroMergeController c) {
  var n = 0;
  for (final row in c.grid) {
    for (final tile in row) {
      if (tile != null) n++;
    }
  }
  return n;
}

void main() {
  group('hat birleştirme — 2048 kuralları', () {
    test('tahta 4x4', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      expect(controller.config.gridSize, 4);
    });

    test('oyun iki karoyla başlar', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      expect(tileCount(controller), 2);
    });

    test('M1 + M1 sola kayınca M2 olur', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][0] = const MetroTile(rank: 1);
      grid[0][1] = const MetroTile(rank: 1);
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isTrue);
      expect(outcome.merges, 1);
      expect(controller.grid[0][0]?.lineLabel, 'M2');
      expect(controller.grid[0][0]?.rank, 2);
    });

    test('M2 + M2 sola kayınca M3 olur', () {
      final controller = controllerFor(seed: 2);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][0] = const MetroTile(rank: 2);
      grid[0][1] = const MetroTile(rank: 2);
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isTrue);
      expect(outcome.merges, 1);
      expect(controller.grid[0][0]?.lineLabel, 'M3');
      expect(controller.grid[0][0]?.rank, 3);
    });

    test('bir hamlede birleşen karo tekrar birleşemez: M1x4 → M2 M2', () {
      // 2048'in en kritik kuralı. Bu olmadan [2 2 2 2] tek hamlede 8 olurdu.
      final controller = controllerFor(seed: 3);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      for (var col = 0; col < 4; col++) {
        grid[0][col] = const MetroTile(rank: 1);
      }
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.merges, 2);
      expect(controller.grid[0][0]?.rank, 2);
      expect(controller.grid[0][1]?.rank, 2);
    });

    test('puan, oluşan karonun değeri kadardır', () {
      // 2048: iki "2" birleşince +4. M1 = 2, M2 = 4.
      final controller = controllerFor(seed: 4);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][0] = const MetroTile(rank: 1);
      grid[0][1] = const MetroTile(rank: 1);
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.gainedPoints, 4);
      expect(const MetroTile(rank: 11).value, 2048);
    });

    test('karolar duvara kadar kayar', () {
      final controller = controllerFor(seed: 5);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[2][3] = const MetroTile(rank: 3);
      controller.debugSetGrid(grid);

      controller.move(MetroMoveDirection.left);

      expect(controller.grid[2][0]?.rank, 3);
      expect(controller.grid[2][3], isNull);
    });

    test(
      'tahtayı değiştirmeyen hamle reddedilir: karo doğmaz, puan yazılmaz',
      () {
        final controller = controllerFor(seed: 6);
        addTearDown(controller.dispose);

        final grid = emptyGrid(controller.config.gridSize);
        grid[0][0] = const MetroTile(rank: 1);
        grid[1][0] = const MetroTile(rank: 3);
        controller.debugSetGrid(grid);
        final before = tileCount(controller);
        final scoreBefore = controller.score;

        final outcome = controller.move(MetroMoveDirection.left);

        expect(outcome.accepted, isFalse);
        expect(tileCount(controller), before);
        expect(controller.score, scoreBefore);
      },
    );

    test('kabul edilen her hamlede bir yeni karo doğar', () {
      final controller = controllerFor(seed: 7);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][3] = const MetroTile(rank: 2);
      controller.debugSetGrid(grid);

      controller.move(MetroMoveDirection.left);

      // Kayan bir karo + doğan bir karo.
      expect(tileCount(controller), 2);
    });

    test('dolu satır SİLİNMEZ — 2048 tetris değildir', () {
      // Regresyon: eskiden "dolu satır/sütun silinir" diye 2048'e ait
      // olmayan bir mekanik vardı. 4x4'te bir duvara dayanan dört karo
      // zaten dolu bir sıra demek, yani mekanik sürekli tetikleniyor ve
      // oyuncunun tüm ilerlemesini siliyordu.
      final controller = controllerFor(seed: 8);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      // Birleşmeyecek dört farklı hat, en alt satırda.
      for (var col = 0; col < 4; col++) {
        grid[3][col] = MetroTile(rank: col + 1);
      }
      controller.debugSetGrid(grid);

      final outcome = controller.move(MetroMoveDirection.up);

      expect(outcome.accepted, isTrue);
      expect(outcome.merges, 0);
      // Dördü de üst satırda duruyor olmalı, silinmiş değil.
      for (var col = 0; col < 4; col++) {
        expect(
          controller.grid[0][col]?.rank,
          col + 1,
          reason: 'sütun $col silinmiş',
        );
      }
    });

    test('en üst hattaki iki karo birleşmez ve yok olmaz', () {
      // Regresyon: eskiden en üst hatta birleşen karolar tahtadan
      // siliniyordu (`vanish`); 2048'de böyle bir kural yok.
      final controller = controllerFor(seed: 9);
      addTearDown(controller.dispose);

      final grid = emptyGrid(controller.config.gridSize);
      grid[0][2] = const MetroTile(rank: metroMergeMaxRank);
      grid[0][3] = const MetroTile(rank: metroMergeMaxRank);
      controller.debugSetGrid(grid);

      controller.move(MetroMoveDirection.left);

      expect(controller.grid[0][0]?.rank, metroMergeMaxRank);
      expect(controller.grid[0][1]?.rank, metroMergeMaxRank);
    });

    test('tahta dolup birleşme kalmayınca oyun biter', () {
      final controller = controllerFor(seed: 10);
      addTearDown(controller.dispose);

      // Hiçbir komşusu eş olmayan, tamamen dolu bir tahta.
      final grid = emptyGrid(controller.config.gridSize);
      const ranks = <List<int>>[
        <int>[1, 2, 1, 2],
        <int>[2, 1, 2, 1],
        <int>[1, 2, 1, 2],
        <int>[2, 1, 2, 3],
      ];
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 4; col++) {
          grid[row][col] = MetroTile(rank: ranks[row][col]);
        }
      }
      controller.debugSetGrid(grid);
      // Kurulum gerçekten kilitli mi? Her yön reddedilmeli.
      for (final d in MetroMoveDirection.values) {
        expect(controller.move(d).accepted, isFalse, reason: '$d kabul edildi');
      }
    });

    test('uzun oyunda tahta hiç boşalmaz ve oyun düzgün biter', () {
      // Asıl regresyon: eski sürümde tahta 22 hamlede tamamen boşalıyor ve
      // oyun kilitleniyordu (boş tahtada hiçbir hamle kabul edilmediği için
      // yeni karo da doğmuyordu).
      for (final seed in <int>[1, 4, 7, 11, 23]) {
        final controller = controllerFor(seed: seed);
        addTearDown(controller.dispose);
        final aim = Random(seed * 17);

        var rejectedInARow = 0;
        for (var m = 0; m < 3000; m++) {
          if (controller.status != GameStatus.playing) break;
          final accepted = controller
              .move(MetroMoveDirection.values[aim.nextInt(4)])
              .accepted;
          rejectedInARow = accepted ? 0 : rejectedInARow + 1;

          expect(
            tileCount(controller),
            greaterThan(0),
            reason: 'tohum $seed: tahta boşaldı (hamle $m)',
          );
          // Dört yön de üst üste reddediliyorsa oyun kilitlenmiş demektir;
          // o durumda bitiş koşulu tetiklenmiş olmalıydı.
          expect(
            rejectedInARow,
            lessThan(50),
            reason: 'tohum $seed: oyun kilitlendi ama bitmedi',
          );
        }
      }
    });
  });

  group('karoların yolu (kayma animasyonu için)', () {
    test('sola kaydırmada her karonun nereden nereye gittiği kaydedilir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final grid = emptyGrid(4);
      grid[0][0] = const MetroTile(rank: 1);
      grid[0][1] = const MetroTile(rank: 1);
      grid[0][3] = const MetroTile(rank: 2);
      controller.debugSetGrid(grid);
      final before = controller.moveCount;

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isTrue);
      expect(controller.moveCount, before + 1);
      // İki M1 aynı hedefe (0,0) kayar ve orada birleşir; M2 (0,3)'ten
      // (0,1)'e kayar.
      expect(
        controller.lastMoves,
        containsAll(const <MetroTileMove>[
          MetroTileMove(fromRow: 0, fromCol: 0, toRow: 0, toCol: 0, rank: 1),
          MetroTileMove(fromRow: 0, fromCol: 1, toRow: 0, toCol: 0, rank: 1),
          MetroTileMove(fromRow: 0, fromCol: 3, toRow: 0, toCol: 1, rank: 2),
        ]),
      );
      expect(controller.lastMoves, hasLength(3));
      expect(controller.lastMerged, <(int, int)>{(0, 0)});
      // Yeni karo boş bir hücrede doğdu.
      final spawn = controller.lastSpawn!;
      expect(spawn, isNot((0, 0)));
      expect(spawn, isNot((0, 1)));
    });

    test('aşağı kaydırmada yol sütun boyunca kaydedilir', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final grid = emptyGrid(4);
      grid[0][2] = const MetroTile(rank: 3);
      controller.debugSetGrid(grid);

      controller.move(MetroMoveDirection.down);

      expect(controller.lastMoves, const <MetroTileMove>[
        MetroTileMove(fromRow: 0, fromCol: 2, toRow: 3, toCol: 2, rank: 3),
      ]);
      expect(controller.lastMerged, isEmpty);
    });

    test('tahtayı değiştirmeyen kaydırma animasyon tetiklemez', () {
      final controller = controllerFor();
      addTearDown(controller.dispose);
      final grid = emptyGrid(4);
      grid[0][0] = const MetroTile(rank: 1);
      controller.debugSetGrid(grid);
      final before = controller.moveCount;

      final outcome = controller.move(MetroMoveDirection.left);

      expect(outcome.accepted, isFalse);
      expect(controller.moveCount, before);
    });
  });
}
