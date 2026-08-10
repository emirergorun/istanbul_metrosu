import 'package:flutter/foundation.dart';

import 'difficulty_profile.dart';
import 'station.dart';

/// Oyunun tek bir oturumunu tanımlayan yolculuk.
@immutable
class Journey {
  const Journey({
    required this.origin,
    required this.destination,
    required this.estimatedMinutes,
    required this.stopCount,
    required this.difficulty,
    required this.lineId,
  });

  final Station origin;
  final Station destination;

  /// Tahmini yolculuk süresi (dakika). Kesin varış vaadi değildir.
  final int estimatedMinutes;

  /// Aradaki durak sayısı (origin hariç, destination dahil).
  final int stopCount;

  final DifficultyProfile difficulty;
  final String lineId;

  int get estimatedSeconds => estimatedMinutes * 60;

  @override
  String toString() =>
      'Journey(${origin.name} -> ${destination.name}, $estimatedMinutes dk, '
      '${difficulty.label})';
}
