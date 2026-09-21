import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/core/widgets/pressable.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_cover.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_cover_art.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_detail_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_select_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/presentation/lane_runner_screen.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/merge_drop_screen.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/presentation/metro_merge_screen.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/presentation/metro_quiz_screen.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/presentation/rail_flight_screen.dart';
import 'package:istanbul_metro_game/features/games/train_snake/presentation/train_snake_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

/// V2 akışı: rota → **galeri** → kapak → **detay** → OYNA → oyun.
///
/// Kapağa dokunmak oyunu artık doğrudan başlatmıyor; arada bilinçli bir
/// karar ekranı var. Testler o iki adımı birlikte doğruluyor: doğru detay
/// açılıyor mu, OYNA doğru oyunu başlatıyor mu.
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

  Future<void> pumpGallery(WidgetTester tester) async {
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
        // Metro Bilgi soru havuzu olmadan açılmaz: boş havuz ürün hatası,
        // sessizce boş soru üretmek yerine hata verir.
        questions: TriviaFixture.repository(perCategory: 4),
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

  Future<void> scrollToGame(WidgetTester tester, MiniGame game) async {
    final finder = find.text(game.name);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        280,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.pump();
  }

  /// Oyunun kartı — başlık kapağın içinde, kartın tamamı dokunmatik.
  Finder cardOf(MiniGame game) => find.ancestor(
    of: find.text(game.name),
    matching: find.byType(GameCoverCard),
  );

  /// Galeriden detaya, detaydan oyuna.
  Future<void> launch(WidgetTester tester, MiniGame game) async {
    await scrollToGame(tester, game);
    // Başlık kapağın **üstünde**: adı görünür olduğunda kartın merkezi hâlâ
    // ekranın altında kalabiliyor. Kartın kendisi görünür kılınmalı.
    await tester.ensureVisible(cardOf(game));
    await tester.pumpAndSettle();
    await tester.tap(cardOf(game));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget, reason: game.id);
    await tester.tap(find.text('OYNA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Izgaranın sonuna kadar kaydırır.
  ///
  /// Kartlar tembel kuruluyor: kilitli üç oyun listenin sonunda ve ekranda
  /// olmadıkları sürece widget ağacında da yoklar.
  Future<void> scrollToBottom(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 6; i++) {
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
  }

  group('Galeri', () {
    testWidgets('yolculuk şeridi ve tüm oyunlar görünür', (tester) async {
      await pumpGallery(tester);

      expect(find.text('OYUNUNU SEÇ'), findsOneWidget);
      expect(find.text('Taksim → Levent'), findsOneWidget);
      expect(find.text('M2'), findsOneWidget);

      // Oynanabilir oyunların adı kapağın içinde yazılı.
      for (final game in MiniGames.playable) {
        await scrollToGame(tester, game);
        expect(find.text(game.name), findsOneWidget, reason: game.id);
      }

      // Kilitli oyunların **adı yazılmıyor**: üç yer tutucu ad oyuncuya
      // verilmemiş bir söz veriyordu. Kartlar yine de duruyor.
      await scrollToBottom(tester);
      for (final game in MiniGames.all.where((g) => !g.isAvailable)) {
        expect(find.text(game.name), findsNothing, reason: game.id);
      }
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is GameCoverArt && w.scene == GameCoverScene.locked,
        ),
        findsWidgets,
      );
    });

    testWidgets('kartlar iki sütuna diziliyor', (tester) async {
      await pumpGallery(tester);

      final cards = find.byType(GameCoverCard);
      expect(cards, findsWidgets);
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));

      // İkinci kart birincinin sağında ve aynı satırda.
      expect(second.left, greaterThan(first.left));
      expect(second.top, closeTo(first.top, 1));
    });

    testWidgets('kartın tamamı dokunmatik, içinde ayrı düğme yok', (
      tester,
    ) async {
      await pumpGallery(tester);

      final card = find.byType(GameCoverCard).first;
      // Kartın içinde tek bir dokunma alanı var: kartın kendisi.
      expect(
        find.descendant(of: card, matching: find.byType(Pressable)),
        findsOneWidget,
      );

      // Kartın köşesine dokunmak da detayı açar.
      final rect = tester.getRect(card);
      await tester.tapAt(rect.topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(GameDetailScreen), findsOneWidget);
    });

    testWidgets('kart metinle doldurulmuyor', (tester) async {
      await pumpGallery(tester);

      final card = find.byType(GameCoverCard).first;
      final texts = find.descendant(of: card, matching: find.byType(Text));
      // Kartta yalnız oyunun adı yazıyor: tanım, rekor ve süre detayda.
      expect(texts, findsOneWidget);
      expect(find.text(MiniGames.blocks.tagline), findsNothing);
    });

    testWidgets('kilitli oyun kilit simgesi taşır ve açılmaz', (tester) async {
      await pumpGallery(tester);

      // Kilit sahnenin kendisinde çiziliyor; ayrı bir simge widget'ı yok.
      await scrollToBottom(tester);
      final lockedCover = find.byWidgetPredicate(
        (Widget w) => w is GameCoverArt && w.scene == GameCoverScene.locked,
      );
      expect(lockedCover, findsWidgets);

      // Kilitli kapak başlık çizmiyor: sahne zaten YAKINDA diyor.
      expect(
        tester
            .widgetList<GameCoverArt>(lockedCover)
            .every((GameCoverArt w) => !w.showTitle),
        isTrue,
      );

      await tester.tap(lockedCover.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(GameDetailScreen), findsNothing);
      expect(find.text('OYUNUNU SEÇ'), findsOneWidget);
    });

    testWidgets('rotayı değiştir geri döner', (tester) async {
      await pumpGallery(tester);

      expect(find.text('Rotayı değiştir'), findsOneWidget);
      await tester.tap(find.text('Rotayı değiştir'));
      await tester.pumpAndSettle();

      // Test ağacında altta rota ekranı yok; galeri kapandı, o kadarı yeter.
      expect(find.text('OYUNUNU SEÇ'), findsNothing);
    });
  });

  group('Galeri → detay → oyun', () {
    testWidgets('kapağa dokunmak oyunu başlatmaz, detayı açar', (tester) async {
      await pumpGallery(tester);

      await tester.tap(find.text(MiniGames.blocks.name));
      await tester.pumpAndSettle();

      expect(find.byType(GameDetailScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.text('SKOR · İLK YOLCULUK'), findsNothing);
    });

    testWidgets('detaydan geri dönünce rota korunur', (tester) async {
      await pumpGallery(tester);

      await tester.tap(find.text(MiniGames.blocks.name));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('OYUNUNU SEÇ'), findsOneWidget);
      expect(find.text('Taksim → Levent'), findsOneWidget);
    });

    testWidgets('yedi oynanabilir oyun OYNA ile doğru ekrana açılır', (
      tester,
    ) async {
      final cases = <MiniGame, Type>{
        MiniGames.blocks: GameScreen,
        MiniGames.metroMerge: MetroMergeScreen,
        MiniGames.railFlight: RailFlightScreen,
        MiniGames.mergeDrop: MergeDropScreen,
        MiniGames.metroQuiz: MetroQuizScreen,
        MiniGames.laneRunner: LaneRunnerScreen,
        MiniGames.trainSnake: TrainSnakeScreen,
      };

      for (final entry in cases.entries) {
        await pumpGallery(tester);
        await launch(tester, entry.key);

        expect(find.byType(entry.value), findsOneWidget, reason: entry.key.id);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}
