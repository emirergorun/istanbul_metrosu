import 'package:flutter/foundation.dart';

import '../../../journey/models/difficulty_profile.dart';

const int metroMergeMaxRank = 9;
const List<String> metroMergeLineLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
  'M8',
  'M9',
];

enum MetroMoveDirection { left, up, right, down }

@immutable
class MetroTile {
  const MetroTile({required this.colorIndex, required this.rank});

  final int colorIndex;
  final int rank;

  int get lineIndex => (rank - 1).clamp(0, metroMergeLineLabels.length - 1);
  String get lineLabel => metroMergeLineLabels[lineIndex];
  String get rankLabel => rank < metroMergeMaxRank
      ? 'Sıradaki ${metroMergeLineLabels[rank]}'
      : 'Final hat';
}

@immutable
class MetroMergeConfig {
  const MetroMergeConfig({required this.gridSize, required this.colorCount});

  factory MetroMergeConfig.fromDifficulty(DifficultyProfile difficulty) {
    return switch (difficulty.id) {
      'mini' || 'short' => const MetroMergeConfig(gridSize: 4, colorCount: 2),
      'standard' => const MetroMergeConfig(gridSize: 5, colorCount: 3),
      _ => const MetroMergeConfig(gridSize: 6, colorCount: 4),
    };
  }

  final int gridSize;
  final int colorCount;
}

@immutable
class MetroMoveOutcome {
  const MetroMoveOutcome({
    required this.accepted,
    this.gainedPoints = 0,
    this.clearedRows = const <int>[],
    this.clearedColumns = const <int>[],
    this.merges = 0,
    this.terminalClears = 0,
    this.beatRecord = false,
  });

  const MetroMoveOutcome.rejected() : this(accepted: false);

  final bool accepted;
  final int gainedPoints;
  final List<int> clearedRows;
  final List<int> clearedColumns;
  final int merges;
  final int terminalClears;
  final bool beatRecord;

  int get linesCleared => clearedRows.length + clearedColumns.length;
  bool get didClear => linesCleared > 0;
}
