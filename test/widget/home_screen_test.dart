import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    // iPhone benzeri ekran.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MetroGameApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> selectStation(
    WidgetTester tester, {
    required String fieldHint,
    required String stationName,
  }) async {
    await tester.tap(find.text(fieldHint));
    await tester.pumpAndSettle();

    final station = find.text(stationName);
    if (tester.any(station)) {
      await tester.tap(station.last);
    } else {
      await tester.scrollUntilVisible(station, 120);
      await tester.tap(station.last);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('home ekranı açılır', (tester) async {
    await pumpHome(tester);

    expect(find.text('YOLCULUĞUN\nKADAR OYNA'), findsOneWidget);
    expect(find.text('YOLCULUĞUNU PLANLA'), findsOneWidget);
    expect(find.text('ÇIKIŞ NOKTASI'), findsOneWidget);
    expect(find.text('GİDİLECEK YER'), findsOneWidget);
    expect(find.text('İnternetsiz oynanabilir.'), findsOneWidget);
    expect(find.text('YOLCULUĞU BAŞLAT'), findsOneWidget);
  });

  testWidgets('rota seçilmeden CTA pasif', (tester) async {
    await pumpHome(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('istasyon seçimi süre ve zorluğu günceller', (tester) async {
    await pumpHome(tester);

    await selectStation(
      tester,
      fieldHint: 'Bindiğin durağı seç',
      stationName: 'Taksim',
    );
    await selectStation(
      tester,
      fieldHint: 'İneceğin durağı seç',
      stationName: 'Levent',
    );

    // Taksim -> Levent = 8 dk -> Kısa profil, hedef 260.
    expect(find.text('~8 dk'), findsOneWidget);
    // Biri özet metriğinde, biri süre–zorluk skalasında (aktif band).
    expect(find.text('Kısa'), findsNWidgets(2));
    expect(find.text('260'), findsOneWidget);
    expect(find.text('4 durak'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('aynı istasyon seçilirse CTA pasif kalır ve uyarı çıkar', (
    tester,
  ) async {
    await pumpHome(tester);

    await selectStation(
      tester,
      fieldHint: 'Bindiğin durağı seç',
      stationName: 'Taksim',
    );
    await selectStation(
      tester,
      fieldHint: 'İneceğin durağı seç',
      stationName: 'Taksim',
    );

    expect(find.text('Biniş ve iniş durağı aynı olamaz.'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('yön değiştirme durakları takas eder', (tester) async {
    await pumpHome(tester);

    await selectStation(
      tester,
      fieldHint: 'Bindiğin durağı seç',
      stationName: 'Taksim',
    );
    await selectStation(
      tester,
      fieldHint: 'İneceğin durağı seç',
      stationName: 'Levent',
    );

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();

    // Süre yön değişse de aynı kalır.
    expect(find.text('~8 dk'), findsOneWidget);
  });
}
