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

  /// Zorluk **yolculuğun uzunluğuna değil, geçilen kapı sayısına** bağlı.
  ///
  /// Eskiden uzun rotada oyun ilk kapıdan itibaren en zor ayarla
  /// başlıyordu. Rota rekoru oyunlar arasında ortaklaşınca bu bir
  /// adaletsizliğe döndü: 52 dakikalık bir yolculukta Ray Uçuşu dakikada
  /// 43 puan verirken diğer oyunlar 130-150 veriyordu (ölçüldü,
  /// `test/balance/points_per_minute_test.dart`). Oyuncu uzun rotada bu
  /// oyunu seçtiği için cezalandırılıyordu.
  ///
  /// Artık diğer oyunlarla aynı mantık: herkes kolaydan başlar, oyun
  /// oyuncu ilerledikçe zorlaşır. [hardenAfterGates] kapıda en zor ayara
  /// ulaşılır — hat merdiveninin (M1…M11) tepesiyle aynı yer.
  factory RailFlightConfig.forGates(int gates) {
    final t = (gates / hardenAfterGates).clamp(0.0, 1.0);
    double lerp(double easy, double hard) => easy + (hard - easy) * t;
    return RailFlightConfig(
      gravity: lerp(1.35, 1.48),
      flapVelocity: lerp(-0.46, -0.50),
      speed: lerp(0.25, 0.32),
      gapHeight: lerp(0.38, 0.31),
      spawnDistance: lerp(0.62, 0.54),
    );
  }

  /// Kaç kapıdan sonra en zor ayara ulaşılır.
  static const int hardenAfterGates =
      railFlightGatesPerLine * railFlightMaxLineLevel;

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
