import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/telemetry/analytics.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';

import '../helpers/metro_fixture.dart';

/// Kaydedilen olayları biriktiren sahte ölçüm.
class _Recorder implements Analytics {
  final List<({AnalyticsEvent event, Map<String, String> params})> entries =
      <({AnalyticsEvent event, Map<String, String> params})>[];

  @override
  void log(AnalyticsEvent event, {Map<String, String> params = const {}}) {
    entries.add((event: event, params: Map<String, String>.of(params)));
  }

  Iterable<Map<String, String>> paramsOf(AnalyticsEvent event) =>
      entries.where((e) => e.event == event).map((e) => e.params);

  int countOf(AnalyticsEvent event) => paramsOf(event).length;
}

void main() {
  final catalog = DiscoveryCatalog.fromRepository(MetroFixture.load());

  ({DiscoveryController discovery, _Recorder log}) build() {
    final log = _Recorder();
    return (
      discovery: DiscoveryController(catalog: catalog, analytics: log),
      log: log,
    );
  }

  group('keşif ölçümü', () {
    test('her yeni durak için bir olay', () {
      final built = build();
      built.discovery.discoverAll(<String>[
        'taksim',
        'osmanbey',
      ], gameId: 'blocks');

      expect(built.log.countOf(AnalyticsEvent.stationDiscovered), 2);
    });

    test('zaten bilinen durak olay üretmez', () {
      final built = build();
      built.discovery.discoverAll(<String>['taksim']);
      built.discovery.discoverAll(<String>['taksim']);

      expect(built.log.countOf(AnalyticsEvent.stationDiscovered), 1);
    });

    test('olay durak kimliği taşımaz, hat ve oyun taşır', () {
      // Ölçüm sözleşmesi: 143 serbest durak adı panoyu sayılamaz hâle
      // getirir. "Hangi oyun hangi hattı keşfettiriyor" ise on satırda
      // okunur.
      final built = build();
      built.discovery.discoverAll(<String>['taksim'], gameId: 'metro_quiz');

      final params = built.log
          .paramsOf(AnalyticsEvent.stationDiscovered)
          .single;
      expect(params['line_id'], 'M2');
      expect(params['game_id'], 'metro_quiz');
      expect(params.containsKey('station_id'), isFalse);
      expect(params.values, isNot(contains('Taksim')));
    });

    test('aktarma durağı hatlarını birlikte taşır', () {
      final built = build();
      built.discovery.discoverAll(<String>['yenikapi']);

      final params = built.log
          .paramsOf(AnalyticsEvent.stationDiscovered)
          .single;
      expect(params['line_id'], 'M1A/M1B/M2');
    });

    test('oyun kimliği verilmezse alan hiç yazılmaz', () {
      final built = build();
      built.discovery.discoverAll(<String>['taksim']);

      final params = built.log
          .paramsOf(AnalyticsEvent.stationDiscovered)
          .single;
      expect(params.containsKey('game_id'), isFalse);
    });

    test('hat tamamlanınca bir kez line_completed', () {
      final built = build();
      final m6 = catalog.stationsOfLine('M6').map((s) => s.id).toList();

      built.discovery.discoverAll(m6, gameId: 'blocks');
      expect(built.log.countOf(AnalyticsEvent.lineCompleted), 1);
      expect(
        built.log.paramsOf(AnalyticsEvent.lineCompleted).single['line_id'],
        'M6',
      );

      // Aynı duraklar tekrar verilince yeni keşif yok, yeni olay da yok.
      built.discovery.discoverAll(m6, gameId: 'blocks');
      expect(built.log.countOf(AnalyticsEvent.lineCompleted), 1);
    });

    test('hat tamamlanmadan line_completed atılmaz', () {
      final built = build();
      final m6 = catalog.stationsOfLine('M6').map((s) => s.id).toList();
      built.discovery.discoverAll(m6.take(3));

      expect(built.log.countOf(AnalyticsEvent.lineCompleted), 0);
    });
  });
}
