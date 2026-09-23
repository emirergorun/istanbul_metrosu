import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/crossing/presentation/crossing_screen.dart';
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

  Future<void> pumpGame(
    WidgetTester tester, {
    Size size = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = size;
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
          home: CrossingScreen(journey: shortJourney()),
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

  /// HUD'daki "SIRA" çipinin değeri.
  String rowCounter(WidgetTester tester) {
    final chip = find
        .ancestor(of: find.text('SIRA'), matching: find.byType(Column))
        .first;
    final texts = tester.widgetList<Text>(
      find.descendant(of: chip, matching: find.byType(Text)),
    );
    return texts.last.data!;
  }

  testWidgets('oyun ekranı hatasız açılır', (tester) async {
    await pumpGame(tester);

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(find.textContaining('Dokun'), findsOneWidget);
    // Sıra sayacı: oyuncunun ne kadar ilerlediğini gösteren tek yer.
    expect(find.text('SIRA'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('dokunmak bir sıra ileri götürür', (tester) async {
    await pumpGame(tester);

    expect(rowCounter(tester), '0');

    await tester.tap(find.byType(CustomPaint).first, warnIfMissed: false);
    // Zıplama 0,14 saniye; birkaç kare sonra varmış olmalı.
    await tester.pump(const Duration(milliseconds: 250));

    expect(rowCounter(tester), '1');
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('yukarı kaydırmak da ileri götürür', (tester) async {
    await pumpGame(tester);

    expect(rowCounter(tester), '0');

    await tester.drag(
      find.byType(CustomPaint).first,
      const Offset(0, -60),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(rowCounter(tester), '1');
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('duraklatma paneli açılır ve devam edilebilir', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    expect(find.text('Duraklatıldı'), findsOneWidget);

    await tester.tap(find.text('DEVAM ET'));
    await tester.pump();

    expect(find.text('Duraklatıldı'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('dar ekranda taşma yok', (tester) async {
    // iPhone SE: oyun alanı sabit oranlı, HUD ve şerit onun etrafında.
    await pumpGame(tester, size: const Size(750, 1334));

    expect(tester.takeException(), isNull);
    expect(find.byType(JourneyProgressBar), findsOneWidget);

    await disposeGame(tester);
  });
}
