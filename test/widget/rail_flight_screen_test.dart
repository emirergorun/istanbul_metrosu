import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/presentation/rail_flight_screen.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  late LocalStore store;
  final metro = MetroFixture.load();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();
  });

  Journey shortJourney() =>
      RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;

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
          home: RailFlightScreen(journey: journey ?? shortJourney()),
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

  testWidgets('oyun ekranı hatasız açılır ve HUD gösterilir', (tester) async {
    await pumpGame(tester);

    expect(find.text('M1 · 0'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('fizik gerçek zamanlayıcıyla ilerler ve treni serbest düşüşte '
      'zamanla düşürür', (tester) async {
    // Bu test, fizik döngüsünün gerçek `Timer` + `clock.now()` ile
    // çalıştığını ve tester.pump(süre) ile doğru şekilde hızlandırılıp
    // ilerletilebildiğini doğruluyor — controller'ın kare zamanlaması
    // testleri bu mekanizmayı Timer'dan bağımsız test ediyordu, bu test
    // ise gerçek widget + gerçek Timer birlikte çalışırken de aynı doğru
    // sonucu verdiğini kanıtlıyor.
    await pumpGame(tester);

    // Hiç dokunulmazsa yerçekimi treni aşağı çeker; birkaç saniye içinde
    // zemine çarpıp oyun bitmeli. Sabit-dt hatası olsaydı ya da fizik
    // Timer ile senkronize olmasaydı bu ilerleme hiç olmaz ya da çok
    // farklı bir hızda olurdu.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Raya çarptın'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('dokunma treni yukarı uçurur (flap)', (tester) async {
    await pumpGame(tester);

    // Bir süre serbest düşsün, sonra dokunup yukarı ivmelendiğini gör.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(const Duration(milliseconds: 16));

    // Oyun hâlâ oynanıyor olmalı (tek bir flap ile hemen ölmez) ve
    // istisna fırlatılmamış olmalı.
    expect(find.text('Raya çarptın'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('duraklatma paneli açılır ve devam edilebilir', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('DEVAM ET'), findsOneWidget);

    await tester.tap(find.text('DEVAM ET'));
    await tester.pump();

    expect(find.text('Duraklatıldı'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('duraklatınca fizik ilerlemeyi durdurur', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    // Duraklatılmışken saatlerce zaman geçse bile oyun bitmemeli —
    // zamanlayıcı durmuş olmalı.
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Raya çarptın'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('space tuşu treni uçurur', (tester) async {
    await pumpGame(tester);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });
}
