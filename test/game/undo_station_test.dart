import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/board_helpers.dart';
import '../helpers/metro_fixture.dart';

/// Hamlenin kazandırdığı saniyeden güvenle büyük bir pay.
///
/// İyi oyun yolculuğa saniye katıyor; tek satır temizliği bile durağı
/// geçirebilecek kadar kazandırabilir. Test bu iki olayı ayrı tutmak
/// istediği için başlangıç noktası kazançtan uzağa konur.
const int _margin = 20;

void main() {
  test('durak geçildikten sonra hamle geri alınamaz', () {
    // Regresyon: geri alma `stationsPassed`'i de eski değerine döndürüyordu.
    // Durak bir sonraki saniyede yeniden işleniyor, geri alınmış tahtadaki
    // kalabalık satır bedavaya boşalıyor, parça da tepsiye geri geliyordu.
    final journey = RouteService(
      MetroFixture.load(),
    ).estimate('m2_taksim', 'm2_levent').journey!;
    final perStop = journey.estimatedSeconds ~/ journey.stopCount;
    final dot = PieceShapes.byId('dot')!.withColor(1);

    final controller = GameController(
      journey: journey,
      resumeFrom: GameSession.initial(
        journey: journey,
        board: boardFrom(<String>[
          'XXXXXXX.',
          '........',
          '........',
          '........',
          '........',
          '........',
          '........',
          '........',
        ]),
        tray: <BlockPiece?>[dot, dot, dot],
        // Durağa yeterince uzakta başla: temizliğin kazandırdığı saniye tek
        // başına durağı geçirmesin, hamle ile durak geçişi ayrı kalsın.
      ),
      resumeProgress: ResumedProgress(
        score: 0,
        elapsedSeconds: perStop - _margin,
        stationsPassed: 0,
        recordToBeat: 0,
        recordBeaten: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.start();

    // Satırı tamamlayan hamle; ardından tren durağı geçer.
    final outcome = controller.place(0, 0, 7);
    expect(outcome.didClear, isTrue);
    expect(controller.canUndo, isTrue);
    controller.debugAdvanceSeconds(_margin - outcome.journeySeconds);
    expect(controller.stationsPassed, 1);
    final scoreAfterStation = controller.score;

    expect(controller.canUndo, isFalse);
    expect(controller.undo(), isFalse);

    controller.debugAdvanceSeconds(1);
    expect(controller.stationsPassed, 1);
    expect(controller.score, scoreAfterStation);
    expect(controller.tray.whereType<BlockPiece>(), hasLength(2));
  });

  test('temizliğin kazandırdığı saniye durağı geçirirse geri alma kapanır', () {
    // Yolculuk kazancı süreyi ilerlettiği için durağı hamlenin **kendisi**
    // geçirebilir. Bu durumda da geri alma kapanmalı: geri alma durağın
    // öncesine dönemez.
    final journey = RouteService(
      MetroFixture.load(),
    ).estimate('m2_taksim', 'm2_levent').journey!;
    final perStop = journey.estimatedSeconds ~/ journey.stopCount;
    final dot = PieceShapes.byId('dot')!.withColor(1);

    final controller = GameController(
      journey: journey,
      resumeFrom: GameSession.initial(
        journey: journey,
        board: boardFrom(<String>[
          'XXXXXXX.',
          '........',
          '........',
          '........',
          '........',
          '........',
          '........',
          '........',
        ]),
        tray: <BlockPiece?>[dot, dot, dot],
        // Durağa tam bir saniye kala: tek satır temizliği yeter.
      ),
      resumeProgress: ResumedProgress(
        score: 0,
        elapsedSeconds: perStop - 1,
        stationsPassed: 0,
        recordToBeat: 0,
        recordBeaten: false,
      ),
    );
    addTearDown(controller.dispose);
    controller.start();

    final outcome = controller.place(0, 0, 7);

    expect(outcome.journeySeconds, greaterThanOrEqualTo(1));
    expect(controller.stationsPassed, 1);
    expect(controller.canUndo, isFalse);
    expect(controller.undo(), isFalse);
  });
}
