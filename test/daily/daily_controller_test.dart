import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/daily/application/daily_controller.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_generator.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_mission.dart';
import 'package:istanbul_metro_game/features/daily/domain/day_stamp.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:istanbul_metro_game/features/session/run_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Günlük sistemin davranışı: gün dönümü, görev ilerlemesi ve seri.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metro = MetroFixture.load();
  final routes = RouteService(metro);
  final generator = DailyGenerator(metro: metro, routes: routes);

  Future<LocalStore> freshStore([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{...seed});
    final store = LocalStore();
    await store.init();
    return store;
  }

  /// Verilen plana birebir uyan bir koşu raporu.
  RunReport dailyRun(DailyController daily, {bool arrived = true}) {
    final plan = daily.plan!;
    return RunReport(
      gameId: plan.gameId,
      journey: plan.journey,
      status: arrived ? GameStatus.arrived : GameStatus.gameOver,
      score: 100,
      stationsPassed: arrived ? plan.journey.stopCount : 1,
    );
  }

  /// Günün planıyla ilgisi olmayan, **sayılacak kadar oynanmış** bir koşu.
  RunReport otherRun({
    String gameId = 'blocks',
    GameStatus status = GameStatus.gameOver,
    int stationsPassed = 1,
  }) {
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
    return RunReport(
      gameId: gameId,
      journey: journey,
      status: status,
      score: 10,
      stationsPassed: stationsPassed,
    );
  }

  test('bugünün planı kurulur', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final daily = DailyController(generator: generator, store: store);
      addTearDown(daily.dispose);

      expect(daily.plan, isNotNull);
      expect(daily.day, const DayStamp(2026, 9, 20));
      expect(daily.missions, hasLength(3));
      expect(daily.isDailyComplete, isFalse);
      expect(daily.streak, 0);
    });
  });

  test('aynı gün yeniden açılınca ilerleme geri gelir', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final first = DailyController(generator: generator, store: store);
      first.reportRun(dailyRun(first));
      await first.flush();
      first.dispose();

      final second = DailyController(generator: generator, store: store);
      addTearDown(second.dispose);
      expect(second.isDailyComplete, isTrue);
      expect(second.counters.arrivals, 1);
      expect(second.streak, 1);
    });
  });

  test('ertesi gün sayaçlar sıfırlanır, seri korunur', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final today = DailyController(generator: generator, store: store);
      today.reportRun(dailyRun(today));
      await today.flush();
      today.dispose();
    });

    await withClock(Clock.fixed(DateTime(2026, 9, 21, 9)), () async {
      final tomorrow = DailyController(generator: generator, store: store);
      addTearDown(tomorrow.dispose);

      expect(tomorrow.isDailyComplete, isFalse);
      expect(tomorrow.counters.arrivals, 0);
      // Seri dünden geliyor ve hâlâ yaşıyor.
      expect(tomorrow.streak, 1);
      expect(tomorrow.streakCompletedToday, isFalse);
    });
  });

  test('ertesi gün rota değişir', () async {
    final store = await freshStore();
    late Journey first;
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final daily = DailyController(generator: generator, store: store);
      first = daily.plan!.journey;
      daily.dispose();
    });
    await withClock(Clock.fixed(DateTime(2026, 9, 21, 10)), () async {
      final daily = DailyController(generator: generator, store: store);
      addTearDown(daily.dispose);
      expect(
        '${daily.plan!.journey.origin.id}>${daily.plan!.journey.destination.id}'
        '${daily.plan!.gameId}',
        isNot('${first.origin.id}>${first.destination.id}'),
      );
    });
  });

  group('günlük tamamlanması', () {
    test('doğru rota ve doğru oyunla varış günü tamamlar', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(dailyRun(daily));
        expect(daily.isDailyComplete, isTrue);
        expect(daily.streak, 1);
        expect(daily.streakCompletedToday, isTrue);
      });
    });

    test('varamadan biten koşu günü tamamlamaz', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(dailyRun(daily, arrived: false));
        expect(daily.isDailyComplete, isFalse);
        expect(daily.streak, 0);
        // Koşunun kendisi yine de sayılır.
        expect(daily.counters.finishedRuns, 1);
      });
    });

    test('başka oyunla aynı rotayı bitirmek günü tamamlamaz', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);
        final plan = daily.plan!;
        final wrongGame = plan.gameId == 'blocks' ? 'metro_quiz' : 'blocks';

        daily.reportRun(
          RunReport(
            gameId: wrongGame,
            journey: plan.journey,
            status: GameStatus.arrived,
            score: 5,
          ),
        );
        expect(daily.isDailyComplete, isFalse);
      });
    });

    test('tek durak bile geçmeden biten koşu sayılmaz', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        // Oyunu açıp iki saniyede duvara çarpmak "oyun bitirmek" değil.
        daily.reportRun(otherRun(stationsPassed: 0));
        expect(daily.counters.finishedRuns, 0);
        expect(daily.counters.playedGameIds, isEmpty);
      });
    });

    test('yarıda bırakılan koşu hiçbir sayacı büyütmez', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(
          otherRun(status: GameStatus.abandoned, stationsPassed: 3),
        );
        expect(daily.counters.finishedRuns, 0);
        expect(daily.counters.playedGameIds, isEmpty);
      });
    });

    test('aynı gün ikinci kez tamamlamak seriyi iki katlamaz', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(dailyRun(daily));
        daily.reportRun(dailyRun(daily));
        daily.reportRun(dailyRun(daily));
        expect(daily.streak, 1);
      });
    });
  });

  group('görev ilerlemesi', () {
    test('oyun bitirmek ve farklı oyun oynamak sayılır', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(otherRun(gameId: 'blocks'));
        daily.reportRun(otherRun(gameId: 'blocks'));
        daily.reportRun(otherRun(gameId: 'metro_quiz'));

        expect(daily.counters.finishedRuns, 3);
        expect(daily.counters.playedGameIds, <String>{'blocks', 'metro_quiz'});
        expect(
          const DailyMission(
            type: DailyMissionType.playDistinctGames,
            target: 2,
          ).isCompleteFor(daily.counters),
          isTrue,
        );
      });
    });

    test('yalnızca yeni keşifler keşif görevini ilerletir', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportNewStations(2);
        daily.reportNewStations(0);
        expect(daily.counters.newStations, 2);
      });
    });

    test('tamamlanan görev bir kez duyurulur', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(dailyRun(daily));
        final announced = daily.consumeCompletedMissions();
        expect(
          announced.map((DailyMission m) => m.type),
          contains(DailyMissionType.dailyJourney),
        );
        // İkinci okuma boş: kutlama bir kez gösterilir.
        expect(daily.consumeCompletedMissions(), isEmpty);

        // Aynı günü tekrar oynamak yeniden duyurmaz.
        daily.reportRun(dailyRun(daily));
        expect(
          daily
              .consumeCompletedMissions()
              .map((DailyMission m) => m.type)
              .contains(DailyMissionType.dailyJourney),
          isFalse,
        );
      });
    });

    test('tamamlanma anı bir kez okunur', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);

        daily.reportRun(dailyRun(daily));
        expect(daily.consumeDailyCompletion(), isTrue);
        expect(daily.consumeDailyCompletion(), isFalse);
      });
    });
  });

  group('seri', () {
    test('ardışık iki gün', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        daily.reportRun(dailyRun(daily));
        await daily.flush();
        daily.dispose();
      });
      await withClock(Clock.fixed(DateTime(2026, 9, 21, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);
        daily.reportRun(dailyRun(daily));
        expect(daily.streak, 2);
        expect(daily.bestStreak, 2);
      });
    });

    test('atlanan gün seriyi kırar, en iyi kalır', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        daily.reportRun(dailyRun(daily));
        await daily.flush();
        daily.dispose();
      });
      await withClock(Clock.fixed(DateTime(2026, 9, 21, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        daily.reportRun(dailyRun(daily));
        await daily.flush();
        daily.dispose();
      });
      await withClock(Clock.fixed(DateTime(2026, 9, 24, 10)), () async {
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);
        expect(daily.streak, 0);
        expect(daily.bestStreak, 2);

        daily.reportRun(dailyRun(daily));
        expect(daily.streak, 1);
        expect(daily.bestStreak, 2);
      });
    });

    test('uygulamayı açmak seriyi büyütmez', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
        for (var i = 0; i < 3; i++) {
          DailyController(generator: generator, store: store).dispose();
        }
        final daily = DailyController(generator: generator, store: store);
        addTearDown(daily.dispose);
        expect(daily.streak, 0);
      });
    });
  });

  test('bozuk kayıt günü sıfırdan başlatır', () async {
    final store = await freshStore(<String, Object>{
      'daily_counters': '{bozuk',
      'daily_streak': 'x',
    });
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final daily = DailyController(generator: generator, store: store);
      addTearDown(daily.dispose);
      expect(daily.isDailyComplete, isFalse);
      expect(daily.streak, 0);
    });
  });
}
