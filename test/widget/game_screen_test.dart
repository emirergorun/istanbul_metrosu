import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/data/metro/metro_repository.dart';
import 'package:istanbul_metro_game/features/game/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/game/presentation/widgets/board_view.dart';
import 'package:istanbul_metro_game/features/game/presentation/widgets/piece_tray.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/progress/journey_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalStore store;
  const metro = BundledMetroRepository();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();
  });

  Journey shortJourney() =>
      const RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;

  Future<void> pumpGame(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        metro: metro,
        routeService: const RouteService(metro),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: shortJourney()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Timer'ların testin sonunda sızmaması için ekranı söker.
  Future<void> disposeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('oyun ekranı açılır', (tester) async {
    await pumpGame(tester);

    expect(find.text('SKOR'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('/ 260'), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byType(JourneyProgressBar), findsOneWidget);

    await disposeGame(tester);
  });

  testWidgets('metro ilerleme alanı rota bilgisini gösterir', (tester) async {
    await pumpGame(tester);

    expect(find.text('Taksim'), findsOneWidget);
    expect(find.text('Levent'), findsOneWidget);
    expect(find.text('M2'), findsOneWidget);

    await disposeGame(tester);
  });

  testWidgets('tepside 3 sürüklenebilir parça var', (tester) async {
    await pumpGame(tester);

    expect(find.byType(Draggable<TrayDragData>), findsNWidgets(3));

    await disposeGame(tester);
  });

  testWidgets('pause paneli açılır ve devam edilebilir', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Devam et'), findsOneWidget);

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Duraklatıldı'), findsNothing);

    await disposeGame(tester);
  });

  testWidgets('parça board’a sürüklenince skor artar', (tester) async {
    await pumpGame(tester);

    final boardRect = tester.getRect(find.byType(BoardView));
    final draggable = find.byType(Draggable<TrayDragData>).first;
    final start = tester.getCenter(draggable);

    // Parça parmağın üstünde göründüğü için board'un alt-orta bölgesine
    // bırakmak her şekil için güvenli bir hedeftir.
    final target = Offset(boardRect.center.dx, boardRect.bottom - 8);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing, reason: 'skor güncellenmedi');

    await disposeGame(tester);
  });
}
