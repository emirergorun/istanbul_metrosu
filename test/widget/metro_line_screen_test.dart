import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/metro_line/domain/metro_line_state.dart';
import 'package:istanbul_metro_game/features/games/metro_line/presentation/metro_line_screen.dart';
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
          home: MetroLineScreen(journey: shortJourney()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> disposeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// HUD'daki "KALAN" çipinin değeri — tahtadaki tren sayısı.
  String remaining(WidgetTester tester) {
    final chip = find
        .ancestor(of: find.text('KALAN'), matching: find.byType(Column))
        .first;
    final texts = tester
        .widgetList<Text>(find.descendant(of: chip, matching: find.byType(Text)))
        .toList();
    return texts.last.data!;
  }

  testWidgets('oyun ekranı hatasız açılır ve HUD gösterilir', (tester) async {
    await pumpGame(tester);

    expect(find.text('SEVİYE'), findsOneWidget);
    expect(find.text('KALAN'), findsOneWidget);
    expect(find.byType(JourneyProgressBar), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('kalan hak jetonları çizilir', (tester) async {
    await pumpGame(tester);

    expect(
      find.byIcon(Icons.confirmation_number_rounded),
      findsNWidgets(3),
      reason: 'üç hak da görünmeli',
    );

    await disposeGame(tester);
  });

  testWidgets('tahtaya dokunmak oyunu ilerletir', (tester) async {
    await pumpGame(tester);
    final before = remaining(tester);

    // Tahtanın her hücresine sırayla dokun: en az biri bir trene denk
    // gelip onu çıkarmalı. (Hangi hücrede tren olduğu rastgele.)
    final rect = tester.getRect(find.byKey(boardKey));
    var changed = false;
    const n = metroLineMinSize;
    for (var row = 0; row < n && !changed; row++) {
      for (var col = 0; col < n && !changed; col++) {
        await tester.tapAt(
          Offset(
            rect.left + rect.width * (col + 0.5) / n,
            rect.top + rect.height * (row + 0.5) / n,
          ),
        );
        await tester.pump();
        changed = remaining(tester) != before;
      }
    }

    expect(
      changed,
      isTrue,
      reason: 'tahtanın hiçbir hücresine dokunmak bir şey değiştirmedi',
    );
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('dar ekranda taşma olmaz', (tester) async {
    // iPhone SE: tahta kare olduğu için taşma riski önce burada görünür.
    await pumpGame(tester, size: const Size(750, 1334));

    expect(tester.takeException(), isNull);
    expect(find.text('SEVİYE'), findsOneWidget);

    await disposeGame(tester);
  });
}
