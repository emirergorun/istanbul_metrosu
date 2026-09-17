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

  testWidgets('rozet yokken duraklatma düğmesi sağ kenarda', (tester) async {
    final rightEdge = await pumpHud(tester, width: 390);

    expect(tester.takeException(), isNull);
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('rozet varken de sağ kenarda', (tester) async {
    final rightEdge = await pumpHud(
      tester,
      width: 390,
      chips: <Widget>[
        const ComboChip(
          combo: 4,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
        const StreakChip(streak: 6),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('dar ekranda üç haneli rozetler satırı taşırmaz', (tester) async {
    final rightEdge = await pumpHud(
      tester,
      width: 320,
      chips: <Widget>[
        const ComboChip(
          combo: 128,
          graceLeft: 1,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
        const StreakChip(streak: 256),
      ],
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'rozetler küçülmeli, satır taşmamalı',
    );
    expect(pauseRight(tester), closeTo(rightEdge, 1));
  });

  testWidgets('geniş ekranda rozetler küçültülmez', (tester) async {
    await pumpHud(
      tester,
      width: 900,
      chips: <Widget>[
        const ComboChip(
          combo: 4,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
        const StreakChip(streak: 6),
      ],
    );

    expect(tester.takeException(), isNull);
    // Rozetler doğal yüksekliğinde: ölçekleme devreye girmemiş.
    expect(tester.getSize(find.byType(StreakChip)).height, greaterThan(24));
  });

  testWidgets('skor rozetlerin yerini kapmaz', (tester) async {
    await pumpHud(
      tester,
      width: 390,
      chips: <Widget>[
        const ComboChip(
          combo: 4,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    // Rozet tam genişliğinde çizilmeli; skor sütunu kalanı doldurur.
    expect(find.text('COMBO'), findsOneWidget);
    expect(find.text('x4'), findsOneWidget);
  });
}
