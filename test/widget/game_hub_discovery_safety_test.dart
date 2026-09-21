import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_detail_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_select_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

/// V2 ekranlarında gezinmek **keşif üretmez**.
///
/// Bu sınır ürünün belkemiği: İstanbul Keşfi "oynadığın kadar keşfet"
/// demek. Galeriyi karıştırmak, bir oyunun kapağına bakmak ya da yardımı
/// açmak durak keşfettirseydi ilerleme oynamadan da birikir ve sistem
/// anlamını kaybederdi.
void main() {
  late LocalStore store;
  late DiscoveryController discovery;
  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
    discovery = DiscoveryController(catalog: catalog, store: store);
    addTearDown(discovery.dispose);
  });

  Future<void> pumpGallery(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        questions: TriviaFixture.repository(perCategory: 4),
        discovery: discovery,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: GameSelectScreen(journey: journey),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ertelenmiş bildirim ve diske yazma varsa onları da bekler.
  Future<void> settleDiscovery(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('galeriyi açmak keşif üretmez', (tester) async {
    await pumpGallery(tester);
    await settleDiscovery(tester);

    expect(discovery.discoveredCount, 0);
    expect(store.discoveredStationIds, isEmpty);
  });

  testWidgets('galeriyi kaydırmak keşif üretmez', (tester) async {
    await pumpGallery(tester);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settleDiscovery(tester);

    expect(discovery.discoveredCount, 0);
  });

  testWidgets('tanıtım ekranını açmak keşif üretmez', (tester) async {
    await pumpGallery(tester);

    await tester.tap(find.text(MiniGames.blocks.name));
    await settleDiscovery(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);
    expect(discovery.discoveredCount, 0);
    expect(store.discoveredStationIds, isEmpty);
  });

  testWidgets('yedi oyunun tanıtımını gezmek keşif üretmez', (tester) async {
    for (final game in MiniGames.playable) {
      await pumpGallery(tester);
      final finder = find.text(game.name);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          280,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder, warnIfMissed: false);
      await settleDiscovery(tester);

      expect(discovery.discoveredCount, 0, reason: game.id);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('yardımı açmak keşif üretmez', (tester) async {
    await pumpGallery(tester);

    final finder = find.text(MiniGames.trainSnake.name);
    await tester.scrollUntilVisible(
      finder,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nasıl oynanır?'));
    await settleDiscovery(tester);

    expect(find.text('NASIL OYNANIR?'), findsOneWidget);
    expect(discovery.discoveredCount, 0);
  });

  testWidgets('geri dönmek keşif üretmez', (tester) async {
    await pumpGallery(tester);

    await tester.tap(find.text(MiniGames.blocks.name));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await settleDiscovery(tester);

    expect(find.text('OYUNUNU SEÇ'), findsOneWidget);
    expect(discovery.discoveredCount, 0);
  });

  testWidgets('OYNA ile oyun başlayınca biniş durağı keşfedilir', (
    tester,
  ) async {
    await pumpGallery(tester);

    await tester.tap(find.text(MiniGames.blocks.name));
    await tester.pumpAndSettle();
    expect(discovery.discoveredCount, 0);

    await tester.tap(find.text('OYNA'));
    await settleDiscovery(tester);

    // V1a aynen çalışıyor: oyun gerçekten başladığında biniş durağı açılır.
    expect(discovery.discoveredCount, 1);
    expect(discovery.isDiscovered('taksim'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
