import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/core/utils/formatters.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kalan süre, yolculuğun başında rota ekranındaki süreyle aynı', () {
    // Regresyon: rota ekranı dakikayı yuvarlıyor, oyun içi sayaç yukarı
    // yuvarlıyordu. 868 sn'lik Yenikapı → Otogar "~14 dk" / "~15 dk kaldı".
    final metro = MetroFixture.load();
    final routes = RouteService(metro);
    var checked = 0;
    for (final line in metro.lines()) {
      final stations = metro.stations().where((s) => s.lineId == line.id);
      final first = stations.first;
      for (final other in stations.skip(1)) {
        final journey = routes.estimate(first.id, other.id).journey;
        if (journey == null || journey.estimatedSeconds < 60) continue;
        expect(
          Formatters.remaining(journey.estimatedSeconds),
          Formatters.approxMinutes(journey.estimatedMinutes),
          reason: '${first.name} → ${other.name}',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(50));
  });

  group('bestRecordForRoute', () {
    Future<LocalStore> storeWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final store = LocalStore();
      await store.init();
      return store;
    }

    test('rekor yoksa null', () async {
      final store = await storeWith(<String, Object>{});
      expect(store.bestRecordForRoute('m2_taksim', 'm2_levent'), isNull);
    });

    test('oyunlar arasından en yükseğini, oyunuyla birlikte döner', () async {
      final store = await storeWith(<String, Object>{
        'best_route_m2_levent__m2_taksim': 120,
        'best_game_route_rail_flight|m2_levent__m2_taksim': 300,
        'best_game_route_metro_merge|m2_levent__m2_taksim': 90,
        // Başka rota: karışmamalı.
        'best_game_route_rail_flight|m2_osmanbey__m2_taksim': 999,
      });

      final record = store.bestRecordForRoute('m2_taksim', 'm2_levent')!;
      expect(record.score, 300);
      expect(record.gameId, 'rail_flight');

      // Yön fark etmez.
      expect(store.bestRecordForRoute('m2_levent', 'm2_taksim')!.score, 300);
    });

    test('eski rota kaydı Blok Metro olarak döner', () async {
      final store = await storeWith(<String, Object>{
        'best_route_m2_levent__m2_taksim': 120,
      });

      final record = store.bestRecordForRoute('m2_taksim', 'm2_levent')!;
      expect(record.score, 120);
      expect(record.gameId, LocalStore.legacyRouteGameId);
    });
  });
}
