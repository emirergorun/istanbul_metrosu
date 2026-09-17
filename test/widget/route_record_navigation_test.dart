import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/presentation/widgets/line_selector.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();

  Future<LocalStore> pumpApp(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
      ...prefs,
    });
    final store = LocalStore();
    await store.init();

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(store: store, audio: AudioService(), metro: metro),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('yarım kalan oyunda "Başka oyun seç" oyun seçimine götürür', (
    tester,
  ) async {
    // Regresyon: oyun başlıktaki kayıttan açılınca altta oyun seçimi yoktu;
    // düğme başlık ekranına dönüyordu.
    final journey = RouteService(
      metro,
    ).estimate('m2_taksim', 'm2_levent').journey!;
    final session = GameSession.initial(
      journey: journey,
      board: Board.empty(),
      tray: <BlockPiece?>[
        PieceShapes.dot.withColor(1),
        PieceShapes.h2.withColor(2),
        PieceShapes.v2.withColor(3),
      ],
    );
    final controller = GameController(
      journey: session.journey,
      resumeFrom: session,
      tick: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    await pumpApp(tester, <String, Object>{
      'saved_game': GameSnapshot.encode(controller),
    });

    await tester.tap(find.text('YARIM KALAN OYUN'));
    await tester.pumpAndSettle();
    expect(find.text('Başka oyun seç'), findsOneWidget);

    await tester.tap(find.text('Başka oyun seç'));
    await tester.pumpAndSettle();
    expect(find.text('Oyun seç'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('rota ekranı rekoru oyun adıyla gösterir, "En iyi" tekrarı yok', (
    tester,
  ) async {
    await pumpApp(tester, <String, Object>{
      'best_route_m2_levent__m2_taksim': 120,
      'best_game_route_rail_flight|m2_levent__m2_taksim': 300,
    });
    await tester.tap(find.text('OYUNA BAŞLA'));
    await tester.pumpAndSettle();

    final chip = find.text('M2');
    if (!tester.any(chip)) {
      await tester.dragUntilVisible(
        chip,
        find.byType(LineSelector),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(chip);
    await tester.pumpAndSettle();
    for (final pick in <List<String>>[
      <String>['Bindiğin durağı seç', 'Taksim'],
      <String>['İneceğin durağı seç', 'Levent'],
    ]) {
      await tester.tap(find.text(pick[0]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pick[1]).last);
      await tester.pumpAndSettle();
    }

    expect(find.text('ROTA REKORUN'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('Ray Uçuşu'), findsOneWidget);
    expect(find.textContaining('En iyi'), findsNothing);
  });

  testWidgets('açılıştaki son rota kartı oyun seçimini açar', (tester) async {
    await pumpApp(tester, <String, Object>{
      'last_route_origin': 'm2_taksim',
      'last_route_destination': 'm2_levent',
      'best_game_route_rail_flight|m2_levent__m2_taksim': 300,
    });

    expect(find.text('~9 dk · Ray Uçuşu rekorun 300'), findsOneWidget);

    await tester.tap(find.text('Taksim → Levent'));
    await tester.pumpAndSettle();
    expect(find.text('Oyun seç'), findsOneWidget);
  });
}
