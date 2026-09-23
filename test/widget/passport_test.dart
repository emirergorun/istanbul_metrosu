import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/discovery_screen.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/discovery_entry_strip.dart';
import 'package:istanbul_metro_game/features/passport/domain/achievement.dart';
import 'package:istanbul_metro_game/features/passport/presentation/achievements_screen.dart';
import 'package:istanbul_metro_game/features/passport/presentation/widgets/achievement_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// V4 — İstanbul Pasaportu.
///
/// Sınanan söz: pasaport ikinci bir ilerleme kaydı **tutmuyor**; ekranda
/// gördüğü sayı kalıcı keşif kaydının kendisi. V4'ten önce oynamış bir
/// oyuncunun ilerlemesi ilk açılışta yerinde duruyor.
void main() {
  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);

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

  Future<void> openPassport(WidgetTester tester) async {
    await tester.tap(find.byType(DiscoveryEntryStrip));
    await tester.pumpAndSettle();
  }

  /// Damga rafına dokunur.
  ///
  /// Dokunulan yer başlık değil rafın kendisi: başlık bölümü adlandırıyor,
  /// eylem rozetlerin durduğu kartta.
  Future<void> openAchievements(WidgetTester tester) async {
    await tester.tap(find.byType(AchievementBadge).first);
    await tester.pumpAndSettle();
  }

  List<String> firstStations(int count) =>
      catalog.stations.take(count).map((CanonicalStation s) => s.id).toList();

  group('Pasaport', () {
    testWidgets('keşif şeridinden açılır', (tester) async {
      await pumpApp(tester, await storeWith(const <String>[]));
      await openPassport(tester);

      expect(find.byType(DiscoveryScreen), findsOneWidget);
      expect(find.text('YOLCULUK KARTIM'), findsOneWidget);
    });

    testWidgets('keşif bölümü hâlâ ilk sırada', (tester) async {
      await pumpApp(tester, await storeWith(firstStations(3)));
      await openPassport(tester);

      final discovery = tester.getRect(find.text('İSTANBUL KEŞFİ'));
      final badges = tester.getRect(find.text('ROZETLER'));
      final lines = tester.getRect(find.text('HATLAR'));

      // Pasaportun konusu keşif; başarımlar onu taçlandıran katman.
      expect(discovery.top, lessThan(badges.top));
      expect(badges.top, lessThan(lines.top));
    });

    testWidgets('başarım rafı sayacı gösterir', (tester) async {
      await pumpApp(tester, await storeWith(firstStations(3)));
      await openPassport(tester);

      expect(find.byType(AchievementBadge), findsWidgets);
      // Üç durak yalnız "İlk Keşif"i açar; sayaç toplamı katalogdan gelir.
      expect(find.text('1 / ${Achievements.all.length}'), findsOneWidget);
    });

    testWidgets('rafa dokununca başarım sayfası açılır', (tester) async {
      await pumpApp(tester, await storeWith(firstStations(3)));
      await openPassport(tester);

      await openAchievements(tester);

      expect(find.byType(AchievementsScreen), findsOneWidget);
      // Kilitli başarımın adı gizlenmiyor: hedef görünmezse hedef olmaz.
      // Liste tembel kuruluyor, satır önce görünür kılınıyor.
      final locked = find.text(Achievements.explorerIII.title);
      await tester.scrollUntilVisible(locked, 200);
      expect(locked, findsOneWidget);
    });
  });

  group('Başarım sayfası', () {
    testWidgets('açık ve kilitli rozetler bir arada', (tester) async {
      await pumpApp(tester, await storeWith(firstStations(12)));
      await openPassport(tester);
      await openAchievements(tester);

      final badges = tester
          .widgetList<AchievementBadge>(find.byType(AchievementBadge))
          .toList();
      expect(badges.where((AchievementBadge b) => b.unlocked), isNotEmpty);
      expect(badges.where((AchievementBadge b) => !b.unlocked), isNotEmpty);
    });

    testWidgets('kilitli başarımda ilerleme yazılı', (tester) async {
      await pumpApp(tester, await storeWith(firstStations(12)));
      await openPassport(tester);
      await openAchievements(tester);

      // 12 durak: "İstanbul Kâşifi II" 12 / 25'te. Liste tembel kuruluyor,
      // satır önce görünür kılınıyor.
      final progress = find.text('12 / 25');
      await tester.scrollUntilVisible(progress, 200);
      expect(progress, findsOneWidget);
    });

    testWidgets('V4 öncesi ilerleme ilk açılışta duruyor', (tester) async {
      // Oyuncu V4'ten önce 25 durak keşfetmiş; rozet kaydı hiç yok.
      await pumpApp(tester, await storeWith(firstStations(25)));
      await openPassport(tester);

      // Keşif sayısı kaydın kendisi, pasaportun kopyası değil.
      expect(find.text('25'), findsWidgets);
      expect(
        find.text('${Achievements.all.length}'),
        findsNothing,
        reason: 'Tümü birden açılmamalı',
      );
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
          await storeWith(firstStations(12)),
          size: entry.value,
          pixelRatio: 1,
        );
        await openPassport(tester);
        await openAchievements(tester);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en büyük yazı ölçeğinde taşma yok', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(
        tester,
        await storeWith(firstStations(12)),
        size: const Size(320, 568),
        pixelRatio: 1,
      );
      await openPassport(tester);
      await openAchievements(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
