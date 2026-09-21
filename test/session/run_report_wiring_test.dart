import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/daily/application/daily_controller.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_generator.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_mission.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/application/journey_discovery.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/passport/application/achievement_controller.dart';
import 'package:istanbul_metro_game/features/passport/domain/achievement.dart';
import 'package:istanbul_metro_game/features/session/composite_run_reporter.dart';
import 'package:istanbul_metro_game/features/session/run_report.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Motordan günlük göreve ve pasaporta giden yol.
///
/// Yedi oyunun hiçbiri günlük görevi ya da başarımı tanımıyor: koşu bitince
/// motor **tek** bir rapor gönderiyor, gerisini dinleyenler çözüyor. Burada
/// o zincirin uçtan uca çalıştığı gösteriliyor.
class _TestGame extends JourneyGameController {
  _TestGame({
    required super.journey,
    required super.gameId,
    super.discovery,
  }) : super(recordToBeat: 0, tick: const Duration(days: 1));

  @override
  void onTick(double dt) {}

  @override
  void onRestart() {}

  /// Oyunun kendi kaybetme koşulu — motorda korumalı olan [endGame]'in
  /// testten çağrılabilen hâli.
  void lose() => endGame();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);
  final generator = DailyGenerator(metro: metro, routes: routes);

  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    return store;
  }

  /// Keşif, günlük ve pasaport birlikte kurulur — uygulamadaki sırayla.
  ({
    DailyController daily,
    DiscoveryController discovery,
    AchievementController achievements,
    CompositeRunReporter reporter,
  })
  wire(LocalStore store) {
    final daily = DailyController(generator: generator, store: store);
    final discovery = DiscoveryController(
      catalog: catalog,
      store: store,
      onDiscovered: (result) => daily.reportNewStations(result.stations.length),
    );
    final achievements = AchievementController(
      discovery: discovery,
      daily: daily,
      store: store,
    );
    addTearDown(achievements.dispose);
    addTearDown(discovery.dispose);
    addTearDown(daily.dispose);
    return (
      daily: daily,
      discovery: discovery,
      achievements: achievements,
      reporter: CompositeRunReporter(<RunReporter>[daily, achievements]),
    );
  }

  /// Rotayı sonuna kadar oynar.
  void playToArrival(_TestGame game, Journey journey) {
    game.start();
    game.debugAdvance(journey.estimatedSeconds.toDouble());
  }

  test('günün yolculuğunu bitirmek zinciri baştan sona çalıştırır', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final plan = world.daily.plan!;

      final game = _TestGame(
        journey: plan.journey,
        gameId: plan.gameId,
        discovery: JourneyDiscovery(
          journey: plan.journey,
          discovery: world.discovery,
          gameId: plan.gameId,
        ),
      )..reporter = world.reporter;
      addTearDown(game.dispose);

      playToArrival(game, plan.journey);
      // Keşif bildirimi bir sonraki mikro görevde geliyor.
      await Future<void>.delayed(Duration.zero);

      expect(game.status, GameStatus.arrived);

      // V1a: rotanın bütün durakları kalıcı olarak keşfedildi.
      expect(
        world.discovery.discoveredCount,
        catalog.routeStationIds(plan.journey).length,
      );

      // V3: gün tamamlandı, seri başladı, görevler ilerledi.
      expect(world.daily.isDailyComplete, isTrue);
      expect(world.daily.streak, 1);
      expect(world.daily.counters.arrivals, 1);
      expect(world.daily.counters.finishedRuns, 1);
      expect(world.daily.counters.newStations, greaterThan(0));
      expect(
        world.daily.missions
            .where(world.daily.isMissionComplete)
            .map((DailyMission m) => m.type),
        contains(DailyMissionType.dailyJourney),
      );

      // V4: ilk yolculuk ve ilk keşif rozetleri açıldı.
      expect(
        world.achievements.isUnlocked(Achievements.firstJourney),
        isTrue,
      );
      expect(
        world.achievements.isUnlocked(Achievements.firstDiscovery),
        isTrue,
      );
      expect(world.achievements.stats.journeysCompleted, 1);
    });
  });

  test('yarıda bırakılan koşu hiçbir şeyi ilerletmez', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final plan = world.daily.plan!;

      final game = _TestGame(journey: plan.journey, gameId: plan.gameId)
        ..reporter = world.reporter;
      addTearDown(game.dispose);

      game.start();
      game.abandon();
      await Future<void>.delayed(Duration.zero);

      expect(world.daily.counters.finishedRuns, 0);
      expect(world.daily.isDailyComplete, isFalse);
      expect(world.achievements.stats.journeysCompleted, 0);
    });
  });

  test('başka rota günü tamamlamaz ama koşuyu sayar', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final other = routes.estimate('m2_taksim', 'm2_levent').journey!;

      final game = _TestGame(journey: other, gameId: 'blocks')
        ..reporter = world.reporter;
      addTearDown(game.dispose);

      playToArrival(game, other);
      await Future<void>.delayed(Duration.zero);

      expect(world.daily.isDailyComplete, isFalse);
      expect(world.daily.streak, 0);
      expect(world.daily.counters.arrivals, 1);
      expect(
        world.achievements.isUnlocked(Achievements.firstJourney),
        isTrue,
      );
    });
  });

  test('aynı koşu iki kez bildirilmez', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final other = routes.estimate('m2_taksim', 'm2_levent').journey!;

      final game = _TestGame(journey: other, gameId: 'blocks')
        ..reporter = world.reporter;
      addTearDown(game.dispose);

      game.start();
      // Bir durak geçilsin ki koşu sayılacak kadar oynanmış olsun.
      game.debugAdvance(other.estimatedSeconds / 2);
      // Oyun kendi kuralıyla iki kez bitirmeye kalkışsa bile tek koşu.
      game.lose();
      game.lose();
      await Future<void>.delayed(Duration.zero);

      expect(world.daily.counters.finishedRuns, 1);
    });
  });

  test('yarıda bırakılan koşunun kutlaması sonraki koşuya sarkmaz', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final plan = world.daily.plan!;

      // Birinci koşu: durak keşfedilir, görev tamamlanabilir, oyuncu
      // yarıda bırakır. Sonuç paneli hiç açılmadığı için kutlama okunmaz.
      final abandoned = _TestGame(
        journey: plan.journey,
        gameId: plan.gameId,
        discovery: JourneyDiscovery(
          journey: plan.journey,
          discovery: world.discovery,
          gameId: plan.gameId,
        ),
      )..reporter = world.reporter;
      abandoned.start();
      abandoned.debugAdvance(plan.journey.estimatedSeconds.toDouble());
      await Future<void>.delayed(Duration.zero);
      abandoned.dispose();

      // İkinci koşu başlıyor: kuyrukta bekleyen kutlama temizlenmeli.
      final next = _TestGame(journey: plan.journey, gameId: plan.gameId)
        ..reporter = world.reporter;
      addTearDown(next.dispose);
      next.start();

      expect(world.daily.consumeCompletedMissions(), isEmpty);
      expect(world.daily.consumeDailyCompletion(), isFalse);
      expect(world.achievements.consumeUnlocked(), isEmpty);
    });
  });

  test('yeniden başlayan koşu yeni bir koşudur', () async {
    final store = await freshStore();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = wire(store);
      final other = routes.estimate('m2_taksim', 'm2_levent').journey!;

      final game = _TestGame(journey: other, gameId: 'blocks')
        ..reporter = world.reporter;
      addTearDown(game.dispose);

      game.start();
      game.debugAdvance(other.estimatedSeconds / 2);
      game.lose();
      game.restart();
      game.debugAdvance(other.estimatedSeconds / 2);
      game.lose();
      await Future<void>.delayed(Duration.zero);

      expect(world.daily.counters.finishedRuns, 2);
    });
  });
}
