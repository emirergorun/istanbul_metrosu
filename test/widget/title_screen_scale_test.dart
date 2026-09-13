import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/home/presentation/title_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Açılış ekranının dikey düzeni.
///
/// Ekran esnek boşluklarla (`Spacer`) kuruluyor: marka ortada, kart dipten
/// bir tutam yukarıda. Esnek boşluk, içerik ekrandan uzun olduğunda sıfıra
/// iner ve taşma başlar — bu yüzden en dar telefonda ve uygulamanın
/// desteklediği en büyük yazı ölçeğinde (1.6×) taşmadığı sınanmalı.
void main() {
  final metro = MetroFixture.load();

  Future<void> pumpTitle(
    WidgetTester tester, {
    required double scale,
    required Size size,
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
      ...prefs,
    });
    final store = LocalStore();
    await store.init();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        child: MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const TitleScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  // iPhone SE: desteklenen en dar/kısa ekran.
  const small = Size(375, 667);

  testWidgets('1.6x yazı ölçeğinde taşma yok — ilk açılış', (tester) async {
    await pumpTitle(tester, scale: 1.6, size: small);

    expect(find.text('OYUNA BAŞLA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.6x yazı ölçeğinde taşma yok — son rota kartı varken', (
    tester,
  ) async {
    await pumpTitle(
      tester,
      scale: 1.6,
      size: small,
      prefs: <String, Object>{
        'last_route_origin': 'm1a_aksaray',
        'last_route_destination': 'm1a_otogar',
      },
    );

    expect(find.text('Başka bir rota seç'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
