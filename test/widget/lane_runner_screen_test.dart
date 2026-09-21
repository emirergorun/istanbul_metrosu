import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/presentation/lane_runner_screen.dart';
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

  Future<void> pumpGame(WidgetTester tester, {Journey? journey}) async {
    tester.view.physicalSize = const Size(1170, 2532);
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
          home: LaneRunnerScreen(journey: journey ?? shortJourney()),
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

  testWidgets('oyun ekranı hatasız açılır ve HUD gösterilir', (tester) async {
    await pumpGame(tester);

    expect(find.text('M1 · 0'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('gerçek zamanlayıcıyla yolculuk ilerler', (tester) async {
    // Bu test **fizik döngüsünün gerçek Timer + clock.now() ile döndüğünü**
    // ölçüyor: `tester.pump(süre)` ile zaman ilerliyor ve yolculuk de
    // onunla birlikte ilerliyor.
    //
    // Eskiden "sekiz saniyede çarpışma olur" diye yazılmıştı ve tam
    // takımda ara sıra düşüyordu: engellerin rayı tohumlanmamış bir
    // `Random`'dan geliyor, yani çarpışmanın o pencereye düşmesi şansa
    // bağlı. Çarpışmanın kendisi zaten tohumlanmış birim testinde
    // deterministik olarak sınanıyor (`test/game/lane_runner_controller_test.dart`,
    // "çarpışma oyunu bitirir"). Widget testi şansa bakmaz.
    await pumpGame(tester);

    final bar = tester.widget<JourneyProgressBar>(
      find.byType(JourneyProgressBar),
    );
    final before = bar.progress;

    await tester.pump(const Duration(seconds: 3));

    final after = tester
        .widget<JourneyProgressBar>(find.byType(JourneyProgressBar))
        .progress;
    expect(after, greaterThan(before));
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('sağ/sol ray değiştirme çalışır', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.text('Sağ ray'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sol ray'));
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets('duraklatınca fizik ilerlemeyi durdurur', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Kapalı raya girdin'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('ok tuşlarıyla ray değiştirilebilir', (tester) async {
    await pumpGame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });
}
