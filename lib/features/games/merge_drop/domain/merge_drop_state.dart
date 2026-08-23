import 'package:flutter/foundation.dart';

const int mergeDropMinLevel = 1;
const int mergeDropMaxLevel = 7;
const double mergeDropDangerLine = 0.12;

const List<String> mergeDropLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
];

const List<double> mergeDropRadii = <double>[
  0.045,
  0.055,
  0.067,
  0.080,
  0.094,
  0.110,
  0.128,
];

@immutable
class DropBall {
  const DropBall({
    required this.id,
    required this.level,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });

  final int id;
  final int level;
  final double x;
  final double y;
  final double vx;
  final double vy;

  String get label => mergeDropLabelForLevel(level);
  double get radius => mergeDropRadiusForLevel(level);

  DropBall copyWith({
    int? id,
    int? level,
    double? x,
    double? y,
    double? vx,
    double? vy,
  }) {
    return DropBall(
      id: id ?? this.id,
      level: level ?? this.level,
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
    );
  }
}

String mergeDropLabelForLevel(int level) {
  final index = (level - 1).clamp(0, mergeDropLabels.length - 1);
  return mergeDropLabels[index];
}

double mergeDropRadiusForLevel(int level) {
  final index = (level - 1).clamp(0, mergeDropRadii.length - 1);
  return mergeDropRadii[index];
}
