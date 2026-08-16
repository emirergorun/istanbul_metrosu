import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/session/widgets/arrival_sequence.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/widgets/board_view.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/widgets/piece_tray.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  late LocalStore store;
  final metro = MetroFixture.load();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Tanıtım yalnızca ilk açılışta çıkar; testlerde kapalı.
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
  });

  Journey shortJourney() =>
      RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;

  /// Taksim -> Osmanbey: 2 dk. Varışı test etmek için en kısa rota.
  Journey miniJourney() =>
      RouteService(metro).estimate('m2_taksim', 'm2_osmanbey').journey!;

  Future<void> pumpGame(WidgetTester tester, {Journey? journey}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey ?? shortJourney()),
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

    // Rotada rekor yoksa HUD "ilk yolculuk" der; hedef skor gösterilmez.
    expect(find.text('SKOR · İLK YOLCULUK'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
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

  testWidgets('en alt satıra parça bırakılabilir', (tester) async {
    // Regresyon: parça parmağın üstünde gösterildiği için en alt satıra
    // yerleştirmek parmağın board'un alt kenarının altına inmesini gerektirir.
    // Bırakma hedefi yalnızca board olduğunda bu satır oynanamıyordu.
    await pumpGame(tester);

    final boardRect = tester.getRect(find.byType(BoardView));
    final cellSize = boardRect.width / 8;
    final draggable = find.byType(Draggable<TrayDragData>).first;

    final gesture = await tester.startGesture(tester.getCenter(draggable));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(
      Offset(boardRect.center.dx, boardRect.bottom + cellSize * 0.5),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    final board = tester.widget<BoardView>(find.byType(BoardView)).board;
    final lastRow = board.rows - 1;
    final filledInLastRow = <int>[
      for (var c = 0; c < board.cols; c++)
        if (!board.isEmptyAt(lastRow, c)) c,
    ];

    expect(
      filledInLastRow,
      isNotEmpty,
      reason: 'en alt satıra parça yerleşmedi',
    );

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

  group('varış sahnesi', () {
    testWidgets('yolculuk bitince tren gelir ve sonuç açılır', (tester) async {
      await pumpGame(tester, journey: miniJourney());

      // 2 dakikalık yolculuk: sayaç dolsun.
      await tester.pump(const Duration(minutes: 3));

      expect(
        find.byType(ArrivalSequence),
        findsOneWidget,
        reason: 'varışta tören sahnesi oynamalı',
      );

      // Sahne kontrolörü ilk kareden sonra başlar (hareket-azaltma kontrolü
      // için); bir kare ver, sonra süreyi ilerlet.
      await tester.pump();
      await tester.pump(ArrivalSequence.defaultDuration);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('DURAĞA GELDİN'), findsOneWidget);
      expect(find.text('TEKRAR OYNA'), findsOneWidget);
      // Peron tabelasındaki durak adı.
      expect(find.text('Osmanbey'), findsWidgets);

      await disposeGame(tester);
    });

    testWidgets('sahne dokununca atlanabilir', (tester) async {
      await pumpGame(tester, journey: miniJourney());
      await tester.pump(const Duration(minutes: 3));

      // Sahnenin ilk anında sonuç henüz görünmez.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('TEKRAR OYNA'), findsNothing);

      await tester.tap(find.byType(ArrivalSequence));
      // Bir frame jesti çözer, sonraki frame atlama animasyonunu bitirir.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DURAĞA GELDİN'), findsOneWidget);

      await disposeGame(tester);
    });
  });

  group('yarım kalan oyun', () {
    testWidgets('kayıt yazılır, geri yüklenir ve duraklatılmış açılır', (
      tester,
    ) async {
      await pumpGame(tester);

      // Bir hamle yap; kayıt her yerleştirmede güncellenir.
      final boardRect = tester.getRect(find.byType(BoardView));
      final draggable = find.byType(Draggable<TrayDragData>).first;
      final gesture = await tester.startGesture(tester.getCenter(draggable));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(Offset(boardRect.center.dx, boardRect.bottom - 8));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(store.hasSavedGame, isTrue, reason: 'oyun kaydedilmedi');

      final restored = GameSnapshot.decode(
        store.savedGame!,
        RouteService(metro),
      );
      expect(restored, isNotNull);
      expect(restored!.score, greaterThan(0));
      expect(restored.board.filledCount, greaterThan(0));
      expect(
        restored.status,
        GameStatus.paused,
        reason: 'kayıttan dönen oyun duraklatılmış başlamalı',
      );

      await disposeGame(tester);
    });

    testWidgets('oyun bitince kayıt silinir', (tester) async {
      await pumpGame(tester, journey: miniJourney());
      await tester.pump(const Duration(minutes: 3)); // varış
      await tester.pump();

      expect(
        store.hasSavedGame,
        isFalse,
        reason: 'biten oyunun kaydı kalmamalı',
      );

      await disposeGame(tester);
    });
  });
}
