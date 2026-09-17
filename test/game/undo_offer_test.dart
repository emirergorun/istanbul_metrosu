import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/saved_game_helpers.dart';
import '../helpers/metro_fixture.dart';

void main() {
  final journey = RouteService(
    MetroFixture.load(),
  ).estimate('m2_taksim', 'm2_levent').journey!;

  /// Satranç tahtası: boş hücreler yan yana değil, her satır ve sütunda boş
  /// var. Tek kare konunca hiçbir hat dolmaz; 2'lik parçalar hiç sığmaz.
  Board checkerboard() => Board.fromGrid(<List<int>>[
    for (var r = 0; r < 8; r++)
      <int>[for (var c = 0; c < 8; c++) (r + c).isEven ? kEmptyCell : 1],
  ]);

  GameController lockingController({int? undoLeft}) {
    final session = GameSession.initial(
      journey: journey,
      board: checkerboard(),
      tray: <BlockPiece?>[
        PieceShapes.dot.withColor(1),
        PieceShapes.h2.withColor(2),
        PieceShapes.v2.withColor(3),
      ],
    );
    return GameController(
      journey: journey,
      resumeFrom: undoLeft == null
          ? session
          : session.copyWith(undoLeft: undoLeft),
    )..start();
  }

  test('hamle kalmayınca hak varsa oyun bitmez, geri alma teklif edilir', () {
    final controller = lockingController();
    addTearDown(controller.dispose);
    final undoBefore = controller.session.undoLeft;
    expect(undoBefore, greaterThan(0));

    controller.debugAdvanceSeconds(3);
    expect(controller.place(0, 0, 0).accepted, isTrue);

    expect(controller.status, GameStatus.playing);
    expect(controller.awaitingUndo, isTrue);
    expect(controller.canUndo, isTrue);

    // Karar verilene kadar yolculuk ilerlemez.
    controller.debugAdvanceSeconds(30);
    expect(controller.elapsedSeconds, 3);

    expect(controller.undo(), isTrue);
    expect(controller.awaitingUndo, isFalse);
    expect(controller.session.undoLeft, undoBefore - 1);
    expect(controller.tray.whereType<BlockPiece>(), hasLength(3));

    controller.debugAdvanceSeconds(1);
    expect(controller.elapsedSeconds, 4);
  });

  test('oyuncu teklifi reddederse oyun biter', () {
    final controller = lockingController();
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);

    controller.acceptGameOver();

    expect(controller.status, GameStatus.gameOver);
    expect(controller.awaitingUndo, isFalse);
    expect(controller.canUndo, isFalse);
  });

  test('geri alma hakkı yoksa tepsi yenileme teklif edilir', () {
    final controller = lockingController(undoLeft: 0);
    addTearDown(controller.dispose);

    controller.place(0, 0, 0);

    expect(controller.status, GameStatus.playing);
    expect(controller.awaitingUndo, isTrue);
    expect(controller.canUndo, isFalse);
    expect(controller.canRefillTray, isTrue);
  });

  test('tepsi yenileme oyunu sürdürür ve hakkı tüketir', () {
    final controller = lockingController(undoLeft: 0);
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);

    expect(controller.refillTray(), isTrue);
    expect(controller.trayRefillsLeft, 0);
    expect(controller.awaitingUndo, isFalse);
    // Yeni tepsi tahtaya sığıyorsa oyun devam eder; sığmıyorsa hak
    // kalmadığı için biter. İkisi de geçerli, aradaki "teklif açık"
    // durumu artık olamaz.
    expect(controller.status, anyOf(GameStatus.playing, GameStatus.gameOver));
  });

  test('yenileme hakkı bir kez kullanılır', () {
    final controller = lockingController(undoLeft: 0);
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);

    expect(controller.refillTray(), isTrue);
    expect(controller.refillTray(), isFalse, reason: 'hak tükendi');
    expect(controller.trayRefillsLeft, 0);
  });

  test('teklif açıkken çıkmak oyunu bitirir', () {
    final controller = lockingController();
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);

    controller.abandon();

    expect(controller.status, GameStatus.gameOver);
  });

  test('teklif açıkken duraklat / devam: teklif sürer, sayaç durur', () {
    final controller = lockingController();
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);

    controller.pause();
    controller.resume();

    expect(controller.status, GameStatus.playing);
    expect(controller.awaitingUndo, isTrue);
    controller.debugAdvanceSeconds(10);
    expect(controller.elapsedSeconds, 0);
  });

  test('kayıttan kilitli tahtayla dönen oyun devam edince biter', () {
    // Teklif açıkken uygulama kapanırsa geri alma kaydı diske yazılmaz;
    // oyun hamlesiz tahtayla sonsuza kadar "oynanıyor" kalmamalı.
    final locked = GameSession.initial(
      journey: journey,
      board: checkerboard(),
      tray: <BlockPiece?>[
        null,
        PieceShapes.h2.withColor(2),
        PieceShapes.v2.withColor(3),
      ],
    );
    final saved = savedGameOf(locked);
    final controller = GameController(
      journey: journey,
      resumeFrom: saved.session,
      resumeProgress: saved.progress,
    );
    addTearDown(controller.dispose);

    controller.resume();

    expect(controller.status, GameStatus.gameOver);
  });

  test('geri alma sabit puan bedeli öder', () {
    final controller = lockingController();
    addTearDown(controller.dispose);
    controller.place(0, 0, 0);
    final before = controller.score;

    expect(controller.undo(), isTrue);

    expect(
      controller.score,
      lessThan(before),
      reason: 'hamlenin puanı geri alınır, üstüne sabit bedel biner',
    );
    expect(controller.score, greaterThanOrEqualTo(0));
  });
}
