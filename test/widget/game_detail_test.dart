import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_cover.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_cover_art.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_detail_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

/// Tanıtım ekranı yedi oyun için **tek**: başlık, kapak, tanım, amaç ve
/// kontrol adımları kataloğun kendisinden okunuyor.
void main() {
  late LocalStore store;
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
  });

  Journey journeyOf(String origin, String destination) =>
      routes.estimate(origin, destination).journey!;

  Future<void> pumpDetail(
    WidgetTester tester,
    MiniGame game, {
    Size size = const Size(1170, 2532),
    double pixelRatio = 3,
    Journey? journey,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        questions: TriviaFixture.repository(perCategory: 4),
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: GameDetailScreen(
            journey: journey ?? journeyOf('m2_taksim', 'm2_levent'),
            game: game,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('İçerik', () {
    testWidgets('her oyun kendi adını, tanımını ve amacını gösterir', (
      tester,
    ) async {
      for (final game in MiniGames.playable) {
        await pumpDetail(tester, game);

        expect(find.text(game.name), findsOneWidget, reason: game.id);
        expect(find.text(game.description), findsOneWidget, reason: game.id);
        expect(find.text('AMAÇ'), findsOneWidget, reason: game.id);
        expect(find.text(game.objective), findsOneWidget, reason: game.id);
        expect(find.text('OYNA'), findsOneWidget, reason: game.id);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('kapak galerideki sahneyle aynı', (tester) async {
      await pumpDetail(tester, MiniGames.trainSnake);

      final artwork = tester.widget<GameCoverArt>(find.byType(GameCoverArt));
      expect(artwork.scene, MiniGames.trainSnake.coverScene);
      expect(artwork.identity, MiniGames.trainSnake.color);
      expect(artwork.title, MiniGames.trainSnake.name);
      expect(find.byType(GameCover), findsOneWidget);
    });

    testWidgets('seçili yolculuk görünür', (tester) async {
      await pumpDetail(
        tester,
        MiniGames.blocks,
        journey: journeyOf('m4_kadikoy', 'm4_kozyatagi'),
      );

      expect(find.text('YOLCULUĞUN'), findsOneWidget);
      expect(find.text('M4'), findsOneWidget);
      expect(find.text('Kadıköy'), findsOneWidget);
      expect(find.text('Kozyatağı'), findsOneWidget);
      expect(find.textContaining('durak'), findsOneWidget);
    });

    testWidgets('rekor yoksa rekor satırı çizilmez', (tester) async {
      await pumpDetail(tester, MiniGames.blocks);
      expect(find.textContaining('Bu rotada rekorun'), findsNothing);
    });

    testWidgets('rekor varsa oyun renginde yazılır', (tester) async {
      // Blok Metro rekorunu eski `best_route_` anahtarından okuyor
      // (`LocalStore.legacyRouteGameId`); oyun bazlı anahtarı sınamak için
      // başka bir oyun kullanılıyor.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_seen': true,
        'best_game_route_metro_merge|m2_levent__m2_taksim': 4200,
      });
      store = LocalStore();
      await store.init();

      await pumpDetail(tester, MiniGames.metroMerge);
      // Rekor satırı yolculuk kartının altında; ekranın dibinde kalabilir.
      await tester.scrollUntilVisible(
        find.textContaining('Bu rotada rekorun'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Bu rotada rekorun'), findsOneWidget);
      expect(find.textContaining('4.200'), findsOneWidget);
    });
  });

  group('Nasıl oynanır', () {
    testWidgets('kontrolü açıklama gerektiren oyunda düğme çıkar', (
      tester,
    ) async {
      await pumpDetail(tester, MiniGames.trainSnake);
      expect(find.text('Nasıl oynanır?'), findsOneWidget);

      await tester.tap(find.text('Nasıl oynanır?'));
      await tester.pumpAndSettle();

      expect(find.text('NASIL OYNANIR?'), findsOneWidget);
      for (final step in MiniGames.trainSnake.howToPlay) {
        expect(find.text(step), findsOneWidget);
      }
    });

    testWidgets('sezgisel oyunda düğme hiç çıkmaz', (tester) async {
      await pumpDetail(tester, MiniGames.blocks);
      expect(find.text('Nasıl oynanır?'), findsNothing);
    });
  });

  group('Erişilebilirlik', () {
    testWidgets('OYNA oyunu adıyla duyurur', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDetail(tester, MiniGames.metroQuiz);

      expect(
        find.bySemanticsLabel('Metro Bilgi oyununu başlat'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('yolculuk kartı tek cümlede okunur', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDetail(tester, MiniGames.blocks);

      expect(
        find.bySemanticsLabel(
          RegExp(r'M2 hattı, Taksim durağından Levent durağına'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Ekran boyutları', () {
    const sizes = <String, Size>{
      'küçük telefon (SE)': Size(320, 568),
      'standart telefon': Size(390, 844),
      'geniş telefon (Pro Max)': Size(430, 932),
      'tablet': Size(768, 1024),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} — taşma yok, OYNA erişilebilir', (
        tester,
      ) async {
        await pumpDetail(
          tester,
          // En uzun ad ve en uzun amaç metni olan oyun.
          MiniGames.trainSnake,
          size: entry.value,
          pixelRatio: 1,
        );

        expect(tester.takeException(), isNull);
        // OYNA sabit alt bantta; kaydırma gerektirmeden görünür.
        expect(find.text('OYNA'), findsOneWidget);
        final play = tester.getRect(find.text('OYNA'));
        expect(play.bottom, lessThanOrEqualTo(entry.value.height));
      });
    }

    testWidgets('en büyük yazı ölçeğinde taşma yok', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpDetail(
        tester,
        MiniGames.trainSnake,
        size: const Size(320, 568),
        pixelRatio: 1,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('OYNA'), findsOneWidget);
    });
  });
}
