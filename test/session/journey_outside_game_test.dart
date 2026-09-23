import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/application/journey_discovery.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_host.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:istanbul_metro_game/features/session/run_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Yolculuk oyun ekranından **uzun yaşıyor**: tren oyun seçim ekranında,
/// başlık ekranında ve uygulama arka plandayken de yol alıyor.
///
/// Ortak yolculuk motoruna geçilince keşif ve biten koşu bildirimi yalnız
/// oyun controller'ında kalmıştı; oyun kapalıyken geçilen duraklar
/// keşfedilmiyor, oyun seçim ekranında gelen varış ise günlük görevlere ve
/// pasaporta hiç ulaşmıyordu. Buradaki testler o zinciri kilitliyor.
class _RecordingReporter implements RunReporter {
  final List<RunReport> runs = <RunReport>[];
  int startedCount = 0;

  @override
  void reportRunStarted() => startedCount++;

  @override
  void reportRun(RunReport report) => runs.add(report);
}

/// Yolculuğu kendi kare döngüsüyle süren en küçük oyun.
class _DrivingGame extends JourneyGameController {
  _DrivingGame({required JourneySession session, required super.journey})
    : super(
        session: session,
        gameId: 'blocks',
        recordToBeat: 0,
        tick: const Duration(days: 1),
      );

  void scoreSome(int raw) => addScore(raw);

  void lose() => endGame();

  @override
  void onTick(double dt) {}

  @override
  void onRestart() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);

  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    return store;
  }

  ({
    JourneyController journey,
    DiscoveryController discovery,
    _RecordingReporter reporter,
  })
  wire(LocalStore store) {
    final discovery = DiscoveryController(catalog: catalog, store: store);
    final reporter = _RecordingReporter();
    final journey = JourneyController(
      store: store,
      routes: routes,
      discoveryFactory: (route) => JourneyDiscovery(
        journey: route,
        discovery: discovery,
        gameId: JourneySession.journeyBucket,
      ),
      reporter: reporter,
    );
    addTearDown(journey.dispose);
    addTearDown(discovery.dispose);
    return (journey: journey, discovery: discovery, reporter: reporter);
  }

  Journey route() => routes.estimate('m2_taksim', 'm2_levent').journey!;

  /// Kalp atışını [seconds] kez çağırır — oyun yokken saat böyle akıyor.
  void beatFor(JourneyController controller, int seconds) {
    for (var i = 0; i < seconds; i++) {
      controller.beat();
    }
  }

  test('oyun açık değilken geçilen duraklar keşfediliyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    world.journey.start(journey);
    // Oyun seçim ekranında bekleyen oyuncu: tren yol alıyor, oyun yok.
    beatFor(world.journey, journey.estimatedSeconds ~/ 2);
    await Future<void>.delayed(Duration.zero);

    expect(world.journey.session!.stationsPassed, greaterThan(0));
    expect(
      world.discovery.discoveredCount,
      world.journey.session!.stationsPassed + 1,
      reason: 'geçilen duraklar + biniş durağı',
    );
  });

  test('rota seçmek tek başına keşif üretmez', () async {
    final store = await freshStore();
    final world = wire(store);

    world.journey.start(route());
    await Future<void>.delayed(Duration.zero);

    // Tren henüz hiçbir durağı geçmedi; biniş durağı bile açılmamalı.
    expect(world.discovery.discoveredCount, 0);
  });

  test('oyun açık değilken gelen varış keşfi ve koşuyu bildiriyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    world.journey.start(journey);
    // Oyuncu bir oyun oynayıp çıktı; yolculuk oyun seçiminde tamamlanıyor.
    world.journey.setGamePayload('blocks', null);
    beatFor(world.journey, journey.estimatedSeconds + 1);
    await Future<void>.delayed(Duration.zero);

    expect(world.journey.session!.status, GameStatus.arrived);
    // İniş durağı dahil rotanın tamamı keşfedildi.
    expect(
      world.discovery.discoveredCount,
      catalog.routeStationIds(journey).length,
    );
    // Günlük görev ve pasaport zinciri varışı gördü.
    expect(world.reporter.runs, hasLength(1));
    expect(world.reporter.runs.single.gameId, 'blocks');
    expect(world.reporter.runs.single.arrived, isTrue);
  });

  test('hiç oyun oynanmadıysa koşu bildirilmiyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    world.journey.start(journey);
    beatFor(world.journey, journey.estimatedSeconds + 1);

    expect(world.journey.session!.status, GameStatus.arrived);
    // Yolculuk tamamlandı ama oyuncu hiçbir oyuna girmedi: "oyun bitir"
    // görevini ilerletecek bir koşu yok.
    expect(world.reporter.runs, isEmpty);
  });

  test('arka planda geçen süre durakları keşfe yazıyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();
    final start = DateTime(2026, 9, 21, 8);

    await withClock(Clock.fixed(start), () async {
      world.journey.start(journey);
      world.journey.onBackground();
    });
    // Telefon cebe girdi, beş dakika sonra çıktı: durak aralığı bu rotada
    // ~137 sn, yani en az iki durak geçilmiş olmalı.
    await withClock(
      Clock.fixed(start.add(const Duration(minutes: 5))),
      () async {
        world.journey.onForeground();
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(world.journey.session!.stationsPassed, greaterThan(0));
    expect(world.discovery.discoveredCount, greaterThan(0));
  });

  test('aynı durak iki kez keşfedilmiyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    world.journey.start(journey);
    beatFor(world.journey, journey.estimatedSeconds ~/ 2);
    await Future<void>.delayed(Duration.zero);
    final afterFirst = world.discovery.discoveredCount;

    // Aynı sayaç tekrar bildirilse de kalıcı keşif büyümemeli.
    beatFor(world.journey, 1);
    await Future<void>.delayed(Duration.zero);

    expect(world.discovery.discoveredCount, greaterThanOrEqualTo(afterFirst));
    expect(
      world.discovery.discoveredCount,
      world.journey.session!.stationsPassed + 1,
    );
  });

  test('oyun oynanırken gelen varış rotanın rekoruna yazılıyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    final session = world.journey.start(journey);
    // Oyun yolculuğu sürüyor: saati o ilerletiyor, tutamağın kalp atışı
    // geri çekiliyor.
    final game = _DrivingGame(session: session, journey: journey)
      ..reporter = world.reporter;
    addTearDown(game.dispose);
    game.start();
    game.scoreSome(500);
    game.debugAdvance(journey.estimatedSeconds.toDouble());
    await Future<void>.delayed(Duration.zero);

    expect(session.status, GameStatus.arrived);
    // Rekor yolculuk tutamağı tarafından yazılır; oyun kendi başına
    // yazmıyor (rota puanı ortak).
    expect(
      store.bestJourneyScore(journey.origin.id, journey.destination.id),
      session.score,
    );
    // Varan yolculuk yarım kalmış sayılmaz.
    expect(store.savedJourney ?? '', isEmpty);
    // Rapor bir kez: oyun gönderdi, tutamak ikinciyi göndermedi.
    expect(world.reporter.runs, hasLength(1));
  });

  test('oyun bitmesi yolculuğu bitirmiyor', () async {
    final store = await freshStore();
    final world = wire(store);
    final journey = route();

    final session = world.journey.start(journey);
    final game = _DrivingGame(session: session, journey: journey)
      ..reporter = world.reporter;
    addTearDown(game.dispose);
    game.start();
    game.scoreSome(120);
    game.debugAdvance(30);
    game.lose();

    expect(game.status, GameStatus.gameOver);
    // Yolculuk sürüyor: puan, kalan süre ve durak sayacı duruyor.
    expect(session.status, GameStatus.playing);
    expect(session.score, greaterThan(0));
    expect(session.remainingSeconds, greaterThan(0));

    // Oyuncu başka bir oyuna geçse de aynı yolculuk sürer.
    expect(identical(world.journey.start(journey), session), isTrue);
  });
}
