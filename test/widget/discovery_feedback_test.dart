import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/application/journey_discovery.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/run_discovery_summary.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_status_bar.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);

  Journey journeyOf(String origin, String destination) =>
      routes.estimate(origin, destination).journey!;

  JourneyDiscovery runFor(Journey journey, DiscoveryController state) =>
      JourneyDiscovery(journey: journey, discovery: state, gameId: 'blocks');

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  group('Sonuç paneli keşif özeti', () {
    testWidgets('yeni keşifler adlarıyla listelenir', (tester) async {
      final state = DiscoveryController(catalog: catalog);
      final run = runFor(journeyOf('m2_taksim', 'm2_levent'), state)
        ..reportReached(2);

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      expect(find.text('YENİ KEŞİFLER'), findsOneWidget);
      expect(find.text('Taksim'), findsOneWidget);
      expect(find.text('Osmanbey'), findsOneWidget);
      expect(find.text('Şişli-Mecidiyeköy'), findsOneWidget);
    });

    testWidgets('üçten fazla keşif özetlenir', (tester) async {
      final state = DiscoveryController(catalog: catalog);
      final run = runFor(journeyOf('m2_yenikapi', 'm2_haciosman'), state)
        ..reportReached(5);

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      // Altı durak keşfedildi: üçü ad olarak, kalanı sayı olarak.
      expect(find.text('+3 diğer'), findsOneWidget);
    });

    testWidgets('yeni keşif yokken bölüm çizilmez', (tester) async {
      final state = DiscoveryController(catalog: catalog)
        ..discoverAll(<String>['taksim', 'osmanbey', 'sisli_mecidiyekoy']);
      final run = runFor(journeyOf('m2_taksim', 'm2_levent'), state)
        ..reportReached(2);

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      expect(run.newStationCount, 0);
      expect(find.text('YENİ KEŞİFLER'), findsNothing);
      // Küresel ilerleme yine görünür.
      expect(find.text('İstanbul keşfi'), findsOneWidget);
    });

    testWidgets('yeniden başlatılan yolculukta oturum toplamı da yazılır', (
      tester,
    ) async {
      final state = DiscoveryController(catalog: catalog);
      final run = runFor(journeyOf('m2_taksim', 'm2_levent'), state)
        ..reportReached(2)
        // Oyuncu yarıda yeniden başlattı: üç durak kalıcı, ama koşu
        // defteri sıfırlandı.
        ..reset()
        ..reportReached(3);

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      expect(run.newStationCount, 1);
      expect(find.text('Bu oturumda toplam 4 yeni istasyon'), findsOneWidget);
    });

    testWidgets('yeniden başlatma yoksa oturum satırı çıkmaz', (tester) async {
      final state = DiscoveryController(catalog: catalog);
      final run = runFor(journeyOf('m2_taksim', 'm2_levent'), state)
        ..reportReached(2);

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      expect(find.textContaining('Bu oturumda toplam'), findsNothing);
    });

    testWidgets('tamamlanan hat bildirilir', (tester) async {
      final state = DiscoveryController(catalog: catalog);
      final run =
          runFor(journeyOf('m6_levent', 'm6_bogazici_u_hisarustu'), state)
            ..reportReached(0)
            ..reportArrival();

      await pump(tester, RunDiscoverySummary(run: run, accent: Colors.green));

      expect(find.textContaining('M6 tamamlandı'), findsOneWidget);
    });
  });

  group('Oyun içi durak şeridi', () {
    GameController controllerFor(Journey journey, JourneyDiscovery? run) {
      return GameController(
        journey: journey,
        discovery: run,
        generator: PieceGenerator(random: Random(1)),
        tick: const Duration(days: 1),
      );
    }

    Future<void> pumpBar(WidgetTester tester, GameController controller) async {
      await pump(
        tester,
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => JourneyStatusBar(
            run: controller,
            lineStations: metro.stationsOfLine(controller.journey.lineId),
            accent: Colors.green,
          ),
        ),
      );
    }

    testWidgets('ilk kez ulaşılan durak YENİ rozeti alır', (tester) async {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final state = DiscoveryController(catalog: catalog);
      final run = runFor(journey, state);
      final controller = controllerFor(journey, run)..start();
      addTearDown(controller.dispose);

      await pumpBar(tester, controller);
      controller.debugAdvance(journey.estimatedSeconds / 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      // Sayaç durdurulmazsa test sonunda bekleyen zamanlayıcı kalır.
      controller.pause();

      expect(find.text('YENİ'), findsOneWidget);
    });

    testWidgets('bilinen durakta rozet çıkmaz', (tester) async {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final state = DiscoveryController(catalog: catalog)
        ..discoverAll(catalog.routeStationIds(journey));
      final run = runFor(journey, state);
      final controller = controllerFor(journey, run)..start();
      addTearDown(controller.dispose);

      await pumpBar(tester, controller);
      controller.debugAdvance(journey.estimatedSeconds / 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      controller.pause();

      expect(find.text('YENİ'), findsNothing);
      // Şerit yine durağın adını söyler.
      expect(find.textContaining('Osmanbey'), findsWidgets);
    });
  });
}
