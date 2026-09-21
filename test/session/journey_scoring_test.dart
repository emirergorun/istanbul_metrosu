import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';
import 'package:istanbul_metro_game/features/session/scoring/game_score_profile.dart';

import '../helpers/journey_points.dart';
import '../helpers/metro_fixture.dart';

/// Ortak puan hunisi: ölçek, kesir taşıması, sprint ve hane dağılımı.
void main() {
  final routes = RouteService(MetroFixture.load());
  Journey journeyOf(String origin, String destination) =>
      routes.estimate(origin, destination).journey!;

  JourneySession sessionFor() =>
      JourneySession(journey: journeyOf('m2_taksim', 'm2_levent'))
        ..setStatus(GameStatus.playing);

  group('ortak puanlama', () {
    test('ham puan oyunun ölçeğiyle yazılır', () {
      final session = sessionFor();
      const raw = 1000;

      session.addGameScore(gameId: 'merge_drop', raw: raw);

      final expected = (raw * GameScoreProfiles.scaleFor('merge_drop')).round();
      expect(session.score, expected);
      expect(session.scoreOf('merge_drop'), expected);
    });

    test('kesirler birikir, uzun vadede tek puan bile kaybolmaz', () {
      final session = sessionFor();
      // Ölçeği bilerek küçük olan bir oyun: tek olay bir puandan az.
      final scale = GameScoreProfiles.scaleFor('lane_runner');
      expect(scale, lessThan(0.5));

      for (var i = 0; i < 1000; i++) {
        session.addGameScore(gameId: 'lane_runner', raw: 1);
      }

      // Kesir atılsaydı skor sıfır olurdu; yuvarlama sapması ±1'i geçmez.
      expect(session.score, closeTo(1000 * scale, 1));
    });

    test('çıpa oyunun ham puanı olduğu gibi yazılır', () {
      final session = sessionFor();

      session.addGameScore(gameId: 'blocks', raw: 137);

      expect(session.score, 137);
    });

    test('sprint çarpanı ölçekten sonra gelir', () {
      // Sprint yalnızca yeterince duraklı yolculuklarda açılıyor.
      final session = JourneySession(
        journey: journeyOf('m2_yenikapi', 'm2_haciosman'),
      )..setStatus(GameStatus.playing);
      // Yolculuğun son diliminde: sprint açık.
      session.addElapsed(session.journey.estimatedSeconds * 0.95);
      session.settle();
      expect(session.isSprint, isTrue);

      session.addGameScore(gameId: 'merge_drop', raw: 1000);

      final scaled = (1000 * GameScoreProfiles.scaleFor('merge_drop')).round();
      expect(session.score, scaled * 2);
    });

    test('hanelerin toplamı yolculuk skoruna eşit', () {
      final session = sessionFor();

      session
        ..addGameScore(gameId: 'blocks', raw: 240)
        ..addGameScore(gameId: 'train_snake', raw: 900)
        ..addGameScore(gameId: 'metro_quiz', raw: 60)
        // Durak bonusu yolculuğun kendi hanesine yazılır.
        ..addScore(25);

      final total = session.scoreByGame.values.fold<int>(0, (a, b) => a + b);
      expect(total, session.score);
      expect(session.scoreOf(JourneySession.journeyBucket), 25);
    });

    test('geri alma puanı oyunun hanesinden düşer', () {
      final session = sessionFor();
      session
        ..addGameScore(gameId: 'blocks', raw: 200)
        ..addScore(25);

      session.refund(points: 60, seconds: 4, gameId: 'blocks');

      expect(session.score, 165);
      expect(session.scoreOf('blocks'), 140);
      expect(session.scoreOf(JourneySession.journeyBucket), 25);
      final total = session.scoreByGame.values.fold<int>(0, (a, b) => a + b);
      expect(total, session.score);
    });

    test('geri alma oyunun kazandığından çoksa kalanı yolculuktan iner', () {
      final session = sessionFor();
      session
        ..addGameScore(gameId: 'blocks', raw: 30)
        ..addScore(25);

      session.refund(points: 50, gameId: 'blocks');

      expect(session.score, 5);
      expect(session.scoreOf('blocks'), 0);
      expect(session.scoreOf(JourneySession.journeyBucket), 5);
    });

    test('geri alma skoru eksiye düşürmez', () {
      final session = sessionFor();
      session.addGameScore(gameId: 'blocks', raw: 10);

      session.refund(points: 500, seconds: 900, gameId: 'blocks');

      expect(session.score, 0);
      expect(session.elapsedSeconds, 0);
    });

    test('her oyunun kesiri ayrı sayılır', () {
      final session = sessionFor();

      // İki oyunun yarım puanları birbirini tamamlamamalı.
      session
        ..addGameScore(gameId: 'lane_runner', raw: 2)
        ..addGameScore(gameId: 'rail_flight', raw: 1);

      // Ray Değiştir'in kesiri bekliyor; Ray Uçuşu'nunki kendi hanesinde.
      expect(session.scoreOf('lane_runner'), journeyPoints('lane_runner', [2]));
      expect(session.scoreOf('lane_runner'), 0);
      expect(session.scoreOf('rail_flight'), journeyPoints('rail_flight', [1]));
      expect(session.scoreOf('rail_flight'), greaterThan(0));
    });
  });
}
