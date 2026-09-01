import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/station_memory_state.dart';

class StationMemoryController extends JourneyGameController {
  StationMemoryController({
    required super.journey,
    required super.recordToBeat,
    required List<String> stationNames,
    super.store,
    Random? random,
    super.tick = AppConstants.playTick,
    this.showDuration,
  }) : _stationNames = stationNames.length >= 4
           ? List<String>.unmodifiable(stationNames)
           : const <String>['Taksim', 'Levent', 'Şişli', 'Yenikapı'],
       _random = random ?? Random(),
       super(gameId: id) {
    _round = _createRound();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'station_memory';

  /// Ezberleme süresini sabitler. Yalnızca test için; normalde `null` bırakılır
  /// ve süre dizi uzunluğuna göre hesaplanır.
  final Duration? showDuration;

  /// Ezberleme süresi = taban + durak başına süre.
  ///
  /// Sabit süre yanlıştı: dizi 3 duraktan 7'ye çıkarken süre 1400 ms'de
  /// kalıyordu. İlk turda oyuncu hazır olduktan sonra bekliyor, son turlarda
  /// yedi durağı okumaya vakit bulamıyordu.
  static const Duration showBase = Duration(milliseconds: 200);
  static const Duration showPerStation = Duration(milliseconds: 320);

  /// Bu turun ezberleme süresi.
  Duration get currentShowDuration =>
      showDuration ?? showBase + showPerStation * _round.sequence.length;
  final Random _random;
  final List<String> _stationNames;

  Timer? _showTimer;
  late StationMemoryRound _round;
  int _successes = 0;

  StationMemoryRound get round => _round;
  int get successes => _successes;
  int get lineLevel => stationMemoryLineLevelForSuccesses(_successes);
  String get lineLabel => stationMemoryLineLabelForSuccesses(_successes);
  bool get isShowing => _round.phase == StationMemoryPhase.showing;

  @visibleForTesting
  void debugFinishShowing() => _finishShowing();

  @visibleForTesting
  void debugSetSuccesses(int value) {
    _successes = value;
    notifyListeners();
  }

  // --- Yolculuk motorunun kancaları ---

  @override
  void onRestart() {
    _showTimer?.cancel();
    _successes = 0;
    _round = _createRound();
    _scheduleShowFinish();
  }

  /// Ezberleme aşamasının kendi sayacı da yolculukla birlikte durur.
  @override
  void onPause() => _showTimer?.cancel();

  @override
  void onResume() {
    if (isShowing) _scheduleShowFinish();
  }

  @override
  void onAbandon() => _showTimer?.cancel();

  @override
  void onFinish(GameStatus status) => _showTimer?.cancel();

  bool choose(String stationName) {
    if (status != GameStatus.playing ||
        _round.phase != StationMemoryPhase.answering) {
      return false;
    }

    final expected = _round.sequence[_round.answerIndex];
    if (stationName != expected) {
      endGame();
      return false;
    }

    final nextIndex = _round.answerIndex + 1;
    if (nextIndex < _round.sequence.length) {
      _round = _round.copyWith(answerIndex: nextIndex);
      notifyListeners();
      return true;
    }

    _successes++;
    addScore(_round.sequence.length * 5);
    markStationProgress();
    _round = _createRound();
    _scheduleShowFinish();
    notifyListeners();
    return true;
  }

  StationMemoryRound _createRound() {
    final sequenceLength = min(
      3 + _successes ~/ 3,
      min(7, _stationNames.length),
    );
    final shuffled = List<String>.of(_stationNames)..shuffle(_random);
    final sequence = shuffled.take(sequenceLength).toList();
    final optionCount = min(_stationNames.length, max(6, sequenceLength + 2));
    final options = <String>{...sequence};
    for (final station in shuffled) {
      options.add(station);
      if (options.length >= optionCount) break;
    }
    return StationMemoryRound(
      sequence: List<String>.unmodifiable(sequence),
      options: List<String>.unmodifiable(options.toList()..shuffle(_random)),
      phase: StationMemoryPhase.showing,
    );
  }

  void _scheduleShowFinish() {
    _showTimer?.cancel();
    if (status != GameStatus.playing) return;
    _showTimer = Timer(currentShowDuration, _finishShowing);
  }

  void _finishShowing() {
    if (status != GameStatus.playing ||
        _round.phase != StationMemoryPhase.showing) {
      return;
    }
    _round = _round.copyWith(phase: StationMemoryPhase.answering);
    notifyListeners();
  }
}
