import 'package:flutter/foundation.dart';

const int laneRunnerLaneCount = 3;
const int laneRunnerPassesPerLine = 7;
const int laneRunnerMaxLineLevel = 7;
const double laneRunnerTrainY = 0.78;

const List<String> laneRunnerLineLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
];

@immutable
class LaneObstacle {
  const LaneObstacle({
    required this.id,
    required this.lane,
    required this.y,
    this.passed = false,
  });

  final int id;
  final int lane;
  final double y;
  final bool passed;

  LaneObstacle copyWith({int? id, int? lane, double? y, bool? passed}) {
    return LaneObstacle(
      id: id ?? this.id,
      lane: lane ?? this.lane,
      y: y ?? this.y,
      passed: passed ?? this.passed,
    );
  }
}

String laneRunnerLineLabelForPasses(int passes) {
  final index = (passes ~/ laneRunnerPassesPerLine).clamp(
    0,
    laneRunnerLineLabels.length - 1,
  );
  return laneRunnerLineLabels[index];
}

int laneRunnerLineLevelForPasses(int passes) {
  return (passes ~/ laneRunnerPassesPerLine + 1).clamp(
    1,
    laneRunnerMaxLineLevel,
  );
}
