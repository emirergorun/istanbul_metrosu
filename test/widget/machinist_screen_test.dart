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

  testWidgets('ekran açılır: kumanda kolu, hız göstergesi, durak kartı', (
    tester,
  ) async {
    await pumpGame(tester);

    expect(find.byType(MachinistMasterLever), findsOneWidget);
    expect(find.byType(MachinistSpeedometer), findsOneWidget);
    expect(find.text('TAKİP'), findsOneWidget);
    expect(find.text('SONRAKİ İSTASYON'), findsOneWidget);
    // Hattın ikinci istasyonu: Taksim'den sonra Osmanbey.
    expect(find.text('Osmanbey'), findsOneWidget);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kol yukarı itilince tren kalkar, aşağı çekilince fren', (
    tester,
  ) async {
    final controller = await pumpGame(tester);
    final lever = tester.getRect(find.byType(MachinistMasterLever));

    // Kolu yuvanın tepesine (P4) sürükle ve bırak.
    final gesture = await tester.startGesture(lever.center);
    await tester.pump();
    await gesture.moveTo(Offset(lever.center.dx, lever.top + 4));
    await gesture.up();
    await tester.pump();
    expect(controller.leverNotch, 4);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.speed, greaterThan(0));

    // Aşağı çek: fren kademesine oturur ve orada kalır.
    final brake = await tester.startGesture(lever.center);
    await tester.pump();
    await brake.moveTo(Offset(lever.center.dx, lever.bottom - 4));
    await brake.up();
    await tester.pump();
    expect(controller.leverNotch, -4);
    expect(controller.braking, isTrue);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kamera düğmesi kabine geçirir ve seçimi hatırlar', (
    tester,
  ) async {
    await pumpGame(tester);

    await tester.tap(find.text('TAKİP'));
    await tester.pump();
    expect(find.text('KABİN'), findsOneWidget);
    expect(store.machinistCabView, isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('KABİN'));
    await tester.pump();
    expect(find.text('TAKİP'), findsOneWidget);
    expect(store.machinistCabView, isFalse);

    await disposeGame(tester);
  });
}
