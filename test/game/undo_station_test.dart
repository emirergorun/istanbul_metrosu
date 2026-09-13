import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/board_helpers.dart';
import '../helpers/metro_fixture.dart';

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
      ).copyWith(elapsedSeconds: perStop - 1),
    );
    addTearDown(controller.dispose);
    controller.start();

    // Satırı tamamlayan hamle; ardından tren durağı geçer. Temizlikten
    // sonra kalabalık satır kalmadığı için durakta satır boşalmaz.
    expect(controller.place(0, 0, 7).didClear, isTrue);
    expect(controller.canUndo, isTrue);
    controller.debugAdvanceSeconds(1);
    expect(controller.session.stationsPassed, 1);
    final scoreAfterStation = controller.score;

    expect(controller.canUndo, isFalse);
    expect(controller.undo(), isFalse);

    controller.debugAdvanceSeconds(1);
    expect(controller.session.stationsPassed, 1);
    expect(controller.stationClearPulse, 0);
    expect(controller.score, scoreAfterStation);
    expect(controller.tray.whereType<BlockPiece>(), hasLength(2));
  });
}
