import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/daily/presentation/daily_screen.dart';
import 'package:istanbul_metro_game/features/daily/presentation/widgets/daily_entry_strip.dart';
import 'package:istanbul_metro_game/features/daily/presentation/widgets/mission_card.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// V3'ün ekrandaki hâli.
///
/// Sınanan söz: günlük yolculuk **ikinci bir kapı**, zorunlu bir kapı
/// değil; ve o kapıdan geçmek V2'nin oyun tanıtım ekranına çıkıyor, ikinci
/// bir oyun başlatma yoluna değil.
void main() {
  final metro = MetroFixture.load();

  Future<LocalStore> freshStore([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
      ...seed,
    });
    final store = LocalStore();
    await store.init();
    return store;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    LocalStore store, {
    Size size = const Size(1170, 2532),
    double pixelRatio = 3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    // Açılıştaki trenler sonsuz döner; `pumpAndSettle` takılmasın.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(store: store, audio: AudioService(), metro: metro),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDaily(WidgetTester tester) async {
    await tester.tap(find.byType(DailyEntryStrip));
    await tester.pumpAndSettle();
  }

  group('Ana ekran girişi', () {
    testWidgets('günlük şeridi rota ile birlikte çıkar', (tester) async {
      await pumpApp(tester, await freshStore());

      expect(find.byType(DailyEntryStrip), findsOneWidget);
      expect(find.text('BUGÜNÜN YOLCULUĞU'), findsOneWidget);
    });

    testWidgets('şerit birincil eylemin önüne geçmez', (tester) async {
      await pumpApp(tester, await freshStore());

      final strip = tester.getRect(find.byType(DailyEntryStrip));
      final play = tester.getRect(
        find.widgetWithText(FilledButton, 'OYUNA BAŞLA'),
      );

      // Şerit yukarıda, oyuna başlamak altta ve başparmağa daha yakın.
      expect(strip.bottom, lessThan(play.top));
      // Şerit iki satır (başlık + rota), o yüzden düğmeden bir tutam uzun.
      // Sınır yine de dar: günlük kart ekranı ele geçirmemeli.
      expect(strip.height, lessThan(play.height * 1.6));
      // Dokunma alanı 44 pikselin altına inmiyor.
      expect(strip.height, greaterThanOrEqualTo(44));
    });

    testWidgets('seri yokken rozet çizilmez', (tester) async {
      await pumpApp(tester, await freshStore());
      // Rozet yalnız sayıyla birlikte çiziliyor: "4 GÜN". Sıfır seri bir
      // bilgi değil, gürültü.
      expect(find.textContaining(RegExp(r'\d+ GÜN')), findsNothing);
    });
  });

  group('Günlük ekranı', () {
    testWidgets('şeride dokununca açılır', (tester) async {
      await pumpApp(tester, await freshStore());
      await openDaily(tester);

      expect(find.byType(DailyScreen), findsOneWidget);
      expect(find.text('BUGÜN'), findsOneWidget);
    });

    testWidgets('üç görev kartı ve başlama düğmesi', (tester) async {
      await pumpApp(tester, await freshStore());
      await openDaily(tester);

      expect(find.text('GÖREVLER'), findsOneWidget);
      expect(find.byType(MissionCard), findsNWidgets(3));
      expect(find.widgetWithText(FilledButton, 'BAŞLA'), findsOneWidget);
    });

    testWidgets('ilk görev günün yolculuğu', (tester) async {
      await pumpApp(tester, await freshStore());
      await openDaily(tester);

      expect(find.text('Bugünün yolculuğunu tamamla'), findsOneWidget);
    });

    testWidgets('BAŞLA V2 tanıtım ekranını açar', (tester) async {
      await pumpApp(tester, await freshStore());
      await openDaily(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'BAŞLA'));
      await tester.pumpAndSettle();

      // Kendi başlatma yolu yok: V2'nin tanıtım ekranı ve OYNA düğmesi.
      expect(find.byType(GameDetailScreen), findsOneWidget);
      expect(find.text('OYNA'), findsOneWidget);
    });

    testWidgets('gezinmek günlük ilerleme üretmez', (tester) async {
      final store = await freshStore();
      await pumpApp(tester, store);
      await openDaily(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'BAŞLA'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Sayaçlar hâlâ boş: gün yalnızca gerçekten oynanınca ilerler.
      for (final card in tester.widgetList<MissionCard>(
        find.byType(MissionCard),
      )) {
        expect(card.progress, 0);
      }
      expect(store.dailyCountersRaw ?? '', isNot(contains('"done":true')));
    });

    testWidgets('geri dönünce ana ekran korunur', (tester) async {
      await pumpApp(tester, await freshStore());
      await openDaily(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(DailyEntryStrip), findsOneWidget);
      expect(find.byType(DailyScreen), findsNothing);
    });
  });

  group('Ekran boyutları', () {
    const sizes = <String, Size>{
      'küçük telefon (SE)': Size(320, 568),
      'standart telefon': Size(390, 844),
      'tablet': Size(768, 1024),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} — taşma yok', (tester) async {
        await pumpApp(
          tester,
          await freshStore(),
          size: entry.value,
          pixelRatio: 1,
        );
        await openDaily(tester);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en büyük yazı ölçeğinde taşma yok', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(
        tester,
        await freshStore(),
        size: const Size(320, 568),
        pixelRatio: 1,
      );
      await openDaily(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
