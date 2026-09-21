import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final repository = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(repository);
  final routes = RouteService(repository);

  group('DiscoveryCatalog', () {
    test('fiziksel duraklar tekilleştirilir', () {
      // Veri 161 hat-durak kaydı taşıyor; fiziksel durak sayısı daha az,
      // çünkü aktarma durakları birden çok hatta geçiyor.
      expect(repository.stations().length, 161);
      expect(catalog.totalCount, 143);
    });

    test('toplam sayı veriden gelir, sabit yazılı değildir', () {
      final unique = repository
          .stations()
          .map((s) => s.canonicalId)
          .toSet()
          .length;
      expect(catalog.totalCount, unique);
    });

    test('aktarma durağı tüm hatlarını taşır', () {
      final yenikapi = catalog.stationById('yenikapi');
      expect(yenikapi, isNotNull);
      expect(yenikapi!.isInterchange, isTrue);
      expect(yenikapi.lineIds, containsAll(<String>['M1A', 'M1B', 'M2']));
    });

    test('aktarma durağı her hattın toplamına sayılır', () {
      expect(
        catalog.stationsOfLine('M2').map((s) => s.id),
        contains('yenikapi'),
      );
      expect(
        catalog.stationsOfLine('M1A').map((s) => s.id),
        contains('yenikapi'),
      );
    });

    test('hat toplamı o hattın durak sayısıdır', () {
      for (final line in repository.lines()) {
        expect(
          catalog.lineTotalCount(line.id),
          repository.stationsOfLine(line.id).length,
          reason: line.id,
        );
      }
    });

    test('bilinmeyen kimlik null döner', () {
      expect(catalog.stationById('boyle_bir_durak_yok'), isNull);
    });

    test('rota sırası biniş durağından iniş durağına gider', () {
      final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
      final ids = catalog.routeStationIds(journey);

      expect(ids.first, 'taksim');
      expect(ids.last, 'levent');
      expect(ids.length, journey.stopCount + 1);
    });

    test('ters rota ters sırayla gelir', () {
      final forward = catalog.routeStationIds(
        routes.estimate('m2_taksim', 'm2_levent').journey!,
      );
      final backward = catalog.routeStationIds(
        routes.estimate('m2_levent', 'm2_taksim').journey!,
      );

      expect(backward, forward.reversed.toList());
    });

    test('iki duraklık rota iki kimlik döner', () {
      final journey = routes.estimate('m2_taksim', 'm2_osmanbey').journey!;
      final ids = catalog.routeStationIds(journey);
      expect(ids.length, 2);
    });
  });
}
