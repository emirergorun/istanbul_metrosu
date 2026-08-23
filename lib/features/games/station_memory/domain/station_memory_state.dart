import 'package:flutter/foundation.dart';

const int stationMemorySuccessesPerLine = 7;
const int stationMemoryMaxLineLevel = 7;

const List<String> stationMemoryLineLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
];

enum StationMemoryPhase { showing, answering }

@immutable
class StationMemoryRound {
  const StationMemoryRound({
    required this.sequence,
    required this.options,
    required this.phase,
    this.answerIndex = 0,
  });

  final List<String> sequence;
  final List<String> options;
  final StationMemoryPhase phase;
  final int answerIndex;

  StationMemoryRound copyWith({
    List<String>? sequence,
    List<String>? options,
    StationMemoryPhase? phase,
    int? answerIndex,
  }) {
    return StationMemoryRound(
      sequence: sequence ?? this.sequence,
      options: options ?? this.options,
      phase: phase ?? this.phase,
      answerIndex: answerIndex ?? this.answerIndex,
    );
  }
}

String stationMemoryLineLabelForSuccesses(int successes) {
  final index = (successes ~/ stationMemorySuccessesPerLine).clamp(
    0,
    stationMemoryLineLabels.length - 1,
  );
  return stationMemoryLineLabels[index];
}

int stationMemoryLineLevelForSuccesses(int successes) {
  return (successes ~/ stationMemorySuccessesPerLine + 1).clamp(
    1,
    stationMemoryMaxLineLevel,
  );
}
