import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/train_snake/domain/train_snake_state.dart';
import 'package:istanbul_metro_game/features/games/train_snake/presentation/train_snake_screen.dart';
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
          home: TrainSnakeScreen(journey: journey ?? shortJourney()),
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

    // Hat rozeti ve hedef sayacı: sahne görseli kaldırıldıktan sonra
    // oyuncunun hangi hatta olduğunu ve hedefe ne kadar kaldığını
    // söyleyen tek yer bu satır.
    expect(find.text('M1'), findsWidgets);
    expect(find.text('0 / $trainSnakeGoalPassengers'), findsOneWidget);
    expect(find.textContaining('Hedefe'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
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

  testWidgets('duraklatınca ilerlemeyi durdurur', (tester) async {
    await pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Tren durdu'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('ok tuşlarıyla yön değiştirilebilir', (tester) async {
    await pumpGame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kaydırma hareketiyle yön değiştirilebilir', (tester) async {
    await pumpGame(tester);

    await tester.fling(
      find.byType(CustomPaint).first,
      const Offset(0, 120),
      500,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('duvara çarpınca oyun biter ve sonuç ekranı çıkar', (
    tester,
  ) async {
    // Tren ilk girdiye kadar bekler; sol tuş başlangıç yönüne (sağ) tam
    // ters olduğu için reddedilir ve treni başlatmaz. Yukarı geçerli bir
    // dönüş: tren sekiz adımda üst duvara varır.
    await pumpGame(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Tren durdu'), findsOneWidget);
    expect(find.textContaining('Toplanan yolcu'), findsOneWidget);
    expect(find.textContaining('Ulaşılan hat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });
}
