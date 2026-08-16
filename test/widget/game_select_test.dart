import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_select_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  late LocalStore store;
  final metro = MetroFixture.load();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
  });

  Future<void> pumpSelect(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final journey = RouteService(
      metro,
    ).estimate('m2_taksim', 'm2_levent').journey!;

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        child: MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: GameSelectScreen(journey: journey),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('yolculuk özeti ve tüm oyunlar listelenir', (tester) async {
    await pumpSelect(tester);

    // Hangi yolculuk için seçim yapıldığı görünmeli.
    expect(find.text('Taksim → Levent'), findsOneWidget);
    expect(find.text('M2'), findsOneWidget);

    for (final game in MiniGames.all) {
      expect(find.text(game.name), findsOneWidget, reason: game.id);
    }
  });

  testWidgets('kilitli oyunlar "YAKINDA" rozetiyle işaretlenir', (
    tester,
  ) async {
    await pumpSelect(tester);

    final lockedCount = MiniGames.all.where((g) => !g.isAvailable).length;
    expect(lockedCount, greaterThan(0), reason: 'katalogda kilitli oyun yok');
    expect(find.text('YAKINDA'), findsNWidgets(lockedCount));
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(lockedCount));
  });

  testWidgets('kilitli oyuna dokunmak hiçbir şey yapmaz', (tester) async {
    await pumpSelect(tester);

    final locked = MiniGames.all.firstWhere((g) => !g.isAvailable);
    await tester.tap(find.text(locked.name));
    await tester.pumpAndSettle();

    // Hâlâ seçim ekranındayız; oyun açılmadı.
    expect(find.text('Oyun seç'), findsOneWidget);
    expect(find.text('SKOR · İLK YOLCULUK'), findsNothing);
  });

  testWidgets('açık oyuna dokunmak oyunu başlatır', (tester) async {
    await pumpSelect(tester);

    final open = MiniGames.all.firstWhere((g) => g.isAvailable);
    await tester.tap(find.text(open.name));
    await tester.pumpAndSettle();

    expect(find.text('SKOR · İLK YOLCULUK'), findsOneWidget);
  });
}
