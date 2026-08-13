import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/data/metro/metro_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hiç hat içermeyen geçerli bir veri seti.
const String _emptyDataset = '{"lines": []}';

void main() {
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
  });

  testWidgets('hat listesi boşken açılış ekranı çökmez', (tester) async {
    // Regresyon: `_TrafficPainter` boş listede `i % lines.length` ile
    // sıfıra bölüyordu.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(
        store: store,
        audio: AudioService(),
        metro: MetroDataset.parse(_emptyDataset),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('OYUNA BAŞLA'), findsOneWidget);
  });

  testWidgets('hat listesi boşken planlayıcı boş durum gösterir', (
    tester,
  ) async {
    // Regresyon: `_activeLine` boş listede `.first` çağırıp StateError
    // atıyordu.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(
        store: store,
        audio: AudioService(),
        metro: MetroDataset.parse(_emptyDataset),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OYUNA BAŞLA'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hat bulunamadı'), findsOneWidget);
  });

  testWidgets('veri yüklenemezse hata ekranı çıkar', (tester) async {
    await tester.pumpWidget(const MetroDataErrorApp());
    await tester.pumpAndSettle();

    expect(find.text('Metro verisi yüklenemedi'), findsOneWidget);
  });
}
