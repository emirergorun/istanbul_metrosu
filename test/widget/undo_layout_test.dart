import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/widgets/board_view.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/board_helpers.dart';
import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  Future<Rect> boardRectFor(
    WidgetTester tester, {
    required int undoLeft,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
    final session = GameSession.initial(
      journey: journey,
      board: Board.empty(),
      tray: <BlockPiece?>[
        PieceShapes.dot.withColor(1),
        PieceShapes.h2.withColor(2),
        PieceShapes.v2.withColor(3),
      ],
    ).copyWith(undoLeft: undoLeft, status: GameStatus.paused);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey, resumeFrom: session),
        ),
      ),
    );
    await tester.pump();
    final rect = tester.getRect(find.byType(BoardView));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    return rect;
  }

  testWidgets('geri alma hakkı bitince tahta yerinden oynamaz', (tester) async {
    // Regresyon: hak bitince geri al satırı kalkıyor, oyun alanı büyüyüp
    // tahta aşağı kayıyordu.
    final withUndo = await boardRectFor(tester, undoLeft: 2);
    final withoutUndo = await boardRectFor(tester, undoLeft: 0);
    expect(withoutUndo, withUndo);
  });

  testWidgets('geri alma geçişi her karede hatasız çizilir', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
    );
    final undo = ValueNotifier<BoardUndo?>(
      BoardUndo(
        // Önce: dolu satır + konmuş parça. Sonra: satır geri geldi, parça yok.
        before: boardFrom(<String>[
          '........',
          '........',
          '........',
          '........',
          '........',
          '........',
          '..XX....',
          '........',
        ]),
      ),
    );
    final flash = ValueNotifier<BoardFlash?>(null);
    final preview = ValueNotifier<BoardPreview?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BoardView(
            board: boardFrom(<String>[
              '........',
              '........',
              '........',
              '........',
              '........',
              '........',
              '........',
              'XXXXXXXX',
            ]),
            cellSize: 40,
            preview: preview,
            flash: flash,
            flashAnimation: const AlwaysStoppedAnimation<double>(1),
            undo: undo,
            undoAnimation: controller,
          ),
        ),
      ),
    );
    controller.forward(from: 0);
    for (var i = 0; i <= 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    undo.dispose();
    flash.dispose();
    preview.dispose();
  });
}
