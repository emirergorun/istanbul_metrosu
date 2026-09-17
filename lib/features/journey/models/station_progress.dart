import 'package:flutter/foundation.dart';

import 'journey.dart';
import 'station.dart';

/// Yolculuğun **durak düzeyindeki** hâli.
///
/// İlerleme çubuğu tek bir 0..1 sayısıydı: "yolculuğun %37'sindesin".
/// Oyuncu metroda bunu böyle düşünmez — "Aksaray'a yaklaşıyorum" der.
/// Bu sınıf aynı sayıyı durak diline çevirir.
///
/// Konum ölçülmez, ilerlemeden türetilir: GPS yok, konum izni yok.
@immutable
class StationProgress {
  const StationProgress({
    required this.departed,
    required this.approaching,
    required this.stationsPassed,
    required this.stopCount,
    required this.segmentProgress,
  });

  /// Trenin en son ayrıldığı durak. Yolculuk başındayken biniş durağı.
  final Station departed;

  /// Yaklaşılan durak. Varışta `null`.
  final Station? approaching;

  /// Geçilen durak sayısı.
  final int stationsPassed;

  /// Yolculuktaki toplam durak arası sayısı.
  final int stopCount;

  /// İki durak arasındaki ilerleme, 0.0 – 1.0.
  final double segmentProgress;

  /// Tren son durağa vardı mı?
  bool get hasArrived => approaching == null;

  /// Yaklaşılan durak yolculuğun son durağı mı?
  bool get isFinalSegment => stationsPassed >= stopCount - 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StationProgress &&
          other.departed == departed &&
          other.approaching == approaching &&
          other.stationsPassed == stationsPassed &&
          other.stopCount == stopCount &&
          other.segmentProgress == segmentProgress);

  @override
  int get hashCode => Object.hash(
    departed,
    approaching,
    stationsPassed,
    stopCount,
    segmentProgress,
  );

  @override
  String toString() =>
      'StationProgress(${departed.name} -> ${approaching?.name ?? "varış"}, '
      '$stationsPassed/$stopCount durak, '
      '%${(segmentProgress * 100).round()})';
}

/// Bir durağa varıldığı **an**.
///
/// Olay olarak taşınır, durum olarak değil: arayüz bunu bir kez görür ve
/// kısa bir kutlama oynatır. Oyun durmaz.
@immutable
class StationReachedEvent {
  const StationReachedEvent({
    required this.previous,
    required this.reached,
    required this.next,
    required this.stationsPassed,
    required this.stopCount,
    required this.bonusAwarded,
  });

  /// Az önce ayrılınan durak.
  final Station previous;

  /// Varılan durak.
  final Station reached;

  /// Sıradaki durak. Varılan durak son durak ise `null`.
  final Station? next;

  final int stationsPassed;
  final int stopCount;

  /// Bu durakta kazanılan bonus. 0 ise durak bonussuz geçildi.
  final int bonusAwarded;

  /// Varılan durak yolculuğun son durağı mı?
  bool get isDestination => next == null;

  @override
  String toString() =>
      'StationReachedEvent(${reached.name}, $stationsPassed/$stopCount, '
      '+$bonusAwarded)';
}

/// Yolculuk ilerlemesini durak diline çevirir.
///
/// [lineStations] hattın **sıraya dizilmiş** istasyonlarıdır
/// (`MetroRepository.stationsOfLine`). Yön yolculuktan okunur: iniş durağı
/// biniş durağından önce geliyorsa tren geriye doğru gider.
///
/// Durak sayısı 0 ise (veri hatası) `null` döner.
StationProgress? stationProgressFor({
  required Journey journey,
  required List<Station> lineStations,
  required double progress,
}) {
  final stops = journey.stopCount;
  if (stops <= 0 || lineStations.isEmpty) return null;

  final direction = journey.destination.order > journey.origin.order ? 1 : -1;
  final exact = (progress.clamp(0.0, 1.0)) * stops;
  final passed = exact.floor().clamp(0, stops);

  Station? at(int index) {
    final order = journey.origin.order + direction * index;
    for (final station in lineStations) {
      if (station.order == order) return station;
    }
    return null;
  }

  final departed = at(passed) ?? journey.origin;
  final approaching = passed >= stops ? null : at(passed + 1);

  return StationProgress(
    departed: departed,
    approaching: approaching,
    stationsPassed: passed,
    stopCount: stops,
    segmentProgress: passed >= stops ? 1 : exact - passed,
  );
}
