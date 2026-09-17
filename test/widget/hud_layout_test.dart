import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_hud.dart';

import '../helpers/metro_fixture.dart';

/// Üst bar altı oyunun ortak kabuğu; bozulunca hepsi birden bozulur.
///
/// Regresyon: skor sütunu bir ara `Flexible` yapıldı (rozetlere yer açmak
/// için) ve duraklatma düğmesi sağ kenardan kopup metnin yanına kaydı.
/// Rozeti olmayan oyunlarda bile üst bar bozuk görünüyordu.
void main() {
  final routes = RouteService(MetroFixture.load());

  Future<double> pumpHud(
    WidgetTester tester, {
    required double width,
    List<Widget> chips = const <Widget>[],
  }) async {
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
    final controller = GameController(
      journey: journey,
      generator: PieceGenerator(random: Random(1)),
      recordToBeat: 1,
      tick: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: JourneyHud(
              run: controller,
              accent: Colors.red,
              onPause: () {},
              chips: chips,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return width - AppSpacing.lg;
  }

  double pauseRight(WidgetTester tester) {
    final button = find.ancestor(
      of: find.byIcon(Icons.pause_rounded),
      matching: find.byType(HudButton),
    );
    return tester.getTopRight(button).dx;
  }

  testWidgets('okuma yokken duraklatma düğmesi sağ kenarda', (tester) async {
    final rightEdge = await pumpHud(tester, width: 390);

    expect(tester.takeException(), isNull);
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('okuma varken de sağ kenarda', (tester) async {
    final rightEdge = await pumpHud(
      tester,
      width: 390,
      chips: <Widget>[
        ComboReadout(
          combo: 4,
          streak: 6,
          accent: Colors.red,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('dar ekranda üç haneli sayılar satırı taşırmaz', (tester) async {
    final rightEdge = await pumpHud(
      tester,
      width: 320,
      chips: <Widget>[
        ComboReadout(
          combo: 128,
          streak: 256,
          accent: Colors.red,
          graceLeft: 1,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      ],
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'okuma küçülmeli, satır taşmamalı',
    );
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('geniş ekranda okuma küçültülmez', (tester) async {
    await pumpHud(
      tester,
      width: 900,
      chips: <Widget>[
        ComboReadout(
          combo: 4,
          streak: 6,
          accent: Colors.red,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    // Okuma doğal yüksekliğinde: ölçekleme devreye girmemiş.
    expect(tester.getSize(find.byType(ComboReadout)).height, greaterThan(24));
  });

  testWidgets('skor okumanın yerini kapmaz', (tester) async {
    await pumpHud(
      tester,
      width: 390,
      chips: <Widget>[
        ComboReadout(
          combo: 4,
          streak: 0,
          accent: Colors.red,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    // Okuma tam genişliğinde çizilmeli; skor sütunu kalanı doldurur.
    expect(find.text('×4'), findsOneWidget);
  });
}
