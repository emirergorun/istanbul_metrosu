import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/metro/metro_repository.dart';
import 'package:istanbul_metro_game/features/game/application/game_controller.dart';
import 'package:istanbul_metro_game/features/game/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/game/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/game/domain/board.dart';
import 'package:istanbul_metro_game/features/game/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/game/domain/game_state.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

Journey journeyFor(String originId, String destinationId) {
  const service = RouteService(BundledMetroRepository());
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
      expect(controller.session.targetScore, 260);
      expect(controller.session.undoLeft, 1);
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
      // Yenikapı -> Hacıosman: 29 dk, "Uzun" profil, undo yok.
      final controller = controllerFor(
        journeyFor('m2_yenikapi', 'm2_haciosman'),
      )..start();
      addTearDown(controller.dispose);

      controller.place(0, 0, 0);
      expect(controller.canUndo, isFalse);
      expect(controller.undo(), isFalse);
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

    test('hedef skora ulaşınca zafer, sonra endless devam edilebilir', () {
      final controller = controllerFor(shortJourney(), seed: 7)..start();
      addTearDown(controller.dispose);

      var moves = 0;
      while (controller.status == GameStatus.playing && moves < 5000) {
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

      if (controller.status == GameStatus.victory) {
        expect(controller.session.targetReached, isTrue);
        controller.continueEndless();
        expect(controller.status, GameStatus.playing);
      }
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
