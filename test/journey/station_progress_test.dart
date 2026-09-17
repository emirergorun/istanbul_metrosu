import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/models/station_progress.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  StationProgress? progressAt(String origin, String destination, double t) {
    final journey = routes.estimate(origin, destination).journey!;
    return stationProgressFor(
      journey: journey,
      lineStations: metro.stationsOfLine(journey.lineId),
      progress: t,
    );
  }

  group('ileri yön', () {
    test('yolculuk başında biniş durağından ayrılmış sayılır', () {
      final progress = progressAt('m2_yenikapi', 'm2_haciosman', 0)!;

      expect(progress.departed.id, 'm2_yenikapi');
      expect(progress.stationsPassed, 0);
      expect(progress.segmentProgress, 0);
      expect(progress.hasArrived, isFalse);
    });

    test('yaklaşılan durak bir sonraki istasyondur', () {
      final progress = progressAt('m2_yenikapi', 'm2_haciosman', 0)!;
      final stations = metro.stationsOfLine('M2');
      final origin = stations.firstWhere((s) => s.id == 'm2_yenikapi');

      expect(progress.approaching!.order, origin.order + 1);
    });

    test('durak geçilince ayrılınan durak ilerler', () {
      final journey = routes.estimate('m2_yenikapi', 'm2_haciosman').journey!;
      // Tam bir durak arası geçildi.
      final progress = stationProgressFor(
        journey: journey,
        lineStations: metro.stationsOfLine('M2'),
        progress: 1 / journey.stopCount,
      )!;

      expect(progress.stationsPassed, 1);
      expect(progress.departed.id, isNot('m2_yenikapi'));
      expect(progress.segmentProgress, closeTo(0, 0.0001));
    });

    test('durak arası ilerleme 0 ile 1 arasında döner', () {
      final journey = routes.estimate('m2_yenikapi', 'm2_haciosman').journey!;
      final progress = stationProgressFor(
        journey: journey,
        lineStations: metro.stationsOfLine('M2'),
        progress: 1.5 / journey.stopCount,
      )!;

      expect(progress.stationsPassed, 1);
      expect(progress.segmentProgress, closeTo(0.5, 0.0001));
    });

    test('varışta yaklaşılan durak kalmaz', () {
      final progress = progressAt('m2_yenikapi', 'm2_haciosman', 1)!;

      expect(progress.hasArrived, isTrue);
      expect(progress.approaching, isNull);
      expect(progress.departed.id, 'm2_haciosman');
      expect(progress.stationsPassed, progress.stopCount);
    });

    test('son durak arası işaretlenir', () {
      final journey = routes.estimate('m2_yenikapi', 'm2_haciosman').journey!;
      final progress = stationProgressFor(
        journey: journey,
        lineStations: metro.stationsOfLine('M2'),
        progress: (journey.stopCount - 1) / journey.stopCount,
      )!;

      expect(progress.isFinalSegment, isTrue);
      expect(progress.approaching!.id, 'm2_haciosman');
    });
  });

  group('geri yön', () {
    test('iniş durağı önce geliyorsa tren geriye gider', () {
      final journey = routes.estimate('m2_haciosman', 'm2_yenikapi').journey!;
      final progress = stationProgressFor(
        journey: journey,
        lineStations: metro.stationsOfLine('M2'),
        progress: 1 / journey.stopCount,
      )!;

      expect(progress.departed.order, journey.origin.order - 1);
      expect(progress.approaching!.order, journey.origin.order - 2);
    });

    test('geri yönde de doğru durağa varılır', () {
      final progress = progressAt('m2_haciosman', 'm2_yenikapi', 1)!;
      expect(progress.departed.id, 'm2_yenikapi');
    });
  });

  group('art arda durak geçişi', () {
    test('her durak arası sırayla geçilir', () {
      final journey = routes.estimate('m2_yenikapi', 'm2_haciosman').journey!;
      final stations = metro.stationsOfLine('M2');

      final seen = <String>[];
      for (var stop = 0; stop <= journey.stopCount; stop++) {
        final progress = stationProgressFor(
          journey: journey,
          lineStations: stations,
          progress: stop / journey.stopCount,
        )!;
        seen.add(progress.departed.name);
      }

      // Biniş durağından iniş durağına, hiçbir durak atlanmadan.
      expect(seen.first, journey.origin.name);
      expect(seen.last, journey.destination.name);
      expect(seen.length, journey.stopCount + 1);
      expect(seen.toSet().length, seen.length, reason: 'durak tekrarı yok');
    });

    test('geçilen durak sayısı hiç azalmaz', () {
      final journey = routes.estimate('m4_kadikoy', 'm4_kozyatagi').journey!;
      final stations = metro.stationsOfLine('M4');

      var previous = -1;
      for (var i = 0; i <= 100; i++) {
        final progress = stationProgressFor(
          journey: journey,
          lineStations: stations,
          progress: i / 100,
        )!;
        expect(progress.stationsPassed, greaterThanOrEqualTo(previous));
        previous = progress.stationsPassed;
      }
      expect(previous, journey.stopCount);
    });
  });

  group('sınırlar', () {
    test('ilerleme aralık dışındaysa kırpılır', () {
      final low = progressAt('m2_taksim', 'm2_levent', -5)!;
      final high = progressAt('m2_taksim', 'm2_levent', 9)!;

      expect(low.stationsPassed, 0);
      expect(high.hasArrived, isTrue);
    });

    test('hat istasyonu listesi boşsa null döner', () {
      final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
      expect(
        stationProgressFor(
          journey: journey,
          lineStations: const [],
          progress: 0.5,
        ),
        isNull,
      );
    });
  });
}
