import 'package:flutter/foundation.dart';

const int railFlightGatesPerLine = 5;
const int railFlightMaxLineLevel = 10;
const double railFlightTrainX = 0.24;
const double railFlightTrainRadius = 0.045;
const double railFlightObstacleWidth = 0.13;

/// Gerçek ağda M10 yok (M9'dan sonra M11 gelir); bkz. README "Bilinen
/// Sınırlar".
const List<String> railFlightLineLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
  'M8',
  'M9',
  'M11',
];

@immutable
class RailFlightConfig {
  const RailFlightConfig({
    required this.gravity,
    required this.flapVelocity,
    required this.speed,
    required this.gapHeight,
    required this.spawnDistance,
  });

  factory RailFlightConfig.forMinutes(int minutes) {
    if (minutes <= 5) {
      return const RailFlightConfig(
        gravity: 1.35,
        flapVelocity: -0.46,
        speed: 0.25,
        gapHeight: 0.38,
        spawnDistance: 0.62,
      );
    }
    if (minutes <= 15) {
      return const RailFlightConfig(
        gravity: 1.42,
        flapVelocity: -0.48,
        speed: 0.29,
        gapHeight: 0.34,
        spawnDistance: 0.58,
      );
    }
    return const RailFlightConfig(
      gravity: 1.48,
      flapVelocity: -0.50,
      speed: 0.32,
      gapHeight: 0.31,
      spawnDistance: 0.54,
    );
  }

  final double gravity;
  final double flapVelocity;
  final double speed;
  final double gapHeight;
  final double spawnDistance;
}

@immutable
class RailObstacle {
  const RailObstacle({
    required this.x,
    required this.gapCenter,
    required this.gapHeight,
    this.passed = false,
  });

  final double x;
  final double gapCenter;
  final double gapHeight;
  final bool passed;

  RailObstacle copyWith({
    double? x,
    double? gapCenter,
    double? gapHeight,
    bool? passed,
  }) {
    return RailObstacle(
      x: x ?? this.x,
      gapCenter: gapCenter ?? this.gapCenter,
      gapHeight: gapHeight ?? this.gapHeight,
      passed: passed ?? this.passed,
    );
  }
}

String railFlightLineLabelForPasses(int gatesPassed) {
  final index = (gatesPassed ~/ railFlightGatesPerLine).clamp(
    0,
    railFlightLineLabels.length - 1,
  );
  return railFlightLineLabels[index];
}

int railFlightLineLevelForPasses(int gatesPassed) {
  return (gatesPassed ~/ railFlightGatesPerLine + 1).clamp(
    1,
    railFlightMaxLineLevel,
  );
}
