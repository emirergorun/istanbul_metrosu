import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repository = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(repository);

  Future<LocalStore> storeWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final store = LocalStore();
    await store.init();
    return store;
  }

  group('DiscoveryController — türetilen değerler', () {
    test('boş başlangıç sıfırdır', () {
      final discovery = DiscoveryController(catalog: catalog);

      expect(discovery.discoveredCount, 0);
      expect(discovery.progress, 0);
      expect(discovery.percent, 0);
      expect(discovery.isComplete, isFalse);
      expect(discovery.isDiscovered('taksim'), isFalse);
    });

    test('ilk keşif sayılır', () {
      final discovery = DiscoveryController(catalog: catalog);
      final result = discovery.discoverAll(<String>['taksim']);

      expect(result.stations.single.name, 'Taksim');
      expect(discovery.discoveredCount, 1);
      expect(discovery.isDiscovered('taksim'), isTrue);
    });

    test('aynı durak iki kez keşfedilmez', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['taksim']);
      final again = discovery.discoverAll(<String>['taksim']);

      expect(again.isEmpty, isTrue);
      expect(discovery.discoveredCount, 1);
    });

    test('tek çağrıda yinelenen kimlik tek keşiftir', () {
      final discovery = DiscoveryController(catalog: catalog);
      final result = discovery.discoverAll(<String>[
        'taksim',
        'taksim',
        'sishane',
      ]);

      expect(result.stations.length, 2);
      expect(discovery.discoveredCount, 2);
    });

    test('birden çok durak tek çağrıda işlenir', () {
      final discovery = DiscoveryController(catalog: catalog);
      final result = discovery.discoverAll(<String>[
        'yenikapi',
        'vezneciler_istanbul_u',
        'halic',
        'sishane',
      ]);

      expect(result.stations.length, 4);
      expect(discovery.discoveredCount, 4);
    });

    test('yüzde aşağı yuvarlanır', () {
      final discovery = DiscoveryController(catalog: catalog);
      // 143 durağın 142'si %99,3 eder; %100 gösterilmemeli.
      discovery.discoverAll(
        catalog.stations.take(catalog.totalCount - 1).map((s) => s.id),
      );

      expect(discovery.percent, 99);
      expect(discovery.isComplete, isFalse);
    });

    test('tamamı keşfedilince %100 ve bitmiş sayılır', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(catalog.stations.map((s) => s.id));

      expect(discovery.discoveredCount, catalog.totalCount);
      expect(discovery.percent, 100);
      expect(discovery.progress, 1);
      expect(discovery.isComplete, isTrue);
    });
  });

  group('DiscoveryController — hat', () {
    test('hat sayacı ve oranı', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['taksim', 'sishane']);

      expect(discovery.lineDiscoveredCount('M2'), 2);
      expect(discovery.lineTotalCount('M2'), 15);
      expect(discovery.lineProgress('M2'), closeTo(2 / 15, 1e-9));
      expect(discovery.isLineComplete('M2'), isFalse);
    });

    test('hat tamamlanınca bildirilir, ikinci kez bildirilmez', () {
      final discovery = DiscoveryController(catalog: catalog);
      final ids = catalog.stationsOfLine('M6').map((s) => s.id).toList();

      final result = discovery.discoverAll(ids);
      expect(result.completedLines, contains('M6'));
      expect(discovery.isLineComplete('M6'), isTrue);

      // Aynı hattın durakları yeniden verildiğinde yeni keşif yok, dolayısıyla
      // yeni bir tamamlanma bildirimi de yok.
      final again = discovery.discoverAll(ids);
      expect(again.completedLines, isEmpty);
    });

    test('aktarma durağı iki hattın da sayacına girer', () {
      final discovery = DiscoveryController(catalog: catalog);
      final before = discovery.lineDiscoveredCount('M1A');

      // Levent M2 ve M6'da ortak; M2 üzerinden keşfedilir.
      discovery.discoverAll(<String>['levent']);

      expect(discovery.lineDiscoveredCount('M2'), 1);
      expect(discovery.lineDiscoveredCount('M6'), 1);
      // İlgisiz hat etkilenmez.
      expect(discovery.lineDiscoveredCount('M1A'), before);
    });

    test('aktarma durağı ikinci hattan gelince yeni keşif üretmez', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['levent']);
      final again = discovery.discoverAll(<String>['levent']);

      expect(again.isEmpty, isTrue);
      expect(discovery.discoveredCount, 1);
    });
  });

  group('DiscoveryController — hat sayacı önbelleği', () {
    // Sayaçlar yazma anında güncelleniyor (okuma O(1)). Önbellek ile
    // gerçek küme arasında sapma olursa ekran yanlış sayar ve kimse fark
    // etmez; bu testler ikisini karşılaştırır.
    int recount(DiscoveryController discovery, String lineId) => catalog
        .stationsOfLine(lineId)
        .where((s) => discovery.isDiscovered(s.id))
        .length;

    void expectConsistent(DiscoveryController discovery) {
      for (final line in repository.lines()) {
        expect(
          discovery.lineDiscoveredCount(line.id),
          recount(discovery, line.id),
          reason: '${line.id} sayacı kümeden saptı',
        );
      }
    }

    test('yazımdan sonra sayaç kümeyle aynı', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['taksim', 'levent', 'yenikapi']);
      expectConsistent(discovery);
    });

    test('aktarma durağı sayacı iki hatta birden artırır, bir kez', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['levent', 'levent']);

      expect(discovery.lineDiscoveredCount('M2'), 1);
      expect(discovery.lineDiscoveredCount('M6'), 1);
      expectConsistent(discovery);
    });

    test('kayıttan yüklenince sayaç kurulur', () async {
      final store = await storeWith(<String, Object>{
        'discovered_stations': <String>['yenikapi', 'taksim', 'gecersiz_id'],
      });

      final discovery = DiscoveryController(catalog: catalog, store: store);
      // Yenikapı üç hatta birden hizmet veriyor.
      expect(discovery.lineDiscoveredCount('M1A'), 1);
      expect(discovery.lineDiscoveredCount('M1B'), 1);
      expect(discovery.lineDiscoveredCount('M2'), 2);
      expectConsistent(discovery);
    });

    test('debugReset sayacı da sıfırlar', () {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['taksim']);
      discovery.debugReset();

      expect(discovery.lineDiscoveredCount('M2'), 0);
      expectConsistent(discovery);
    });
  });

  group('DiscoveryController — bildirim', () {
    test('tek karedeki çok sayıda yazım tek bildirim üretir', () async {
      final discovery = DiscoveryController(catalog: catalog);
      var notifications = 0;
      discovery.addListener(() => notifications++);

      discovery
        ..discoverAll(<String>['taksim'])
        ..discoverAll(<String>['osmanbey'])
        ..discoverAll(<String>['sishane']);

      // Bildirim mikro göreve ertelenir: build sırasında dinleyiciyi
      // yeniden çizmeye zorlamamak için.
      expect(notifications, 0);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('yeni keşif yoksa bildirim gitmez', () async {
      final discovery = DiscoveryController(catalog: catalog)
        ..discoverAll(<String>['taksim']);
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      discovery.addListener(() => notifications++);
      discovery.discoverAll(<String>['taksim']);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
    });

    test('dispose sonrası bekleyen bildirim patlamaz', () async {
      final discovery = DiscoveryController(catalog: catalog);
      discovery.discoverAll(<String>['taksim']);
      discovery.dispose();

      await expectLater(Future<void>.delayed(Duration.zero), completes);
    });
  });

  group('DiscoveryController — kalıcılık', () {
    test('keşifler diske yazılır ve geri okunur', () async {
      final store = await storeWith(<String, Object>{});
      DiscoveryController(
        catalog: catalog,
        store: store,
      ).discoverAll(<String>['taksim', 'sishane']);

      // Yeni bir oturum: aynı depodan okunur.
      final restored = DiscoveryController(catalog: catalog, store: store);
      expect(restored.discoveredCount, 2);
      expect(restored.isDiscovered('taksim'), isTrue);
    });

    test('bilinmeyen kimlik yüklemede yok sayılır', () async {
      final store = await storeWith(<String, Object>{
        'discovered_stations': <String>['taksim', 'kaldirilmis_hat_duragi'],
      });

      final discovery = DiscoveryController(catalog: catalog, store: store);
      expect(discovery.discoveredCount, 1);
      expect(discovery.isDiscovered('taksim'), isTrue);
    });

    test('boş kayıt sıfırdan başlatır', () async {
      final store = await storeWith(<String, Object>{
        'discovered_stations': <String>[],
      });

      expect(
        DiscoveryController(catalog: catalog, store: store).discoveredCount,
        0,
      );
    });

    test('flush bekleyen yazımı tamamlar', () async {
      // Oyun sırasındaki yazım beklenmiyor; uygulama arka plana düşerken
      // bu çağrı diske yazmayı garantiler.
      final store = await storeWith(<String, Object>{});
      final discovery = DiscoveryController(catalog: catalog, store: store);
      discovery.discoverAll(<String>['taksim', 'sishane']);

      await discovery.flush();

      expect(store.discoveredStationIds, <String>{'taksim', 'sishane'});
    });

    test('flush keşif yokken de güvenli', () async {
      final store = await storeWith(<String, Object>{});
      await expectLater(
        DiscoveryController(catalog: catalog, store: store).flush(),
        completes,
      );
    });

    test('keşif yazımı başka kayıtlara dokunmaz', () async {
      final store = await storeWith(<String, Object>{
        'sound_enabled': false,
        'best_score_overall': 4200,
      });
      final nameBefore = store.playerName;

      DiscoveryController(
        catalog: catalog,
        store: store,
      ).discoverAll(<String>['taksim']);
      await Future<void>.delayed(Duration.zero);

      expect(store.soundEnabled, isFalse);
      expect(store.playerName, nameBefore);
      expect(store.overallBest, 4200);
    });
  });
}
