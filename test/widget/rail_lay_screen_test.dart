import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/data/rail_lay_levels.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/presentation/rail_lay_painter.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/presentation/rail_lay_screen.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_host.dart';
import 'package:istanbul_metro_game/features/session/journey_save.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  late LocalStore store;
  final metro = MetroFixture.load();

  Future<void> resetStore({int? level}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'rail_lay_level_v2': ?level,
    });
    store = LocalStore();
    await store.init();
  }

  setUp(() => resetStore());

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
          home: RailLayScreen(journey: shortJourney()),
        ),
      ),
    );
    await tester.pump();
  }

  /// Tahta: yolculuk şeridindeki tren de bir `CustomPaint`, türünden bulunur.
  final board = find.byWidgetPredicate(
    (Widget w) => w is CustomPaint && w.painter is RailLayPainter,
  );

  /// Timer'ların testin sonunda sızmaması için ekranı söker.
  Future<void> disposeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('oyun ekranı hatasız açılır', (tester) async {
    await pumpGame(tester);

    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(board, findsOneWidget);
    expect(find.text('BÖLÜM'), findsOneWidget);
    expect(find.textContaining('Kaydır'), findsOneWidget);
    expect(find.text('BAŞTAN AL'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kaldığı bölümden açılır', (tester) async {
    await resetStore(level: 17);
    await pumpGame(tester);

    expect(find.textContaining('17 · '), findsOneWidget);

    await disposeGame(tester);
  });

  testWidgets('kaydırmak metroyu yürütür, kareler döşenir', (tester) async {
    await pumpGame(tester);

    // 1. bölümün çözümünün ilk kayışı kesin olarak kare döşer.
    final first = RailLayLevels.byNumber(1).solution.first;
    final offset = Offset(first.delta.x * 80.0, first.delta.y * 80.0);
    await tester.drag(board, offset, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('kare döşendi'), findsOneWidget);
    expect(find.textContaining('1 / '), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('baştan al döşemeyi sıfırlar', (tester) async {
    await pumpGame(tester);
    final first = RailLayLevels.byNumber(1).solution.first;
    await tester.drag(
      board,
      Offset(first.delta.x * 80.0, first.delta.y * 80.0),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('kare döşendi'), findsOneWidget);

    await tester.tap(find.text('BAŞTAN AL'));
    await tester.pump();

    // Döşeme ve hamle sayısı sıfırlandı: ilk bölümde ipucu geri gelir.
    expect(find.textContaining('kare döşendi'), findsNothing);
    expect(find.textContaining('Kaydır'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('bölüm bitince yolculuk puanı hemen kaydedilir', (tester) async {
    // Bölüm numarası kalıcı kayda anında yazılıyor. Yolculuk kaydı beş
    // saniyelik kalp atışını beklerse, arada zorla kapanan uygulamada
    // bölüm ilerlemiş ama puanı kaybolmuş olurdu.
    final routes = RouteService(metro);
    final host = JourneyController(store: store, routes: routes);
    final session = host.start(shortJourney());
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: routes,
        child: JourneyScope(
          controller: host,
          session: session,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: RailLayScreen(journey: shortJourney()),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. bölümü kendi çözümüyle bitir; her kayış yarım saniyeden kısa.
    for (final direction in RailLayLevels.byNumber(1).solution) {
      await tester.drag(
        board,
        Offset(direction.delta.x * 80.0, direction.delta.y * 80.0),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(session.scoreOf('rail_lay'), greaterThan(0));
    final saved = JourneySave.decode(store.savedJourney!)!;
    expect(saved.scoreByGame['rail_lay'], session.scoreOf('rail_lay'));
    expect(store.railLayLevel, 2);

    await disposeGame(tester);
    host.dispose();
  });

  testWidgets('bölüm sonu yazısı tahtanın altında, raylara binmez', (
    tester,
  ) async {
    // Yazı önce tahtanın ortasına biniyor, döşenmiş rayların üstünde
    // okunmuyordu.
    await pumpGame(tester);

    final solution = RailLayLevels.byNumber(1).solution;
    for (var i = 0; i < solution.length; i++) {
      final direction = solution[i];
      await tester.drag(
        board,
        Offset(direction.delta.x * 80.0, direction.delta.y * 80.0),
        warnIfMissed: false,
      );
      // Son kayıştan sonra kısa bekle: kutlama 0,9 saniye sürüyor.
      await tester.pump(
        Duration(milliseconds: i == solution.length - 1 ? 300 : 400),
      );
    }

    final praise = find.text('HAT AÇILDI!');
    expect(praise, findsOneWidget);
    expect(
      tester.getRect(praise).top,
      greaterThanOrEqualTo(tester.getRect(board).bottom),
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

    await disposeGame(tester);
  });

  testWidgets('büyük bölüm dar ekranda taşmaz', (tester) async {
    await resetStore(level: 60);
    await pumpGame(tester, size: const Size(750, 1334));

    expect(tester.takeException(), isNull);
    expect(find.byType(JourneyProgressBar), findsOneWidget);

    await disposeGame(tester);
  });
}
