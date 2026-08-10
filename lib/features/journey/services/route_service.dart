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

  /// İki istasyon arasında rota bulunamadı (çok hatlı ağda mümkün).
  noRoute,

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

  /// Kullanıcıya gösterilecek hata metni.
  String? get message => switch (error) {
    RouteError.sameStation => 'Biniş ve iniş durağı aynı olamaz.',
    RouteError.unknownStation => 'İstasyon bulunamadı.',
    RouteError.noRoute => 'Bu iki durak arasında rota bulunamadı.',
    RouteError.zeroDuration => 'Yolculuk süresi hesaplanamadı.',
    null => null,
  };
}

/// Biniş/iniş durağından tahmini süre ve zorluk üretir.
///
/// MVP: tek hat. İki istasyonun sıra farkındaki edge sürelerini toplar,
/// yön fark etmez (ters yön de desteklenir).
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

    // MVP tek hat varsayımı.
    // TODO(PROD): Çok hatlı ağda Dijkstra/A* + aktarma ağırlığı kullanılacak.
    if (origin.lineId != destination.lineId) {
      return const RouteResult.failure(RouteError.noRoute);
    }

    final minutes = _minutesBetween(origin, destination);
    if (minutes == null) return const RouteResult.failure(RouteError.noRoute);
    if (minutes <= 0) {
      return const RouteResult.failure(RouteError.zeroDuration);
    }

    final journey = Journey(
      origin: origin,
      destination: destination,
      estimatedMinutes: minutes,
      stopCount: (destination.order - origin.order).abs(),
      difficulty: difficultyFor(minutes),
      lineId: origin.lineId,
    );
    return RouteResult.success(journey);
  }

  /// İki istasyon arasındaki toplam dakika. Yönden bağımsızdır.
  int? _minutesBetween(Station origin, Station destination) {
    final lower = origin.order < destination.order ? origin : destination;
    final upper = origin.order < destination.order ? destination : origin;

    final byId = <String, Station>{
      for (final s in _repository.stations()) s.id: s,
    };
    final edges = _repository.edges();

    var total = 0;
    for (var order = lower.order; order < upper.order; order++) {
      final from = _stationAtOrder(byId.values, lower.lineId, order);
      final to = _stationAtOrder(byId.values, lower.lineId, order + 1);
      if (from == null || to == null) return null;

      final match = edges.where((e) => e.connects(from.id, to.id));
      if (match.isEmpty) return null;
      total += match.first.minutes;
    }
    return total;
  }

  Station? _stationAtOrder(
    Iterable<Station> stations,
    String lineId,
    int order,
  ) {
    for (final station in stations) {
      if (station.lineId == lineId && station.order == order) return station;
    }
    return null;
  }
}
