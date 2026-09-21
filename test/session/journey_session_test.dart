import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/application/lane_runner_controller.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/domain/lane_runner_state.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_host.dart';
import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final routes = RouteService(MetroFixture.load());
  Journey journeyOf(String origin, String destination) =>
      routes.estimate(origin, destination).journey!;

  group('ortak yolculuk', () {
    test('oyun değişince puan ve kalan süre devam eder', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final session = JourneySession(journey: journey)
        ..setStatus(GameStatus.playing);

      final first = LaneRunnerController(
        journey: journey,
        recordToBeat: 0,
        session: session,
      )..start();
      first.debugAdvance(30);
      final scoreAfterFirst = session.score + 120;
      session.addScore(120, gameId: LaneRunnerController.id);
      first.dispose();

      // Oyuncu oyun seçimine dönüp başka bir oyuna geçiyor.
      final second = MetroMergeController(
        journey: journey,
        recordToBeat: 0,
        session: session,
      )..start();

      expect(second.score, scoreAfterFirst, reason: 'puan sıfırlandı');
      expect(
        second.elapsedSeconds,
        closeTo(30, 0.001),
        reason: 'saat sıfırlandı',
      );
      expect(second.remainingSeconds, journey.estimatedSeconds - 30);
      second.dispose();
    });

    test('yanmak yolculuğu bitirmez, puan durur', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final session = JourneySession(journey: journey)
        ..setStatus(GameStatus.playing);
      final controller = LaneRunnerController(
        journey: journey,
        recordToBeat: 0,
        session: session,
      )..start();

      session.addScore(80, gameId: LaneRunnerController.id);
      controller.debugAdvance(10);
      // Oyun kendi puanını da kazanmış olabilir; korunan şey o anki toplam.
      final scoreBeforeCrash = session.score;
      // Oyunun kendi kuralıyla bitişi: tren kapalı raya girer.
      controller.debugSetObstacles(<LaneObstacle>[
        LaneObstacle(id: 0, lane: controller.trainLane, y: laneRunnerTrainY),
      ]);
      controller.debugAdvance(0.016);

      expect(controller.status, GameStatus.gameOver);
      expect(session.status, GameStatus.playing, reason: 'yolculuk da bitti');
      expect(session.score, scoreBeforeCrash);
      expect(session.elapsedSeconds, greaterThan(9));
      controller.dispose();
    });

    test('ortak yolculukta yeniden başlatmak yalnızca oyunu sıfırlar', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final session = JourneySession(journey: journey)
        ..setStatus(GameStatus.playing);
      final controller = LaneRunnerController(
        journey: journey,
        recordToBeat: 0,
        session: session,
      )..start();

      session.addScore(200, gameId: LaneRunnerController.id);
      controller.debugAdvance(45);
      final scoreBeforeRestart = session.score;
      controller.restart();

      expect(session.score, scoreBeforeRestart);
      expect(session.elapsedSeconds, closeTo(45, 0.001));
      expect(controller.passes, 0, reason: 'oyun sıfırlanmadı');
      controller.dispose();
    });

    test('tek oyunluk yolculukta yeniden başlatmak her şeyi sıfırlar', () {
      // Oturumu kendi kuran controller eski davranışı sürdürür.
      final controller = LaneRunnerController(
        journey: journeyOf('m2_taksim', 'm2_levent'),
        recordToBeat: 0,
      )..start();
      controller.debugAdvance(40);
      controller.restart();

      expect(controller.score, 0);
      expect(controller.elapsedSeconds, closeTo(0, 0.001));
      controller.dispose();
    });
  });

  group('yolculuk tutamağı', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Future<JourneyController> hostWith(LocalStore store) async =>
        JourneyController(store: store, routes: routes);

    test('oyun yokken kalp atışı treni ilerletir', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final session = host.start(journeyOf('m2_taksim', 'm2_levent'));

      host.beat();
      host.beat();

      expect(session.elapsedSeconds, 2);
      host.dispose();
    });

    test('oyun sürerken kalp atışı saati ikinci kez ilerletmez', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final session = host.start(journey);
      final controller = LaneRunnerController(
        journey: journey,
        recordToBeat: 0,
        session: session,
      )..start();

      host.beat();

      expect(session.elapsedSeconds, 0, reason: 'çift sayıldı');
      controller.dispose();
      host.dispose();
    });

    test('arka planda geçen süre dönüşte yolculuğa yazılır', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final start = DateTime(2026, 9, 20, 12);
      late JourneySession session;

      withClock(Clock.fixed(start), () {
        session = host.start(journeyOf('m2_taksim', 'm2_levent'));
        host.onBackground();
      });
      withClock(Clock.fixed(start.add(const Duration(seconds: 40))), () {
        host.onForeground();
      });

      expect(session.elapsedSeconds, closeTo(40, 0.001));
      host.dispose();
    });

    test('süre oyun yokken biterse yolculuk varışla kapanır', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final journey = journeyOf('m2_taksim', 'm2_osmanbey');
      final session = host.start(journey);
      session.addScore(500, gameId: 'blocks');

      final start = DateTime(2026, 9, 20, 12);
      withClock(Clock.fixed(start), host.onBackground);
      withClock(
        Clock.fixed(start.add(Duration(seconds: journey.estimatedSeconds + 5))),
        host.onForeground,
      );

      expect(session.status, GameStatus.arrived);
      await Future<void>.delayed(Duration.zero);
      expect(
        store.bestJourneyScore(journey.origin.id, journey.destination.id),
        500,
        reason: 'varışta rota rekoru yazılmadı',
      );
      host.dispose();
    });

    test('aynı rotaya dönünce yolculuk baştan başlamaz', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final first = host.start(journey);
      first.addScore(90, gameId: 'blocks');

      final again = host.start(journeyOf('m2_taksim', 'm2_levent'));

      expect(identical(first, again), isTrue);
      expect(again.score, 90);
      host.dispose();
    });

    test('yolculuğu kapatmak puanı rotanın rekoruna yazar', () async {
      final store = LocalStore();
      await store.init();
      final host = await hostWith(store);
      final journey = journeyOf('m2_taksim', 'm2_levent');
      host.start(journey).addScore(320, gameId: 'blocks');

      host.close();
      await Future<void>.delayed(Duration.zero);

      expect(
        store.bestJourneyScore(journey.origin.id, journey.destination.id),
        320,
      );
      expect(host.session, isNull);
      host.dispose();
    });
  });
}
