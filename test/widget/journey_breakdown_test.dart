import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_breakdown.dart';

import '../helpers/metro_fixture.dart';

/// Varış panelindeki dağılım: hangi oyun, ne kadar süre, kaç puan.
void main() {
  final journey = RouteService(
    MetroFixture.load(),
  ).estimate('m2_taksim', 'm2_levent').journey!;

  testWidgets('dağılım satırları puanı ve oynanan süreyi birlikte yazar', (
    tester,
  ) async {
    final session = JourneySession(journey: journey)
      ..addGameScore(gameId: 'blocks', raw: 800)
      ..creditPlaySeconds('blocks', 360)
      ..addGameScore(gameId: 'merge_drop', raw: 3800)
      ..creditPlaySeconds('merge_drop', 60)
      ..addScore(50);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Column(children: journeyBreakdownRows(session))),
      ),
    );

    expect(find.text('Blok Metro · 6 dk'), findsOneWidget);
    expect(find.text('800'), findsOneWidget);
    expect(find.text('Hat Düşür · 60 sn'), findsOneWidget);
    expect(find.text('Durak bonusu'), findsOneWidget);
  });

  testWidgets('satırların toplamı yolculuk skoruna eşit', (tester) async {
    final session = JourneySession(journey: journey)
      ..addGameScore(gameId: 'blocks', raw: 240)
      ..addGameScore(gameId: 'metro_quiz', raw: 130)
      ..addGameScore(gameId: 'rail_flight', raw: 44)
      ..addScore(25);

    final total = session.scoreByGame.values.fold<int>(0, (a, b) => a + b);

    expect(total, session.score);
    expect(journeyBreakdownRows(session), hasLength(4));
  });
}
