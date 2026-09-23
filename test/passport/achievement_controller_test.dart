import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/daily/application/daily_controller.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_generator.dart';
import 'package:istanbul_metro_game/features/daily/domain/day_stamp.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/passport/application/achievement_controller.dart';
import 'package:istanbul_metro_game/features/passport/domain/achievement.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:istanbul_metro_game/features/session/run_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Pasaport başarımları.
///
/// Sınanan söz: başarım **kaynağından türer**, ikinci bir sayaç tutmaz, bir
/// kez açılır ve V4'ten önce oynamış oyuncunun ilerlemesi kaybolmaz.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);
  final generator = DailyGenerator(metro: metro, routes: routes);

  Future<LocalStore> storeWith([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{...seed});
    final store = LocalStore();
    await store.init();
    return store;
  }

  RunReport run({
    String gameId = 'blocks',
    GameStatus status = GameStatus.arrived,
    int stationsPassed = 2,
  }) => RunReport(
    gameId: gameId,
    journey: routes.estimate('m2_taksim', 'm2_levent').journey!,
    status: status,
    score: 100,
    stationsPassed: stationsPassed,
  );

  ({
    AchievementController achievements,
    DiscoveryController discovery,
    LocalStore store,
  })
  build(LocalStore store, {DailyController? daily}) {
    final discovery = DiscoveryController(catalog: catalog, store: store);
    final achievements = AchievementController(
      discovery: discovery,
      daily: daily,
      store: store,
    );
    addTearDown(achievements.dispose);
    addTearDown(discovery.dispose);
    return (achievements: achievements, discovery: discovery, store: store);
  }

  test('yeni oyuncuda hiçbir başarım açık değil', () async {
    final world = build(await storeWith());
    expect(world.achievements.unlockedCount, 0);
    expect(world.achievements.totalCount, Achievements.all.length);
  });

  test('ilk keşif ilk rozeti açar', () async {
    final world = build(await storeWith());
    world.discovery.discoverAll(<String>['taksim']);

    expect(world.achievements.isUnlocked(Achievements.firstDiscovery), isTrue);
    expect(world.achievements.isUnlocked(Achievements.explorerI), isFalse);
  });

  test('ilerleme kaynaktan okunur, sayaç tutulmaz', () async {
    final world = build(await storeWith());
    final ids = catalog.stations.take(7).map((CanonicalStation s) => s.id);
    world.discovery.discoverAll(ids);

    expect(world.achievements.progressOf(Achievements.explorerI), 7);
    // Aynı durakları tekrar yazmak ilerlemeyi şişirmez.
    world.discovery.discoverAll(ids);
    expect(world.achievements.progressOf(Achievements.explorerI), 7);
  });

  test('ilerleme hedefi aşmaz', () async {
    final world = build(await storeWith());
    world.discovery.discoverAll(
      catalog.stations.take(30).map((CanonicalStation s) => s.id),
    );
    expect(
      world.achievements.progressOf(Achievements.firstDiscovery),
      Achievements.firstDiscovery.target,
    );
    expect(world.achievements.progressRatio(Achievements.explorerI), 1.0);
  });

  test('yolculuk ve oyun başarımları koşudan gelir', () async {
    final world = build(await storeWith());

    world.achievements.reportRun(run());
    expect(world.achievements.isUnlocked(Achievements.firstJourney), isTrue);
    expect(world.achievements.stats.journeysCompleted, 1);

    // Varamadan biten koşu yolculuk saymaz ama oyun sayar.
    world.achievements.reportRun(
      run(gameId: 'metro_quiz', status: GameStatus.gameOver),
    );
    expect(world.achievements.stats.journeysCompleted, 1);
    expect(world.achievements.stats.playedGameIds, hasLength(2));

    // Yarıda bırakılan koşu hiç sayılmaz.
    world.achievements.reportRun(
      run(gameId: 'train_snake', status: GameStatus.abandoned),
    );
    expect(world.achievements.stats.playedGameIds, hasLength(2));

    // Tek durak bile geçmeden biten koşu da sayılmaz.
    world.achievements.reportRun(
      run(
        gameId: 'rail_flight',
        status: GameStatus.gameOver,
        stationsPassed: 0,
      ),
    );
    expect(world.achievements.stats.playedGameIds, hasLength(2));
  });

  test('açılma tekrarlanmaz ve yeniden açılışta korunur', () async {
    final store = await storeWith();
    final first = build(store);
    first.discovery.discoverAll(<String>['taksim']);
    // Kutlama bildirimi bir sonraki mikro görevde geliyor: keşif, build
    // sırasında yeniden çizim hatası çıkmasın diye bildirimini erteliyor.
    await Future<void>.delayed(Duration.zero);
    expect(first.achievements.consumeUnlocked(), hasLength(1));
    // İkinci okuma boş: aynı rozet iki kez kutlanmaz.
    expect(first.achievements.consumeUnlocked(), isEmpty);
    await first.achievements.flush();
    await first.discovery.flush();

    final second = build(store);
    expect(second.achievements.isUnlocked(Achievements.firstDiscovery), isTrue);
    // Yeniden açılış kutlama üretmez.
    expect(second.achievements.consumeUnlocked(), isEmpty);
  });

  test('V4 öncesi ilerleme geriye dönük açılır ama gürültü yapmaz', () async {
    // Oyuncu V4'ten önce 25 durak keşfetmiş: kayıtta duruyor, rozet yok.
    final discovered = catalog.stations
        .take(25)
        .map((CanonicalStation s) => s.id)
        .toList();
    final store = await storeWith(<String, Object>{
      'discovered_stations': discovered,
    });

    final world = build(store);
    expect(world.achievements.isUnlocked(Achievements.firstDiscovery), isTrue);
    expect(world.achievements.isUnlocked(Achievements.explorerI), isTrue);
    expect(world.achievements.isUnlocked(Achievements.explorerII), isTrue);
    expect(world.achievements.isUnlocked(Achievements.explorerIII), isFalse);
    // Açılış anında beş pencere birden açılmaz.
    expect(world.achievements.consumeUnlocked(), isEmpty);
  });

  test('aktarma sayısı katalogdan türer', () async {
    final interchanges = catalog.stations
        .where((CanonicalStation s) => s.isInterchange)
        .toList();
    expect(
      interchanges,
      isNotEmpty,
      reason: 'Test verisinde aktarma durağı olmalı',
    );

    final world = build(await storeWith());
    world.discovery.discoverAll(
      interchanges.take(2).map((CanonicalStation s) => s.id),
    );
    expect(world.achievements.progressOf(Achievements.interchange), 2);
  });

  test('hat tamamlanınca hat başarımı açılır', () async {
    final world = build(await storeWith());
    final lineId = catalog.lineIds.first;
    world.discovery.discoverAll(
      catalog.stationsOfLine(lineId).map((CanonicalStation s) => s.id),
    );

    expect(world.discovery.isLineComplete(lineId), isTrue);
    expect(world.achievements.isUnlocked(Achievements.lineComplete), isTrue);
  });

  test('seri başarımı günlük sistemden okunur', () async {
    final store = await storeWith();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final daily = DailyController(generator: generator, store: store);
      addTearDown(daily.dispose);
      final world = build(store, daily: daily);

      expect(world.achievements.progressOf(Achievements.streakThree), 0);

      final plan = daily.plan!;
      daily.reportRun(
        RunReport(
          gameId: plan.gameId,
          journey: plan.journey,
          status: GameStatus.arrived,
          score: 1,
        ),
      );
      expect(world.achievements.progressOf(Achievements.streakThree), 1);
      expect(world.achievements.isUnlocked(Achievements.streakThree), isFalse);
    });
  });

  test('Metro Bilgi başarımı kayıtlı rekordan okunur', () async {
    final store = await storeWith();
    await store.submitGameRouteScore(
      gameId: 'metro_quiz',
      originId: 'm2_taksim',
      destinationId: 'm2_levent',
      score: 420,
    );

    final world = build(store);
    expect(world.achievements.progressOf(Achievements.quizMilestone), 400);
    expect(world.achievements.isUnlocked(Achievements.quizMilestone), isTrue);
  });

  test('başarım açıldığı günü taşır', () async {
    final store = await storeWith();
    await withClock(Clock.fixed(DateTime(2026, 9, 20, 10)), () async {
      final world = build(store);
      world.discovery.discoverAll(<String>['taksim']);
      await Future<void>.delayed(Duration.zero);

      expect(
        world.achievements.unlockedOn(Achievements.firstDiscovery),
        const DayStamp(2026, 9, 20),
      );
      await world.achievements.flush();
    });

    // Yeniden açılışta tarih kayıttan geri geliyor.
    final again = build(store);
    expect(
      again.achievements.unlockedOn(Achievements.firstDiscovery),
      const DayStamp(2026, 9, 20),
    );
  });

  test('geriye dönük açılan rozette tarih uydurulmaz', () async {
    final store = await storeWith(<String, Object>{
      'discovered_stations': <String>['taksim'],
    });
    final world = build(store);
    expect(world.achievements.isUnlocked(Achievements.firstDiscovery), isTrue);
    expect(world.achievements.unlockedOn(Achievements.firstDiscovery), isNull);
  });

  test('sıralama açılanları öne alır', () async {
    final world = build(await storeWith());
    world.discovery.discoverAll(
      catalog.stations.take(12).map((CanonicalStation s) => s.id),
    );

    final ordered = world.achievements.ordered;
    final firstLocked = ordered.indexWhere(
      (AchievementDefinition d) => !world.achievements.isUnlocked(d),
    );
    // Açık rozetlerden sonra kilitliler geliyor; karışmıyorlar.
    for (var i = firstLocked; i < ordered.length; i++) {
      expect(world.achievements.isUnlocked(ordered[i]), isFalse);
    }
    expect(ordered, hasLength(world.achievements.totalCount));
  });

  test('bütün oyunlar başarımının hedefi katalogdan geliyor', () {
    expect(Achievements.everyGame.target, greaterThan(1));
  });

  test('bozuk oyuncu kaydı çökmez', () async {
    final store = await storeWith(<String, Object>{'player_stats': '{bozuk'});
    final world = build(store);
    expect(world.achievements.stats.journeysCompleted, 0);
  });

  test('oyun ustalığı rozeti yalnız kendi oyununun koşularını sayar', () async {
    final world = build(await storeWith());

    for (var i = 0; i < 9; i++) {
      world.achievements.reportRun(run(gameId: 'crossing'));
    }
    world.achievements.reportRun(run(gameId: 'blocks'));
    expect(world.achievements.progressOf(Achievements.crossingMaster), 9);
    expect(world.achievements.progressOf(Achievements.blocksMaster), 1);
    expect(world.achievements.isUnlocked(Achievements.crossingMaster), isFalse);

    // Yarıda bırakılan koşu ustalığa sayılmaz.
    world.achievements.reportRun(
      run(gameId: 'crossing', status: GameStatus.gameOver, stationsPassed: 0),
    );
    expect(world.achievements.progressOf(Achievements.crossingMaster), 9);

    world.achievements.reportRun(run(gameId: 'crossing'));
    expect(world.achievements.isUnlocked(Achievements.crossingMaster), isTrue);
  });

  test('koşu sayıları kayıtta kalır, eski kayıt sorunsuz okunur', () async {
    // Koşu sayacından önce yazılmış kayıt: `runs` alanı yok.
    final store = await storeWith(<String, Object>{
      'player_stats': '{"journeys":3,"games":["blocks"]}',
    });
    final first = build(store);
    expect(first.achievements.stats.journeysCompleted, 3);
    expect(first.achievements.stats.runsOf('blocks'), 0);

    first.achievements.reportRun(run(gameId: 'blocks'));
    await Future<void>.delayed(Duration.zero);

    final second = build(store);
    expect(second.achievements.stats.runsOf('blocks'), 1);
    expect(second.achievements.stats.journeysCompleted, 4);
  });
}
