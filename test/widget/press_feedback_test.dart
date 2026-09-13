import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/core/widgets/pressable.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Menü dokunuşlarının geri bildirimi: **basılı durum + haptik**.
///
/// Bu testler gözle görülmeyen iki kuralı korur: basılı durum ilk karede
/// görünmeli (mürekkep dalgası beklenmemeli) ve titreşim ayarı kapalıyken
/// hiçbir menü dokunuşu titrememeli.
void main() {
  final metro = MetroFixture.load();
  late LocalStore store;
  late List<String> haptics;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();

    haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPressable(
    WidgetTester tester, {
    required VoidCallback? onTap,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Pressable(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: const SizedBox(width: 200, height: 60),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('basılı durum parmak değer değmez görünür', (tester) async {
    await pumpPressable(tester, onTap: () {});

    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    // Tek kare: geri bildirim beklemeden görünmeli.
    await tester.pump();

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('parmak kayınca basılı durum ve titreşim iptal olur', (
    tester,
  ) async {
    await pumpPressable(tester, onTap: () {});

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(haptics, isEmpty, reason: 'kayan parmak dokunuş sayılmaz');
  });

  testWidgets('hareket azaltmada ölçek yok, geri bildirim var', (tester) async {
    await pumpPressable(tester, onTap: () {}, disableAnimations: true);

    expect(find.byType(AnimatedScale), findsNothing);

    Container overlay() => tester.widget<Container>(find.byType(Container));
    expect(overlay().foregroundDecoration, isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();

    expect(overlay().foregroundDecoration, isNotNull);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dokunuş titreşimi ayara bağlı', (tester) async {
    var taps = 0;
    await pumpPressable(tester, onTap: () => taps++);

    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(haptics, <String>['HapticFeedbackType.selectionClick']);

    await store.setHapticsEnabled(false);
    await tester.tap(find.byType(Pressable));
    await tester.pumpAndSettle();

    expect(taps, 2);
    expect(haptics, hasLength(1), reason: 'titreşim kapalıyken sessiz kalmalı');
  });

  testWidgets('pasif alan ne titrer ne basılı görünür', (tester) async {
    await pumpPressable(tester, onTap: null);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();

    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
  });
}
