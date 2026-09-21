import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/discovery_screen.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/discovery_entry_strip.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/station_dot_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();

  Future<LocalStore> storeWith(List<String> discovered) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
      if (discovered.isNotEmpty) 'discovered_stations': discovered,
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

  /// Hat kartını görünür kılar.
  ///
  /// Hat listesi tembel kuruluyor: ekranda olmayan kart widget ağacında da
  /// yok. Testin ölçtüğü şey taşma, kaydırma değil — kart önce getiriliyor.
  Future<void> scrollToLine(WidgetTester tester, String name) async {
    final target = find.text(name);
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        220,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  group('Ana ekran girişi', () {
    testWidgets('keşif şeridi sayacı gösterir', (tester) async {
      await pumpApp(tester, await storeWith(<String>['taksim', 'sishane']));

      expect(find.byType(DiscoveryEntryStrip), findsOneWidget);
      expect(find.text('İSTANBUL KEŞFİ'), findsOneWidget);
      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('şeride dokununca keşif ekranı açılır', (tester) async {
      await pumpApp(tester, await storeWith(const <String>[]));

      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.byType(DiscoveryScreen), findsOneWidget);
    });

    testWidgets('şerit birincil eylemin önüne geçmez', (tester) async {
      await pumpApp(tester, await storeWith(const <String>[]));

      final strip = tester.getRect(find.byType(DiscoveryEntryStrip));
      final play = tester.getRect(
        find.widgetWithText(FilledButton, 'OYUNA BAŞLA'),
      );

      // Şerit yukarıda, oyuna başlamak altta ve başparmağa daha yakın.
      expect(strip.bottom, lessThan(play.top));
      // Şeridin yüksekliği birincil eylemi geçmez; dokunma alanı ise 44
      // pikselin altına inmez.
      expect(strip.height, lessThanOrEqualTo(play.height));
      expect(strip.height, greaterThanOrEqualTo(44));
    });
  });

  group('Keşif ekranı', () {
    testWidgets('boş durumda 0 / N ve davet metni', (tester) async {
      await pumpApp(tester, await storeWith(const <String>[]));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsWidgets);
      expect(find.text('/ 143 istasyon'), findsOneWidget);
      expect(
        find.text('İlk yolculuğunu yap ve İstanbul’u keşfetmeye başla.'),
        findsOneWidget,
      );
    });

    testWidgets('her hat için bir kart ve nokta şeridi çizilir', (
      tester,
    ) async {
      await pumpApp(tester, await storeWith(const <String>[]));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      // Liste kaydırmalı; ekrana sığan kadarı yeter.
      expect(find.byType(StationDotStrip), findsWidgets);
      expect(find.text('M2'), findsOneWidget);
    });

    testWidgets('kısmi keşif hat sayacında görünür', (tester) async {
      await pumpApp(
        tester,
        await storeWith(<String>['taksim', 'sishane', 'halic']),
      );
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.text('3 / 15'), findsOneWidget);
      expect(find.text('%2 tamamlandı'), findsOneWidget);
    });

    testWidgets('tamamlanan hat işaretlenir', (tester) async {
      // M6 dört duraklı: en kısa tam hat.
      final m6 = metro.stationsOfLine('M6').map((s) => s.canonicalId).toList();
      await pumpApp(tester, await storeWith(m6));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.text('4 / 4'), findsOneWidget);
      expect(find.textContaining('1 hat bitti'), findsOneWidget);
    });

    testWidgets('hat kartına dokununca duraklar açılır', (tester) async {
      await pumpApp(tester, await storeWith(<String>['taksim']));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.text('Taksim'), findsNothing);

      await scrollToLine(tester, 'Yenikapı – Hacıosman');
      await tester.tap(find.text('Yenikapı – Hacıosman'));
      await tester.pumpAndSettle();

      // Keşfedilen de keşfedilmeyen de görünür: kalan yol gizlenmez.
      expect(find.text('Taksim'), findsOneWidget);
      expect(find.text('Osmanbey'), findsOneWidget);
    });

    testWidgets('durum renkten bağımsız bir simge taşır', (tester) async {
      await pumpApp(tester, await storeWith(<String>['taksim']));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();
      await scrollToLine(tester, 'Yenikapı – Hacıosman');
      await tester.tap(find.text('Yenikapı – Hacıosman'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      expect(find.byIcon(Icons.circle_outlined), findsWidgets);
    });
  });

  group('Erişilebilirlik', () {
    testWidgets('hat kartı tek cümlede özetlenir', (tester) async {
      await pumpApp(tester, await storeWith(<String>['taksim']));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          RegExp(r'M2.*15 duraktan 1 tanesi keşfedildi.*Durakları göster'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('açılan durak listesi ekran okuyucuya ulaşır', (tester) async {
      // Kartı açmanın tek amacı listeyi okumak. Liste `ExcludeSemantics`
      // altında kalırsa kart erişilebilirlik açısından hiç açılmamış olur.
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await storeWith(<String>['taksim']));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();
      await scrollToLine(tester, 'Yenikapı – Hacıosman');
      await tester.tap(find.text('Yenikapı – Hacıosman'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Taksim, keşfedildi'), findsOneWidget);
      expect(find.bySemanticsLabel('Osmanbey, keşfedilmedi'), findsOneWidget);
      // Aktarma bilgisi de sesli okunur.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Yenikapı, keşfedilmedi\. Aktarma: M1A · M1B · M2'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('küresel özet rakam rakam değil cümle olarak okunur', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await storeWith(<String>['taksim', 'sishane']));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          RegExp(r'İstanbul keşfi\. 143 durağın 2 tanesi keşfedildi'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Yeniden açılış', () {
    testWidgets('keşif uygulama kapanıp açılınca durur', (tester) async {
      // Aynı `SharedPreferences` üzerinde iki ayrı `LocalStore`: gerçek
      // bir yeniden açılışın karşılığı.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_seen': true,
      });
      final first = LocalStore();
      await first.init();
      await first.saveDiscoveredStations(<String>{'taksim', 'sishane'});

      final second = LocalStore();
      await second.init();
      await pumpApp(tester, second);

      expect(find.byType(DiscoveryEntryStrip), findsOneWidget);
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsWidgets);
      expect(find.text('2 / 15'), findsOneWidget);
    });
  });

  group('Ağ büyümesi', () {
    testWidgets('daha önce görülmüş toplam büyüyünce bildirilir', (
      tester,
    ) async {
      // Oyuncu ekranı 120 durakken görmüş; ağ bugün 143.
      final store = await storeWith(const <String>[]);
      await store.markDiscoveryTotalSeen(120);

      await pumpApp(tester, store);
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(
        find.text('Ağa 23 yeni durak eklendi. Keşif hedefi büyüdü.'),
        findsOneWidget,
      );
    });

    testWidgets('ilk ziyarette bildirim çıkmaz', (tester) async {
      await pumpApp(tester, await storeWith(const <String>[]));
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.textContaining('yeni durak eklendi'), findsNothing);
    });

    testWidgets('ziyaret sonrası bildirim tekrar çıkmaz', (tester) async {
      final store = await storeWith(const <String>[]);
      await store.markDiscoveryTotalSeen(120);

      await pumpApp(tester, store);
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();
      expect(find.textContaining('yeni durak eklendi'), findsOneWidget);

      // Geri dön ve yeniden aç: toplam artık görülmüş sayılıyor.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();

      expect(find.textContaining('yeni durak eklendi'), findsNothing);
    });
  });

  group('Ekran boyutları', () {
    const sizes = <String, Size>{
      'küçük telefon (SE)': Size(320, 568),
      'standart telefon': Size(390, 844),
      'geniş telefon (Pro Max)': Size(430, 932),
      'tablet': Size(768, 1024),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} — taşma yok', (tester) async {
        await pumpApp(
          tester,
          await storeWith(<String>['taksim', 'yenikapi']),
          size: entry.value,
          pixelRatio: 1,
        );
        await tester.tap(find.byType(DiscoveryEntryStrip));
        await tester.pumpAndSettle();

        // En uzun hat adı ve en kalabalık hat aynı anda ekranda.
        //
        // Kart önce görünür kılınıyor: hat listesi tembel bir sliver, dar
        // ekranda listenin altındaki kartlar henüz kurulmamış oluyor.
        await scrollToLine(tester, 'Kadıköy – Sabiha Gökçen Havalimanı');
        await tester.tap(find.text('Kadıköy – Sabiha Gökçen Havalimanı'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en büyük yazı ölçeğinde taşma yok', (tester) async {
      // Uygulama ölçeği 1.6'ya kırpıyor; sistem 2.0 istese de düzen orada
      // ayakta kalmalı.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(
        tester,
        await storeWith(<String>['taksim']),
        size: const Size(320, 568),
        pixelRatio: 1,
      );
      await tester.tap(find.byType(DiscoveryEntryStrip));
      await tester.pumpAndSettle();
      await scrollToLine(tester, 'Yenikapı – Hacıosman');
      await tester.tap(find.text('Yenikapı – Hacıosman'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
