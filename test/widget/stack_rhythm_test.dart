import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/core/widgets/pressable.dart';
import 'package:istanbul_metro_game/features/daily/presentation/widgets/daily_entry_strip.dart';
import 'package:istanbul_metro_game/features/daily/presentation/widgets/mission_card.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/discovery_entry_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Yığın ritmi: alt alta duran bloklar **tek** bir boşlukla ayrılır.
///
/// Ana ekranda üç farklı değer (8 / 24 / 12) kullanılıyordu ve bloklar aynı
/// aileye ait görünmüyordu. Kural [AppSpacing.stack] ile tek yerde yazılı;
/// bu test onu bozulmaya karşı sabitliyor.
///
/// Piksel değeri değil **eşitlik** ölçülüyor: sabit değişirse test yine
/// geçer, boşluklardan biri elle başka bir değere çekilirse düşer.
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

  Future<void> pumpApp(WidgetTester tester, LocalStore store) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
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

  /// İki bloğun arasındaki dikey boşluk.
  double gapBetween(WidgetTester tester, Finder upper, Finder lower) =>
      tester.getRect(lower).top - tester.getRect(upper).bottom;

  testWidgets('ana ekranda bloklar tek ritimde', (tester) async {
    await pumpApp(
      tester,
      await freshStore(<String, Object>{
        'last_route_origin': 'm2_taksim',
        'last_route_destination': 'm2_levent',
      }),
    );

    final discovery = find.byType(DiscoveryEntryStrip);
    final daily = find.byType(DailyEntryStrip);
    // Son rota kartı: rota metnini saran basılabilir blok.
    final card = find
        .ancestor(
          of: find.textContaining('Taksim'),
          matching: find.byType(Pressable),
        )
        .last;
    final secondary = find.widgetWithText(TextButton, 'Başka bir rota seç');

    expect(discovery, findsOneWidget);
    expect(daily, findsOneWidget);
    expect(card, findsOneWidget);

    final first = gapBetween(tester, discovery, daily);
    final second = gapBetween(tester, daily, card);

    expect(first, AppSpacing.stack);
    expect(second, AppSpacing.stack);
    // Üçüncü boşluk `TextButton`'ın kendi dokunma alanını da taşıyor;
    // ölçülen değer sabitten küçük olamaz.
    expect(
      gapBetween(tester, card, secondary),
      greaterThanOrEqualTo(AppSpacing.stack),
    );
  });

  testWidgets('görev kartları eşit aralıklı', (tester) async {
    await pumpApp(tester, await freshStore());
    await tester.tap(find.byType(DailyEntryStrip));
    await tester.pumpAndSettle();

    final cards = find.byType(MissionCard);
    expect(cards, findsNWidgets(3));

    expect(gapBetween(tester, cards.at(0), cards.at(1)), AppSpacing.stack);
    expect(gapBetween(tester, cards.at(1), cards.at(2)), AppSpacing.stack);
  });

  test('ritim sabitleri ölçekten geliyor', () {
    // Elle seçilmiş bir sayı değil, var olan ölçeğin bir basamağı.
    expect(AppSpacing.stack, AppSpacing.md);
    expect(AppSpacing.sectionGap, AppSpacing.xl);
    // Bölüm boşluğu yığın boşluğundan belirgin şekilde büyük olmalı,
    // yoksa başlıkla başlayan blok ayırt edilemez.
    expect(AppSpacing.sectionGap, greaterThan(AppSpacing.stack));
  });
}
