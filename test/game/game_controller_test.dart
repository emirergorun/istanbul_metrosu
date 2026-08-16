import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:istanbul_metro_game/features/game/application/game_controller.dart';
import 'package:istanbul_metro_game/features/game/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/game/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/game/domain/board.dart';
import 'package:istanbul_metro_game/features/game/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/game/domain/scoring.dart';
import 'package:istanbul_metro_game/features/game/domain/game_state.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

Journey journeyFor(String originId, String destinationId) {
  final service = RouteService(MetroFixture.load());
  final result = service.estimate(originId, destinationId);
  return result.journey!;
}

/// Taksim -> Levent: 8 dk, "Kısa" profil (engel yok, undo 1).
Journey shortJourney() => journeyFor('m2_taksim', 'm2_levent');

GameController controllerFor(Journey journey, {int seed = 42, Duration? tick}) {
  return GameController(
    journey: journey,
    generator: PieceGenerator(random: Random(seed)),
    tick: tick ?? const Duration(seconds: 1),
  );
}

void main() {
  group('başlangıç durumu', () {
    test('oyun hazır durumda ve skor sıfır', () {
      final controller = controllerFor(shortJourney());
      addTearDown(controller.dispose);

      expect(controller.status, GameStatus.ready);
      expect(controller.session.score, 0);
      expect(controller.tray.length, 3);
      expect(controller.session.undoLeft, 1);
      expect(controller.session.isFirstRun, isTrue);
    });

    test('start ile oyun başlar', () {
      final controller = controllerFor(shortJourney());
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.status, GameStatus.playing);
    });
  });

  group('hamle', () {
    test('geçerli hamle skoru artırır ve tepsi slotunu boşaltır', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      final piece = controller.tray[0]!;
      final outcome = controller.place(0, 0, 0);

      expect(outcome.accepted, isTrue);
      expect(controller.session.score, piece.size);
      expect(controller.tray[0], isNull);
      expect(controller.board.filledCount, piece.size);
      expect(controller.session.placedPieces, 1);
    });

    test('oyun başlamadan hamle kabul edilmez', () {
      final controller = controllerFor(shortJourney());
      addTearDown(controller.dispose);

      expect(controller.place(0, 0, 0).accepted, isFalse);
    });

    test('çakışan hamle reddedilir ve state değişmez', () {
      // Şekil rastgeleliğini kaldırmak için hep 1x1 üreten generator.
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
      )..start();
      addTearDown(controller.dispose);

      expect(controller.place(0, 3, 3).accepted, isTrue);
      final scoreAfterFirst = controller.session.score;

      // Aynı hücreye ikinci parça konamaz.
      expect(controller.place(1, 3, 3).accepted, isFalse);
      expect(controller.session.score, scoreAfterFirst);
      expect(controller.board.filledCount, 1);
      expect(controller.tray[1], isNotNull);
    });

    test('board dışına hamle reddedilir', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      expect(controller.place(0, 100, 100).accepted, isFalse);
      expect(controller.place(0, -1, 0).accepted, isFalse);
      expect(controller.board.filledCount, 0);
    });

    test('boş tepsi slotuna hamle reddedilir', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      expect(controller.place(0, 4, 4).accepted, isFalse);
    });

    test('geçersiz tepsi indeksi reddedilir', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      expect(controller.place(-1, 0, 0).accepted, isFalse);
      expect(controller.place(9, 0, 0).accepted, isFalse);
    });

    test('üç parça bitince yeni tepsi gelir', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      var refilled = false;
      for (var i = 0; i < 3; i++) {
        final piece = controller.tray[i];
        if (piece == null) continue;
        final position = findFirstLegalPosition(controller.board, piece);
        if (position == null) continue;
        final outcome = controller.place(i, position.row, position.col);
        refilled = refilled || outcome.trayRefilled;
      }

      expect(refilled, isTrue);
      expect(controller.tray.where((p) => p != null).length, 3);
    });
  });

  group('undo', () {
    test('son hamleyi geri alır ve hakkı azaltır', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      expect(controller.canUndo, isTrue);

      final undone = controller.undo();

      expect(undone, isTrue);
      expect(controller.session.score, 0);
      expect(controller.board.filledCount, 0);
      expect(controller.tray[0], isNotNull);
      expect(controller.session.undoLeft, 0);
      expect(controller.canUndo, isFalse);
    });

    test('undo hakkı olmayan profilde çalışmaz', () {
      // Sevk edilen profillerin hepsinde artık undo hakkı var; kuralın
      // kendisini doğrulamak için hakkı sıfır olan bir profil kuruyoruz.
      final base = shortJourney();
      final controller = controllerFor(
        Journey(
          origin: base.origin,
          destination: base.destination,
          estimatedSeconds: base.estimatedSeconds,
          stopCount: base.stopCount,
          lineId: base.lineId,
          difficulty: const DifficultyProfile(
            id: 'no_undo',
            label: 'Undosuz',
            minMinutes: 0,
            maxMinutes: null,
            initialBlockerRatio: 0,
            hardPieceWeight: 0.1,
            undoCount: 0,
          ),
        ),
      )..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      expect(controller.canUndo, isFalse);
      expect(controller.undo(), isFalse);
    });

    test('uzun yolculukta geri alma hakkı vardır', () {
      // Regresyon: uzun rotalarda undo hakkı 0'dı; artık en zor durumda
      // oyuncunun elinde en çok araç olmalı.
      final controller = controllerFor(
        journeyFor('m2_yenikapi', 'm2_haciosman'), // 32 dk, "Uzun"
      )..start();
      addTearDown(controller.dispose);

      expect(controller.session.undoLeft, greaterThan(0));
      controller.place(0, 0, 0);
      expect(controller.canUndo, isTrue);
      expect(controller.undo(), isTrue);
    });
  });

  group('duraklatma', () {
    test('pause ve resume durumu değiştirir', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      controller.pause();
      expect(controller.status, GameStatus.paused);

      // Duraklatılmışken hamle kabul edilmez.
      expect(controller.place(0, 0, 0).accepted, isFalse);

      controller.resume();
      expect(controller.status, GameStatus.playing);
    });

    test('restart temiz bir oturum başlatır', () {
      final controller = controllerFor(shortJourney())..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      controller.restart();

      expect(controller.session.score, 0);
      expect(controller.board.filledCount, 0);
      expect(controller.status, GameStatus.playing);
    });

    test('restart geçilecek rekoru depodan tazeler', () async {
      // Regresyon: rekor ekran açılırken bir kez okunuyordu. Sonuç panelinden
      // "tekrar oyna" denince ekran yeniden kurulmadığı için ikinci oyun,
      // az önce kırılan ESKİ rekoru hedefliyor ve ilk hamlede "rekoru geçtin"
      // bildirimi çıkıyordu.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();
      await store.submitRouteScore(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        score: 10,
      );

      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        store: store,
        recordToBeat: store.bestScoreForRoute('m2_taksim', 'm2_levent'),
      )..start();
      addTearDown(controller.dispose);

      expect(controller.session.recordToBeat, 10);

      // Oyun sırasında rekor kırılır ve depoya yazılır.
      await store.submitRouteScore(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        score: 60,
      );

      controller.restart();

      expect(
        controller.session.recordToBeat,
        60,
        reason: 'yeni oyun güncel rekoru hedeflemeli',
      );
      expect(
        controller.session.recordBeaten,
        isFalse,
        reason: 'yeni oyun rekor geçilmemiş başlamalı',
      );
    });
  });

  group('oyun sonu', () {
    test('otomatik oynanan oyun geçerli bir bitişle sonlanır', () {
      // Soak test: tahta dolana kadar ilk legal konuma oyna.
      final controller = controllerFor(shortJourney(), seed: 2024)..start();
      addTearDown(controller.dispose);

      var moves = 0;
      while (!controller.status.isFinished && moves < 5000) {
        var placed = false;
        for (var i = 0; i < controller.tray.length; i++) {
          final piece = controller.tray[i];
          if (piece == null) continue;
          final position = findFirstLegalPosition(controller.board, piece);
          if (position == null) continue;
          controller.place(i, position.row, position.col);
          placed = true;
          moves++;
          break;
        }
        if (!placed) break;
      }

      expect(controller.status.isFinished, isTrue);
      expect(moves, greaterThan(0));

      if (controller.status == GameStatus.gameOver) {
        expect(hasAnyLegalMove(controller.board, controller.tray), isFalse);
      } else {
        expect(controller.session.score, greaterThanOrEqualTo(260));
      }
    });

    test('game over yalnızca gerçekten hamle kalmayınca gelir', () {
      // Invaryant: oyun `gameOver` ile bittiyse tepsideki hiçbir parça
      // tahtaya sığmıyor olmalı. Çok tohum + tüm zorluk profilleriyle taranır.
      var gameOvers = 0;

      for (final route in <List<String>>[
        <String>['m2_taksim', 'm2_osmanbey'], // Mini
        <String>['m2_taksim', 'm2_levent'], // Kısa
        <String>['m4_kadikoy', 'm4_kozyatagi'], // Standart
        <String>['m2_yenikapi', 'm2_haciosman'], // Uzun
        <String>['m4_kadikoy', 'm4_sabiha_gokcen_havalimani'], // Maraton
      ]) {
        for (var seed = 0; seed < 25; seed++) {
          final controller = controllerFor(
            journeyFor(route[0], route[1]),
            seed: seed,
          )..start();

          var moves = 0;
          while (controller.status == GameStatus.playing && moves < 3000) {
            var placed = false;
            for (var i = 0; i < controller.tray.length; i++) {
              final piece = controller.tray[i];
              if (piece == null) continue;
              final position = findFirstLegalPosition(controller.board, piece);
              if (position == null) continue;
              controller.place(i, position.row, position.col);
              placed = true;
              moves++;
              break;
            }
            if (!placed) break;
          }

          if (controller.status == GameStatus.gameOver) {
            gameOvers++;
            expect(
              hasAnyLegalMove(controller.board, controller.tray),
              isFalse,
              reason:
                  'seed $seed / ${route[0]}->${route[1]}: hamle varken '
                  'oyun bitti\n${controller.board}',
            );
          }
          controller.dispose();
        }
      }

      expect(gameOvers, greaterThan(0), reason: 'hiç game over üretilmedi');
    });

    test('rekoru geçmek oyunu bitirmez, tek final varıştır', () {
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        recordToBeat: 20,
      )..start();
      addTearDown(controller.dispose);

      var beatEvents = 0;
      var moves = 0;
      while (moves < 2000 && controller.status == GameStatus.playing) {
        final piece = controller.tray.firstWhere((p) => p != null)!;
        final index = controller.tray.indexOf(piece);
        final position = findFirstLegalPosition(controller.board, piece);
        if (position == null) break;
        if (controller.place(index, position.row, position.col).beatRecord) {
          beatEvents++;
        }
        moves++;
        if (controller.session.score > 60) break;
      }

      expect(controller.session.recordBeaten, isTrue);
      expect(
        controller.status,
        GameStatus.playing,
        reason: 'rekoru geçmek oyunu durdurmamalı',
      );
      expect(
        beatEvents,
        1,
        reason: 'rekor bildirimi yalnızca bir kez tetiklenmeli',
      );
    });

    test('ilk yolculukta rekor bildirimi tetiklenmez', () {
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
      )..start();
      addTearDown(controller.dispose);

      expect(controller.session.isFirstRun, isTrue);
      for (var i = 0; i < 5; i++) {
        expect(controller.place(i % 3, i, 0).beatRecord, isFalse);
      }
      expect(controller.session.recordBeaten, isFalse);
    });
  });

  group('rekor', () {
    test('rekor rota bazında tutulur, yön ayırmaz', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();

      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        store: store,
      )..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      controller.abandon();
      await store.submitRouteScore(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        score: 42,
      );

      expect(store.bestScoreForRoute('m2_taksim', 'm2_levent'), 42);
      expect(
        store.bestScoreForRoute('m2_levent', 'm2_taksim'),
        42,
        reason: 'ters yön aynı rekoru paylaşmalı',
      );
      expect(
        store.bestScoreForRoute('m2_taksim', 'm2_osmanbey'),
        0,
        reason: 'farklı rotalar birbirine karışmamalı',
      );
    });

    test('son rota hatırlanır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalStore();
      await store.init();

      expect(store.lastRoute, isNull);
      await store.rememberRoute('m4_kadikoy', 'm4_kozyatagi');

      expect(store.lastRoute?.originId, 'm4_kadikoy');
      expect(store.lastRoute?.destinationId, 'm4_kozyatagi');
    });
  });

  group('durak bonusu', () {
    test('durak geçilirken line temizlendiyse bonus gelir', () async {
      // Taksim -> Levent: 4 durak. Sayaç hızlandırılır.
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      // Bir satır temizle: 1x1 parçalarla 8 hücrelik satırı doldur.
      for (var c = 0; c < 8; c++) {
        final index = controller.tray.indexWhere((p) => p != null);
        controller.place(index, 0, c);
      }
      expect(controller.session.clearedRows, 1, reason: 'satır temizlenmeli');

      final scoreBeforeStation = controller.session.score;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.session.stationsPassed == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.session.stationsPassed, greaterThan(0));
      expect(
        controller.session.score,
        scoreBeforeStation + ScoreRules.stationBonus,
      );
      expect(controller.stationBonusPulse, 1);
    });

    test('geri alınan temizlik durak bonusu kazandırmaz', () async {
      // Regresyon: undo board ve skoru geri alıyor ama "bu duraktan beri
      // temizlik yapıldı" bayrağını bırakıyordu. Oyuncu satırı temizleyip
      // geri alarak bedava +25 kasabiliyordu.
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      for (var c = 0; c < 8; c++) {
        final index = controller.tray.indexWhere((p) => p != null);
        controller.place(index, 0, c);
      }
      expect(controller.session.clearedRows, 1);

      expect(controller.undo(), isTrue);
      expect(controller.session.clearedRows, 0, reason: 'temizlik geri alındı');

      final scoreBefore = controller.session.score;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.session.stationsPassed == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.session.stationsPassed, greaterThan(0));
      expect(
        controller.session.score,
        scoreBefore,
        reason: 'geri alınan temizlik bonus vermemeli',
      );
      expect(controller.stationBonusPulse, 0);
    });

    test('line temizlenmediyse durak bonusu gelmez', () async {
      final controller = GameController(
        journey: shortJourney(),
        generator: _DotGenerator(),
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      controller.place(0, 3, 3); // temizlik yok
      final scoreBefore = controller.session.score;

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.session.stationsPassed == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.session.stationsPassed, greaterThan(0));
      expect(controller.session.score, scoreBefore);
      expect(controller.stationBonusPulse, 0);
    });
  });

  group('yolculuk ilerlemesi', () {
    test('aktif oyun süresi ilerledikçe progress artar', () async {
      final controller = controllerFor(
        journeyFor('m2_taksim', 'm2_osmanbey'), // 2 dk = 120 sn
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(controller.session.elapsedSeconds, greaterThan(0));
      expect(controller.session.progress, greaterThan(0));
      expect(controller.session.progress, lessThanOrEqualTo(1));
    });

    test('duraklatılmışken süre işlemez', () async {
      final controller = controllerFor(
        shortJourney(),
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.pause();
      final frozen = controller.session.elapsedSeconds;

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.session.elapsedSeconds, frozen);
    });

    test('yolculuk süresi dolunca varış durumuna geçer', () async {
      final controller = controllerFor(
        journeyFor('m2_taksim', 'm2_osmanbey'), // 120 sn
        tick: const Duration(milliseconds: 1),
      )..start();
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.status != GameStatus.arrived &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.status, GameStatus.arrived);
      expect(controller.session.progress, 1.0);
      expect(controller.session.remainingSeconds, 0);
    });
  });
}

/// Testlerde şekil rastgeleliğini kaldırmak için hep 1x1 üreten generator.
class _DotGenerator extends PieceGenerator {
  _DotGenerator() : super(random: Random(1));

  @override
  BlockPiece nextPiece(DifficultyProfile profile) =>
      PieceShapes.dot.withColor(1);

  @override
  List<BlockPiece> generateTray(Board board, DifficultyProfile profile) =>
      <BlockPiece>[nextPiece(profile), nextPiece(profile), nextPiece(profile)];
}
