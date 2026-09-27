import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/machinist/application/machinist_controller.dart';
import 'package:istanbul_metro_game/features/games/machinist/presentation/machinist_controls.dart';
import 'package:istanbul_metro_game/features/games/machinist/presentation/machinist_screen.dart';
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

  Future<MachinistController> pumpGame(WidgetTester tester) async {
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
          home: MachinistScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state(find.byType(MachinistScreen)) as dynamic;
    return state.debugController as MachinistController;
  }

  Future<void> disposeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('ekran açılır: iki pedal, hız göstergesi, durak kartı', (
    tester,
  ) async {
    await pumpGame(tester);

    expect(find.byType(MachinistPedal), findsNWidgets(2));
    expect(find.text('İLERİ'), findsOneWidget);
    expect(find.text('FREN'), findsOneWidget);
    expect(find.byType(MachinistSpeedometer), findsOneWidget);
    expect(find.text('SONRAKİ İSTASYON'), findsOneWidget);
    // Hattın ikinci istasyonu: Taksim'den sonra Osmanbey.
    expect(find.text('Osmanbey'), findsOneWidget);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('İLERİ pedalı basılı tutulunca tren kalkar', (tester) async {
    final controller = await pumpGame(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MachinistPedal).first),
    );
    await tester.pump();
    expect(controller.throttleHeld, isTrue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.speed, greaterThan(0));

    await gesture.up();
    await tester.pump();
    expect(controller.throttleHeld, isFalse);

    final brake = await tester.startGesture(
      tester.getCenter(find.byType(MachinistPedal).last),
    );
    await tester.pump();
    expect(controller.brakeHeld, isTrue);
    await brake.up();
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });
}
