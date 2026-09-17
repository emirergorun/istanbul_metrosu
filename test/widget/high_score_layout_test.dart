import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/combo.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/streak.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/saved_game_helpers.dart';

class _SilentAudio extends AudioService {
  @override
  void play(GameSound sound) {}
}

/// Yüksek sayılar arayüzü bozmamalı.
///
/// Combo payı ve streak bonusu skorları eskisinden hızlı büyütüyor. Dar bir
/// telefonda yedi haneli skor, üç haneli combo ve seri rozetleri aynı satıra
/// sığmazsa HUD taşar — testte bu bir istisna olarak düşer.
void main() {
  final metro = MetroFixture.load();

  Future<void> pumpGame(
    WidgetTester tester, {
    required SavedGame saved,
    required Size size,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: saved.session.journey, resumeFrom: saved),
        ),
      ),
    );
  }

  SavedGame hugeSession({
    required int score,
    required int combo,
    required int streak,
  }) {
    final routes = RouteService(metro);
    final journey = routes
        .estimate('m4_kadikoy', 'm4_sabiha_gokcen_havalimani')
        .journey!;
    final dot = PieceShapes.byId('dot')!.withColor(1);

    return savedGameOf(
      GameSession.initial(
        journey: journey,
        board: Board.empty(),
        tray: <BlockPiece?>[dot, dot, dot],
      ).copyWith(
        comboState: ComboState(
          value: combo,
          movesSinceLastClear: 1,
          best: combo,
        ),
        streakState: StreakState(value: streak, best: streak, piecesInSet: 2),
      ),
      score: score,
      stationsPassed: 5,
      recordToBeat: 1,
    );
  }

  testWidgets('yedi haneli skor ve üç haneli sayılar dar ekranda taşmaz', (
    tester,
  ) async {
    await pumpGame(
      tester,
      // iPhone SE genişliği: desteklenen en dar ekran.
      size: const Size(375, 667),
      saved: hugeSession(score: 9876543, combo: 128, streak: 256),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'HUD taşmamalı (RenderFlex overflow istisna olarak düşer)',
    );
    // Skor hem HUD'da hem duraklatma panelinde görünür.
    expect(find.text('9.876.543'), findsWidgets);
    expect(find.text('×128'), findsOneWidget);
    expect(find.text('seri 256'), findsOneWidget);
  });

  testWidgets('dokuz haneli skor da sığar', (tester) async {
    await pumpGame(
      tester,
      size: const Size(375, 667),
      saved: hugeSession(score: 987654321, combo: 9, streak: 9),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('987.654.321'), findsWidgets);
  });

  testWidgets('geniş ekranda da taşma yok', (tester) async {
    await pumpGame(
      tester,
      size: const Size(1290, 2796),
      saved: hugeSession(score: 1234567, combo: 42, streak: 99),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('sıfır combo ve seride okuma hiç çizilmez', (tester) async {
    await pumpGame(
      tester,
      size: const Size(375, 667),
      saved: hugeSession(score: 120, combo: 0, streak: 0),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('×'), findsNothing);
    expect(find.textContaining('seri'), findsNothing);
  });

  testWidgets('oyun sonu paneli durak ve seri satırlarını gösterir', (
    tester,
  ) async {
    // Tahta dolu, tepside tek hücrelik parça bile sığmıyor. Kayıttan dönen
    // oyun duraklatılmış açılır; "devam et" denince motor hamlesiz tahtayı
    // görüp oyunu bitirir ve sonuç paneli çıkar.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
    final dot = PieceShapes.byId('dot')!.withColor(1);

    final saved = savedGameOf(
      GameSession.initial(
        journey: journey,
        board: Board.fromGrid(
          List<List<int>>.generate(8, (_) => List<int>.filled(8, 1)),
        ),
        tray: <BlockPiece?>[dot, dot, dot],
      ).copyWith(
        comboState: const ComboState(value: 0, best: 7),
        streakState: const StreakState(value: 0, best: 11),
        clearedRows: 12,
        clearedColumns: 9,
      ),
      score: 4820,
      stationsPassed: 3,
    );

    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey, resumeFrom: saved),
        ),
      ),
    );
    await tester.pump();

    // Duraklatma panelinden devam: hamle kalmadığı için oyun kapanır.
    await tester.tap(find.text('DEVAM ET'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Geçilen durak'), findsOneWidget);
    // Rekor kırıldıysa satırın sonuna yıldız eklenir.
    expect(find.textContaining('3 / ${journey.stopCount}'), findsOneWidget);
    expect(find.text('En iyi combo'), findsOneWidget);
    expect(find.textContaining('x7'), findsOneWidget);
    expect(find.text('En iyi seri'), findsOneWidget);
    expect(find.textContaining('11'), findsWidgets);
    expect(find.text('Temizlenen satır / sütun'), findsOneWidget);
    expect(find.text('12 / 9'), findsOneWidget);
  });
}
