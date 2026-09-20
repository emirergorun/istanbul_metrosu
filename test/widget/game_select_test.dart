import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/core/widgets/pressable.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_glyph.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_select_screen.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/presentation/lane_runner_screen.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/merge_drop_screen.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/presentation/metro_merge_screen.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/presentation/rail_flight_screen.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/presentation/metro_quiz_screen.dart';
import 'package:istanbul_metro_game/features/games/train_snake/presentation/train_snake_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_status_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/journey_harness.dart';
import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

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

  Future<void> pumpSelect(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1170, 2532);
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
        child: withJourney(
          store: store,
          child: MaterialApp(
            theme: AppTheme.dark(),
            onGenerateRoute: AppRoutes.onGenerateRoute,
            home: GameSelectScreen(journey: journey),
          ),
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
        scrollable: find.byType(Scrollable),
      );
    }
    // Kart listenin kenarında kalmış olabilir (şeridin yüksekliği
    // değişince oluyor): dokunmadan önce tamamen görünür yapılır.
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('yolculuk özeti ve tüm oyunlar listelenir', (tester) async {
    await pumpSelect(tester);

    // Hangi yolculuk için seçim yapıldığı görünmeli.
    expect(find.text('Taksim → Levent'), findsOneWidget);
    // Hat rozeti iki kez: üstteki yolculuk kartında ve canlı yolculuk
    // şeridinde. Şerit oyun seçerken de trenin yol aldığını gösterir.
    expect(find.text('M2'), findsNWidgets(2));
    expect(find.byType(JourneyStatusBar), findsOneWidget);

    for (final game in MiniGames.all) {
      await scrollToGame(tester, game);
      expect(find.text(game.name), findsOneWidget, reason: game.id);
    }
  });

  testWidgets('kilitli oyunlar "YAKINDA" rozetiyle işaretlenir', (
    tester,
  ) async {
    await pumpSelect(tester);

    final lockedGames = MiniGames.all.where((g) => !g.isAvailable).toList();
    expect(lockedGames, isNotEmpty, reason: 'katalogda kilitli oyun yok');
    for (final game in lockedGames) {
      await scrollToGame(tester, game);
      expect(find.text(game.name), findsOneWidget, reason: game.id);
      expect(find.text('YAKINDA'), findsWidgets);
      // Kilit artık stok `Icons.lock_rounded` değil, elle çizilmiş glif.
      // Kontrol edilen şey aynı: kilitli kartta kilit işareti görünmeli.
      expect(
        find.byWidgetPredicate(
          (w) => w is GameGlyphIcon && w.glyph == GameGlyph.locked,
        ),
        findsWidgets,
      );
    }
  });

  testWidgets('kilitli oyuna dokunmak hiçbir şey yapmaz', (tester) async {
    await pumpSelect(tester);

    final locked = MiniGames.all.firstWhere((g) => !g.isAvailable);
    await scrollToGame(tester, locked);
    await tester.tap(find.text(locked.name));
    await tester.pumpAndSettle();

    // Hâlâ seçim ekranındayız; oyun açılmadı.
    expect(find.text('Oyun seç'), findsOneWidget);
    expect(find.text('SKOR · İLK YOLCULUK'), findsNothing);
  });

  testWidgets('açık oyuna dokunmak oyunu başlatır', (tester) async {
    await pumpSelect(tester);

    final open = MiniGames.all.firstWhere((g) => g.isAvailable);
    await tester.tap(find.text(open.name));
    await tester.pumpAndSettle();

    expect(find.text('SKOR · İLK YOLCULUK'), findsOneWidget);
  });

  testWidgets('hat birleştir oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.text(MiniGames.metroMerge.name));
    await tester.pumpAndSettle();

    // Rekor artık her oyunun HUD'unda üstte.
    expect(find.text('SKOR · İLK YOLCULUK'), findsOneWidget);
    expect(find.text('Hat Birleştir'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('ray uçuşu oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.text(MiniGames.railFlight.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('TREN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('hat düşür oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await scrollToGame(tester, MiniGames.mergeDrop);
    await tester.tap(find.text(MiniGames.mergeDrop.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('SIRADAKI'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('metro bilgi oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await scrollToGame(tester, MiniGames.metroQuiz);
    await tester.tap(find.text(MiniGames.metroQuiz.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(MetroQuizScreen), findsOneWidget);
    // Soru metni her oyunda değişir; sabit olan dört şıkkın çizilmesi.
    expect(find.byType(Pressable), findsAtLeastNWidgets(4));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('ray değiştir oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await scrollToGame(tester, MiniGames.laneRunner);
    await tester.tap(find.text(MiniGames.laneRunner.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(LaneRunnerScreen), findsOneWidget);
    expect(find.text('TREN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('yolcu topla oyunu seçimden açılır', (tester) async {
    await pumpSelect(tester);

    await scrollToGame(tester, MiniGames.trainSnake);
    await tester.tap(find.text(MiniGames.trainSnake.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(TrainSnakeScreen), findsOneWidget);
    // HUD çipi + merdivendeki M1 madalyonu: en az bir tane olması yeterli.
    expect(find.text('M1'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('yedi oynanabilir oyun doğru ekrana açılır', (tester) async {
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
      await pumpSelect(tester);
      await scrollToGame(tester, entry.key);
      await tester.tap(find.text(entry.key.name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(entry.value), findsOneWidget, reason: entry.key.id);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('yolculuk puanı şeritte görünür', (tester) async {
    await pumpSelect(tester);

    // Oyun değiştirirken toplam puan burada görünmeli: bu ekranda skoru
    // gösteren başka bir şey yok.
    expect(find.textContaining('YOLCULUK PUANIN'), findsOneWidget);
  });

  testWidgets('dar ekranda şerit taşmaz', (tester) async {
    // iPhone SE: puan satırı eklendiğinde ilk taşma riski burada.
    await pumpSelect(tester, size: const Size(750, 1334));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('YOLCULUK PUANIN'), findsOneWidget);
  });
}
