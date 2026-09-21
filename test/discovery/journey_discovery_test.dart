import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/application/journey_discovery.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

/// Kendi kuralı olmayan bir oyun: yalnız yolculuk motorunu çalıştırır.
class _PlainRun extends JourneyGameController {
  _PlainRun({required super.journey, required super.discovery})
    : super(gameId: 'test', recordToBeat: 0, tick: const Duration(seconds: 1));

  @override
  void onTick(double dt) {}

  @override
  void onRestart() {}

  /// `endGame` korumalı; test dışarıdan bitiremesin diye alt sınıf açıyor.
  void finishEarly() => endGame();
}

void main() {
  final repository = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(repository);
  final routes = RouteService(repository);

  Journey journeyOf(String origin, String destination) =>
      routes.estimate(origin, destination).journey!;

  ({JourneyDiscovery run, DiscoveryController state}) bind(
    Journey journey, {
    DiscoveryController? state,
  }) {
    final controller = state ?? DiscoveryController(catalog: catalog);
    return (
      run: JourneyDiscovery(
        journey: journey,
        discovery: controller,
        gameId: 'test',
      ),
      state: controller,
    );
  }

  group('JourneyDiscovery', () {
    test('rota seçmek keşif üretmez', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));

      expect(bound.state.discoveredCount, 0);
      expect(bound.run.newStationCount, 0);
    });

    test('oyun başlayınca biniş durağı keşfedilir', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run.reportReached(0);

      expect(bound.state.isDiscovered('taksim'), isTrue);
      expect(bound.state.discoveredCount, 1);
    });

    test('geçilen duraklar sırayla keşfedilir', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run
        ..reportReached(0)
        ..reportReached(1)
        ..reportReached(2);

      expect(bound.run.newStations.map((s) => s.name), <String>[
        'Taksim',
        'Osmanbey',
        'Şişli-Mecidiyeköy',
      ]);
    });

    test('büyük sıçrama aradaki tüm durakları işler', () {
      final bound = bind(journeyOf('m2_yenikapi', 'm2_haciosman'));
      bound.run
        ..reportReached(0)
        // %21'den %49'a atlayan bir kare: aradaki dört durak da geçilmiştir.
        ..reportReached(6);

      expect(bound.state.discoveredCount, 7);
    });

    test('aynı indeks iki kez bildirilirse ikincisi bir şey yapmaz', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run
        ..reportReached(2)
        ..reportReached(2)
        ..reportReached(1);

      expect(bound.state.discoveredCount, 3);
    });

    test('varış çağrılmadan son durak keşfedilmez', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      // Yuvarlama yüzünden gelen fazla büyük değer bile son durağı açmamalı.
      bound.run.reportReached(999);

      expect(bound.state.isDiscovered('levent'), isFalse);
      expect(bound.state.discoveredCount, bound.run.routeLength - 1);
    });

    test('varışta son durak keşfedilir', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run
        ..reportReached(0)
        ..reportArrival();

      expect(bound.state.isDiscovered('levent'), isTrue);
      expect(bound.state.discoveredCount, bound.run.routeLength);
    });

    test('iki duraklık rota: biniş başlarken, iniş varışta', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_osmanbey'));
      bound.run.reportReached(0);
      expect(bound.state.discoveredCount, 1);
      expect(bound.state.isDiscovered('osmanbey'), isFalse);

      bound.run.reportArrival();
      expect(bound.state.discoveredCount, 2);
    });

    test('ters rota da çalışır', () {
      final bound = bind(journeyOf('m2_levent', 'm2_taksim'));
      bound.run
        ..reportReached(0)
        ..reportReached(1);

      expect(bound.state.isDiscovered('levent'), isTrue);
      expect(bound.state.isDiscovered('gayrettepe'), isTrue);
      expect(bound.state.isDiscovered('taksim'), isFalse);
    });

    test('yarım kalan koşunun keşifleri kalır', () {
      final state = DiscoveryController(catalog: catalog);
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'), state: state);
      bound.run.reportReached(2);

      // Oyun burada bitti: varış yok.
      expect(state.discoveredCount, 3);
      expect(state.isDiscovered('levent'), isFalse);
    });

    test('tekrar oynamak yeni keşif üretmez', () {
      final state = DiscoveryController(catalog: catalog);
      final journey = journeyOf('m2_taksim', 'm2_levent');

      final first = bind(journey, state: state);
      first.run
        ..reportReached(0)
        ..reportReached(2);
      expect(first.run.newStationCount, 3);

      final second = bind(journey, state: state);
      second.run
        ..reportReached(0)
        ..reportReached(2);

      expect(second.run.newStationCount, 0);
      expect(state.discoveredCount, 3);

      // Daha ileri gidilirse yalnız yeni durak sayılır.
      second.run.reportReached(3);
      expect(second.run.newStationCount, 1);
    });

    test('koşuya özgü yeni keşif kalıcı durumdan ayrıdır', () {
      final state = DiscoveryController(catalog: catalog)
        ..discoverAll(<String>['taksim']);
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'), state: state);
      bound.run
        ..reportReached(0)
        ..reportReached(1);

      expect(bound.run.isNewInRun('taksim'), isFalse);
      expect(bound.run.isNewInRun('osmanbey'), isTrue);
      expect(bound.run.newStationCount, 1);
    });

    test('yeniden başlatma koşu defterini siler, keşfi silmez', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run.reportReached(2);
      expect(bound.run.newStationCount, 3);

      bound.run.reset();

      expect(bound.run.newStationCount, 0);
      expect(bound.state.discoveredCount, 3);
    });
  });

  group('JourneyDiscovery — oturum sayacı', () {
    test('yeniden başlatma oturum toplamını korur', () {
      final state = DiscoveryController(catalog: catalog);
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'), state: state);
      bound.run.reportReached(2);

      expect(bound.run.newStationCount, 3);
      expect(bound.run.sessionStationCount, 3);
      expect(bound.run.hasHiddenSessionDiscoveries, isFalse);

      // Oyuncu yarıda yeniden başlattı: koşu defteri sıfırlandı, kalıcı
      // keşif ve oturum toplamı durdu.
      bound.run.reset();
      expect(bound.run.newStationCount, 0);
      expect(bound.run.sessionStationCount, 3);
      expect(bound.run.hasHiddenSessionDiscoveries, isTrue);

      // İkinci denemede daha ileri gidildi.
      bound.run.reportReached(3);
      expect(bound.run.newStationCount, 1);
      expect(bound.run.sessionStationCount, 4);
      expect(bound.run.hasHiddenSessionDiscoveries, isTrue);
    });

    test('yeniden başlatma olmayınca gizli keşif de yok', () {
      final bound = bind(journeyOf('m2_taksim', 'm2_levent'));
      bound.run.reportReached(1);

      expect(bound.run.hasHiddenSessionDiscoveries, isFalse);
    });
  });

  group('JourneyDiscovery — bozuk rota', () {
    test('çözülemeyen rota geliştirme derlemesinde yüksek sesle düşer', () {
      // Hat kimliği katalogda yoksa rota boş çözülür ve keşif o yolculukta
      // sessizce ölürdü: oyun normal oynanır, hiçbir durak keşfedilmez,
      // hata da görünmez.
      final real = journeyOf('m2_taksim', 'm2_levent');
      final broken = Journey(
        origin: real.origin,
        destination: real.destination,
        estimatedSeconds: real.estimatedSeconds,
        stopCount: real.stopCount,
        difficulty: real.difficulty,
        lineId: 'BOYLE_BIR_HAT_YOK',
      );

      expect(
        () => JourneyDiscovery(
          journey: broken,
          discovery: DiscoveryController(catalog: catalog),
          gameId: 'test',
        ),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'mesaj',
            contains('BOYLE_BIR_HAT_YOK'),
          ),
        ),
      );
    });
  });

  group('Yolculuk motoru → keşif', () {
    test('start biniş durağını keşfeder', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final bound = bind(journey);
      final run = _PlainRun(journey: journey, discovery: bound.run);

      expect(bound.state.discoveredCount, 0);
      run.start();
      expect(bound.state.isDiscovered('taksim'), isTrue);
      run.dispose();
    });

    test('durak geçildikçe keşfedilir, varış durağı varışta açılır', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final bound = bind(journey);
      final run = _PlainRun(journey: journey, discovery: bound.run)..start();

      // Yolculuğun yarısı: biniş + aradaki duraklar, iniş durağı hariç.
      run.debugAdvance(journey.estimatedSeconds / 2);
      expect(bound.state.isDiscovered('levent'), isFalse);
      expect(bound.state.discoveredCount, greaterThan(1));

      run.debugAdvance(journey.estimatedSeconds.toDouble());
      expect(run.status, GameStatus.arrived);
      expect(bound.state.isDiscovered('levent'), isTrue);
      run.dispose();
    });

    test('oyun sonu varış durağını açmaz', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final bound = bind(journey);
      final run = _PlainRun(journey: journey, discovery: bound.run)..start();

      // Yolculuğun son saniyesinde oyun bitiyor.
      run.debugAdvance(journey.estimatedSeconds - 1);
      run.finishEarly();

      expect(run.status, GameStatus.gameOver);
      expect(bound.state.isDiscovered('levent'), isFalse);
      run.dispose();
    });

    test('keşif kapalıyken motor aynen çalışır', () {
      final journey = journeyOf('m2_taksim', 'm2_levent');
      final run = _PlainRun(journey: journey, discovery: null)..start();
      run.debugAdvance(journey.estimatedSeconds.toDouble());

      expect(run.status, GameStatus.arrived);
      run.dispose();
    });
  });
}
