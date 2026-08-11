import '../../../data/metro/metro_repository.dart';
import '../models/journey.dart';
import '../models/station.dart';
import 'difficulty_mapper.dart';

/// Rota hesaplamasının başarısız olma nedenleri.
enum RouteError {
  /// Aynı istasyon seçilemez.
  sameStation,

  /// İstasyon datada yok.
  unknownStation,

  /// İki istasyon farklı hatlarda. MVP'de aktarma yok.
  differentLines,

  /// Süre 0 hesaplandı — datada hata var demektir.
  zeroDuration,
}

/// Rota hesaplama sonucu.
class RouteResult {
  const RouteResult.success(this.journey) : error = null;
  const RouteResult.failure(this.error) : journey = null;

  final Journey? journey;
  final RouteError? error;

  bool get isValid => journey != null;

  String? get message => switch (error) {
    RouteError.sameStation => 'Biniş ve iniş durağı aynı olamaz.',
    RouteError.unknownStation => 'İstasyon bulunamadı.',
    RouteError.differentLines =>
      'Şimdilik aktarmasız yolculuk oynanabiliyor; iki durak da aynı hatta olmalı.',
    RouteError.zeroDuration => 'Yolculuk süresi hesaplanamadı.',
    null => null,
  };
}

/// Biniş/iniş durağından tahmini süre ve zorluk üretir.
///
/// MVP: **aktarmasız**. İki durak aynı hatta olmalıdır; süre aradaki
/// kenarların toplamıdır ve yön fark etmez.
/// TODO(PROD): Aktarma kenarları + Dijkstra ile çok hatlı rota.
class RouteService {
  const RouteService(this._repository);

  final MetroRepository _repository;

  RouteResult estimate(String originId, String destinationId) {
    if (originId == destinationId) {
      return const RouteResult.failure(RouteError.sameStation);
    }

    final origin = _repository.stationById(originId);
    final destination = _repository.stationById(destinationId);
    if (origin == null || destination == null) {
      return const RouteResult.failure(RouteError.unknownStation);
    }
    if (origin.lineId != destination.lineId) {
      return const RouteResult.failure(RouteError.differentLines);
    }

    final seconds = _secondsBetween(origin, destination);
    if (seconds == null) {
      return const RouteResult.failure(RouteError.unknownStation);
    }
    if (seconds <= 0) {
      return const RouteResult.failure(RouteError.zeroDuration);
    }

    final journey = Journey(
      origin: origin,
      destination: destination,
      estimatedSeconds: seconds,
      stopCount: (destination.order - origin.order).abs(),
      difficulty: difficultyFor((seconds / 60).round()),
      lineId: origin.lineId,
    );
    return RouteResult.success(journey);
  }

  /// İki istasyon arasındaki toplam saniye. Yönden bağımsızdır.
  int? _secondsBetween(Station origin, Station destination) {
    final lineStations = _repository.stationsOfLine(origin.lineId);
    if (lineStations.isEmpty) return null;

    final lower = origin.order < destination.order ? origin : destination;
    final upper = origin.order < destination.order ? destination : origin;
    final edges = _repository.edges();

    var total = 0;
    for (var order = lower.order; order < upper.order; order++) {
      if (order + 1 >= lineStations.length) return null;
      final from = lineStations[order];
      final to = lineStations[order + 1];

      final match = edges.where((e) => e.connects(from.id, to.id));
      if (match.isEmpty) return null;
      total += match.first.seconds;
    }
    return total;
  }
}
