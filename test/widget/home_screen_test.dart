import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/journey/presentation/widgets/line_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Tanıtım yalnızca ilk açılışta çıkar; testlerde kapalı.
      'onboarding_seen': true,
    });
    store = LocalStore();
    await store.init();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    // iPhone benzeri ekran.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Açılış ekranındaki trenler sonsuz döner; pumpAndSettle'ın takılmaması
    // için testlerde hareket kapatılır. Bu aynı zamanda "hareketi azalt"
    // desteğinin çalıştığını da doğrular.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(
        store: store,
        audio: AudioService(),
        metro: MetroFixture.load(),
      ),
    );
    await tester.pumpAndSettle();

    // Açılış ekranından planlayıcıya geç.
    await tester.tap(find.text('OYUNA BAŞLA'));
    await tester.pumpAndSettle();
  }

  Future<void> selectLine(WidgetTester tester, String lineId) async {
    final chip = find.text(lineId);
    if (!tester.any(chip)) {
      // Hat şeridi yatay kaydırılır; ekran dışındaki hatlar görünür yapılır.
      await tester.dragUntilVisible(
        chip,
        find.byType(LineSelector),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(chip);
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
    expect(find.text('ÇIKIŞ NOKTASI'), findsOneWidget);
    expect(find.text('GİDİLECEK YER'), findsOneWidget);
    expect(find.text('İnternetsiz oynanabilir.'), findsOneWidget);
    expect(find.text('YOLCULUĞU BAŞLAT'), findsOneWidget);
    // Sağ üstteki çevrimdışı rozeti kaldırıldı.
    expect(find.text('ÇEVRİMDIŞI'), findsNothing);
  });

  testWidgets('rota seçilmeden CTA pasif', (tester) async {
    await pumpHome(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('istasyon seçimi süre ve zorluğu günceller', (tester) async {
    await pumpHome(tester);
    await selectLine(tester, 'M2');

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

    // Taksim -> Levent = 9 dk (M2'de kenar 137 sn).
    expect(find.text('~9 dk'), findsOneWidget);
    // Hedef skor kaldırıldı; amaç rotadaki kendi rekorunu geçmek.
    expect(find.text('HEDEF'), findsNothing);
    expect(find.text('BU ROTADA'), findsOneWidget);
    expect(find.text('İlk yolculuk'), findsOneWidget);
    // Zorluk profili oyuncuya gösterilmez.
    expect(find.text('ZORLUK'), findsNothing);
    expect(find.text('Kısa'), findsNothing);
    expect(find.text('4 durak'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('aynı istasyon seçilirse CTA pasif kalır ve uyarı çıkar', (
    tester,
  ) async {
    await pumpHome(tester);
    await selectLine(tester, 'M2');

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

  testWidgets('oyun yarım bırakılınca açılışta devam kartı çıkar', (
    tester,
  ) async {
    // Regresyon: Navigator.pop alttaki rotayı yeniden çizmez. Ekran
    // tazelenmezse ne "son rotan" kartı ne de yeni rekor görünür.
    await pumpHome(tester);
    await selectLine(tester, 'M2');
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

    // Rota seçildikten sonra önce oyun seçimi gelir.
    await tester.tap(find.text('YOLCULUĞU BAŞLAT'));
    await tester.pumpAndSettle();
    expect(find.text('Oyun seç'), findsOneWidget);

    await tester.tap(find.text('Blok Metro'));
    await tester.pumpAndSettle();
    expect(find.text('SKOR · İLK YOLCULUK'), findsOneWidget);

    // Oyundan çık; oyun seçimi ve planlayıcıdan da geri dön.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni rota seç'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
    }

    // Oyun yarım bırakıldığı için açılışta "devam et" kartı çıkar.
    expect(find.text('YARIM KALAN OYUN'), findsOneWidget);
    expect(find.text('Taksim → Levent'), findsOneWidget);
    expect(find.text('Yeni bir yolculuk başlat'), findsOneWidget);
  });

  testWidgets('uzun hatta durak araması filtreler', (tester) async {
    await pumpHome(tester);
    await selectLine(tester, 'M4'); // 23 durak — eşik üstü

    await tester.tap(find.text('Bindiğin durağı seç'));
    await tester.pumpAndSettle();

    expect(find.text('Durak ara'), findsOneWidget);
    expect(find.text('Kadıköy'), findsOneWidget);

    // Türkçe karakter normalleştirilir: "kozyatagi" -> "Kozyatağı".
    await tester.enterText(find.byType(TextField), 'kozyatagi');
    await tester.pumpAndSettle();

    expect(find.text('Kozyatağı'), findsOneWidget);
    expect(find.text('Kadıköy'), findsNothing);
  });

  testWidgets('kısa hatta arama alanı çıkmaz', (tester) async {
    await pumpHome(tester);
    await selectLine(tester, 'M6'); // 4 durak — eşik altı

    await tester.tap(find.text('Bindiğin durağı seç'));
    await tester.pumpAndSettle();

    expect(find.text('Durak ara'), findsNothing);
    expect(find.text('Nispetiye'), findsOneWidget);
  });

  testWidgets('tanıtım yalnızca ilk açılışta çıkar', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final freshStore = LocalStore();
    await freshStore.init();

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Açılış ekranındaki trenler sonsuz döner; pumpAndSettle'ın takılmaması
    // için testlerde hareket kapatılır. Bu aynı zamanda "hareketi azalt"
    // desteğinin çalıştığını da doğrular.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(
        store: freshStore,
        audio: AudioService(),
        metro: MetroFixture.load(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yolculuğunu seç'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();

    expect(find.text('Yolculuğunu seç'), findsNothing);
    expect(freshStore.hasSeenOnboarding, isTrue);
    expect(find.text('OYUNA BAŞLA'), findsOneWidget);
  });

  testWidgets('tanıtım kapanmadan "görüldü" olarak işaretlenir', (
    tester,
  ) async {
    // Regresyon: kayıt yalnızca tanıtım kapandıktan sonra yazılıyordu.
    // Kullanıcı tanıtım açıkken uygulamayı kapatırsa bir dahaki açılışta
    // yeniden karşılıyordu.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final freshStore = LocalStore();
    await freshStore.init();

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
        store: freshStore,
        audio: AudioService(),
        metro: MetroFixture.load(),
      ),
    );
    await tester.pumpAndSettle();

    // Tanıtım hâlâ ekranda, ama kayıt çoktan yazılmış olmalı.
    expect(find.text('Yolculuğunu seç'), findsOneWidget);
    expect(freshStore.hasSeenOnboarding, isTrue);
  });

  testWidgets('yön değiştirme durakları takas eder', (tester) async {
    await pumpHome(tester);
    await selectLine(tester, 'M2');

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
    expect(find.text('~9 dk'), findsOneWidget);
  });
}
