import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/presentation/metro_merge_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Hat Birleştir'de karolar 2048'deki gibi kaymalı, ışınlanmamalı.
void main() {
  final metro = MetroFixture.load();

  testWidgets('kaydırmada karolar önce kayar, sonra yerine oturur', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    tester.view.physicalSize = const Size(1170, 2532);
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
          home: MetroMergeScreen(
            journey: RouteService(
              metro,
            ).estimate('m2_taksim', 'm2_levent').journey!,
          ),
        ),
      ),
    );
    await tester.pump();

    // Rastgele başlangıç tahtasında her yön hamle olmayabilir: dört yön
    // denenir, ilk kabul edilende kayma başlar.
    final center = tester.getCenter(find.byType(Scaffold));
    const swipes = <Offset>[
      Offset(-300, 0),
      Offset(300, 0),
      Offset(0, -300),
      Offset(0, 300),
    ];
    var slid = false;
    for (final swipe in swipes) {
      await tester.flingFrom(center, swipe, 1500);
      // Kayma evresinin ortası (~110 ms'nin yarısı).
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const ValueKey<String>('kayan-0')).evaluate().isNotEmpty) {
        slid = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(slid, isTrue, reason: 'hiçbir kaydırmada karo kaymadı');

    // Kayma bitince kayan karolar gider, ızgara oturur.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('kayan-0')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
