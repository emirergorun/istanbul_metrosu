import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/simit_catch/application/simit_catch_controller.dart';
import 'package:istanbul_metro_game/features/games/simit_catch/presentation/simit_catch_painter.dart';
import 'package:istanbul_metro_game/features/games/simit_catch/presentation/simit_catch_screen.dart';
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
          home: SimitCatchScreen(journey: shortJourney()),
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

  Finder scene() => find.byWidgetPredicate(
    (Widget w) => w is CustomPaint && w.painter is SimitCatchPainter,
  );

  SimitCatchController controllerOf(WidgetTester tester) =>
      (tester.widget<CustomPaint>(scene()).painter! as SimitCatchPainter)
          .controller;

  testWidgets('oyun ekranı hatasız açılır', (tester) async {
    await pumpGame(tester);

    expect(scene(), findsOneWidget);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(find.text('Dokun: kanat çırp'), findsOneWidget);
    expect(find.text('SERİ'), findsOneWidget);
    expect(find.text('SİMİT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('sahneye dokunmak kanat çırpar', (tester) async {
    await pumpGame(tester);
    final controller = controllerOf(tester);
    expect(controller.isWaiting, isTrue);

    await tester.tap(scene());
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.flapPulse, 1);
    expect(controller.isWaiting, isFalse);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kanat çırpılmazsa oyun biter ve sonuç paneli çıkar', (
    tester,
  ) async {
    await pumpGame(tester);

    await tester.tap(scene());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.textContaining(RegExp('Denize düştün|Simidi kaçırdın')),
      findsOneWidget,
    );
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
    await pumpGame(tester, size: const Size(750, 1334));
    await tester.tap(scene());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(JourneyProgressBar), findsOneWidget);

    await disposeGame(tester);
  });
}
