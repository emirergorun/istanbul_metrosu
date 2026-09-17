import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

/// Motorun yolculuk kazancı kanalı — altı oyunun ortak yolu.
///
/// "İyi oyun treni hızlandırır" kuralı Blok Metro'da yazılmıştı; motora
/// taşınınca her oyun kullanabilir hale geldi. Kritik nokta özyineleme:
/// gerçek zamanlı oyunlar kazancı [onTick] içinden bildiriyor, oradan
/// doğrudan `advance` çağırmak sonsuz döngü olurdu.
class _TestGame extends JourneyGameController {
  _TestGame({
    required super.journey,
    this.secondsPerGoodMove = 0,
    this.goodMovePerTick = false,
  }) : super(gameId: 'test', recordToBeat: 0, tick: const Duration(days: 1));

  final double secondsPerGoodMove;

  /// Her karede bir "iyi hamle" bildir — özyineleme tuzağını sınamak için.
  final bool goodMovePerTick;

  int ticks = 0;

  @override
  double get journeySecondsPerGoodMove => secondsPerGoodMove;

  @override
  void onTick(double dt) {
    ticks++;
    if (goodMovePerTick) markStationProgress();
  }

  @override
  void onRestart() {}

  void reportGoodMove() => markStationProgress();
}

void main() {
  final routes = RouteService(MetroFixture.load());
  Journey longJourney() =>
      routes.estimate('m2_yenikapi', 'm2_haciosman').journey!;

  test('varsayılan kapalı: kazanç tanımlanmazsa saat normal akar', () {
    final game = _TestGame(journey: longJourney())..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.debugAdvance(1);

    expect(game.elapsedSeconds, 1);
  });

  test('iyi hamle yolculuğa saniye katar', () {
    final game = _TestGame(journey: longJourney(), secondsPerGoodMove: 4)
      ..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.debugAdvance(1);

    expect(game.elapsedSeconds, 5, reason: '1 sn saat + 4 sn kazanç');
  });

  test('kazanç bir sonraki karede yazılır, biriktirilir', () {
    final game = _TestGame(journey: longJourney(), secondsPerGoodMove: 2)
      ..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.reportGoodMove();
    game.reportGoodMove();
    // Henüz kare işlenmedi.
    expect(game.elapsedSeconds, 0);

    game.debugAdvance(1);
    expect(game.elapsedSeconds, 7, reason: '1 sn saat + 3 x 2 sn kazanç');
  });

  test('kazanç iki kez yazılmaz', () {
    final game = _TestGame(journey: longJourney(), secondsPerGoodMove: 3)
      ..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.debugAdvance(1);
    game.debugAdvance(1);

    expect(game.elapsedSeconds, 5, reason: '2 sn saat + tek seferlik 3 sn');
  });

  test('onTick içinden bildirilen kazanç özyinelemeye girmez', () {
    // Gerçek zamanlı oyunların yolu: her karede kapı geçilebiliyor.
    final game = _TestGame(
      journey: longJourney(),
      secondsPerGoodMove: 1,
      goodMovePerTick: true,
    )..start();
    addTearDown(game.dispose);

    game.debugAdvance(1);

    expect(game.ticks, 1, reason: 'kare bir kez işlenmeli');
    expect(game.elapsedSeconds, 2, reason: '1 sn saat + 1 sn kazanç');
  });

  test('kazanç durak geçişini tetikleyebilir', () {
    final journey = longJourney();
    final perStop = journey.estimatedSeconds / journey.stopCount;

    final game = _TestGame(journey: journey, secondsPerGoodMove: perStop)
      ..start();
    addTearDown(game.dispose);

    expect(game.stationsPassed, 0);

    game.reportGoodMove();
    game.debugAdvance(1);

    expect(game.stationsPassed, greaterThan(0));
    expect(game.stationPulse, greaterThan(0));
  });

  test('kazanç varışı tetikleyebilir', () {
    final journey = longJourney();
    final game = _TestGame(
      journey: journey,
      secondsPerGoodMove: journey.estimatedSeconds.toDouble(),
    )..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.debugAdvance(1);

    expect(game.status, GameStatus.arrived);
  });

  test('yeniden başlatma birikmiş kazancı siler', () {
    final game = _TestGame(journey: longJourney(), secondsPerGoodMove: 5)
      ..start();
    addTearDown(game.dispose);

    game.reportGoodMove();
    game.restart();
    game.debugAdvance(1);

    expect(game.elapsedSeconds, 1, reason: 'eski kazanç yeni koşuya taşınmaz');
  });

  test('durak bonusu hakkı kazançtan bağımsız işler', () {
    final game = _TestGame(journey: longJourney())..start();
    addTearDown(game.dispose);

    // Kazanç kapalı olsa da "bu duraktan beri bir şey yaptım" işareti
    // konmalı; durak bonusunun koşulu bu.
    game.reportGoodMove();
    game.debugAdvance(1);

    expect(game.elapsedSeconds, 1);
  });
}
