import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_status_bar.dart';
import 'package:istanbul_metro_game/features/session/widgets/station_banner.dart';

import '../helpers/metro_fixture.dart';

/// Durak bildirimi artık **altı oyunun ortak katmanında**.
///
/// Eskiden yalnızca Blok Metro'da vardı; diğer beş oyunda tren ilerleme
/// çubuğunda sessizce kayıyor, geçilen durak hiçbir yerde söylenmiyordu.
/// "Bir sonraki durak" hesabı da beş ekrana kelimesi kelimesine
/// kopyalanmıştı.
void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  GameController controllerFor(String origin, String destination) {
    final journey = routes.estimate(origin, destination).journey!;
    return GameController(
      journey: journey,
      generator: PieceGenerator(random: Random(1)),
      tick: const Duration(days: 1),
    );
  }

  Future<void> pumpBar(WidgetTester tester, GameController controller) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => JourneyStatusBar(
                run: controller,
                lineStations: metro.stationsOfLine(controller.journey.lineId),
                accent: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('yolculuk başında mevcut durak biniş durağı', (tester) async {
    final controller = controllerFor('m2_taksim', 'm2_levent');
    addTearDown(controller.dispose);
    await pumpBar(tester, controller);

    expect(find.text('Taksim'), findsOneWidget);
    expect(find.text('Sonraki durak: Osmanbey'), findsOneWidget);
  });

  testWidgets('durak geçilince adı bildirilir', (tester) async {
    final controller = controllerFor('m2_taksim', 'm2_levent')..start();
    await pumpBar(tester, controller);

    expect(find.byType(StationBanner), findsOneWidget);
    expect(find.text('Osmanbey'), findsNothing);

    final perStop =
        controller.journey.estimatedSeconds ~/ controller.journey.stopCount;
    controller.debugAdvanceSeconds(perStop + 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Osmanbey'),
      findsWidgets,
      reason: 'varılan durağın adı hem şeritte hem üst etikette',
    );
    expect(find.text('Sonraki durak: Şişli-Mecidiyeköy'), findsOneWidget);

    // Motorun sayacı testin sonunda asılı kalmasın.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('bildirim kalıcı değil, kısa süre sonra kalkar', (tester) async {
    final controller = controllerFor('m2_taksim', 'm2_levent')..start();
    await pumpBar(tester, controller);

    final perStop =
        controller.journey.estimatedSeconds ~/ controller.journey.stopCount;
    controller.debugAdvanceSeconds(perStop + 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(StationBanner.visibleFor);
    await tester.pump(const Duration(milliseconds: 400));

    // Şerit kalktı; üst etiket durağı göstermeye devam ediyor.
    expect(find.text('Osmanbey'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('hiç durak geçilmeden yok edilince çökmez', (tester) async {
    // Regresyon: animasyon denetleyicisi tembel alandaydı ve şerit hiç
    // gösterilmeden `dispose` çağrıldığında ilk kez orada kuruluyordu.
    // Flutter, yok edilmekte olan ağaçta ticker kurmaya izin vermiyor.
    final controller = controllerFor('m2_taksim', 'm2_levent');
    addTearDown(controller.dispose);
    await pumpBar(tester, controller);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('tek duraklık yolculukta da çizilir', (tester) async {
    final stations = metro.stationsOfLine('M2');
    final controller = controllerFor(stations[0].id, stations[1].id);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);

    expect(tester.takeException(), isNull);
    expect(find.byType(JourneyStatusBar), findsOneWidget);
  });
}
