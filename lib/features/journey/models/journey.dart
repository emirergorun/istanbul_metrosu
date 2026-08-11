import 'package:flutter/foundation.dart';

import 'difficulty_profile.dart';
import 'station.dart';

/// Oyunun tek bir oturumunu tanımlayan yolculuk.
@immutable
class Journey {
  const Journey({
    required this.origin,
    required this.destination,
    required this.estimatedSeconds,
    required this.stopCount,
    required this.difficulty,
    required this.lineId,
  });

  final Station origin;
  final Station destination;

  /// Tahmini yolculuk süresi (saniye). Kesin varış vaadi değildir.
  ///
  /// Kenar süreleri saniye tutulur; dakikaya yalnızca gösterim için yuvarlanır.
  final int estimatedSeconds;

  /// Aradaki durak sayısı (origin hariç, destination dahil).
  final int stopCount;

  final DifficultyProfile difficulty;
  final String lineId;

  /// Kullanıcıya gösterilen yuvarlanmış dakika.
  int get estimatedMinutes => (estimatedSeconds / 60).round();

  @override
  String toString() =>
      'Journey(${origin.name} -> ${destination.name}, $estimatedMinutes dk, '
      '${difficulty.label})';
}
