import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_store.dart';
import '../../blocks/domain/scoring.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_run.dart';
import '../domain/station_memory_state.dart';

class StationMemoryController extends ChangeNotifier implements JourneyRun {
  StationMemoryController({
    required Journey journey,
    required int recordToBeat,
    required List<String> stationNames,
    this.store,
    Random? random,
    this.tick = AppConstants.playTick,
    this.showDuration = const Duration(milliseconds: 1400),
  }) : _journey = journey,
       _recordToBeat = recordToBeat,
       _stationNames = stationNames.length >= 4
           ? List<String>.unmodifiable(stationNames)
           : const <String>['Taksim', 'Levent', 'Şişli', 'Yenikapı'],
       _random = random ?? Random() {
    _round = _createRound();
  }

  static const String gameId = 'station_memory';

  final LocalStore? store;
  final Duration tick;
  final Duration showDuration;
  final Journey _journey;
  final Random _random;
  final List<String> _stationNames;

  Timer? _timer;
  Timer? _showTimer;
  late StationMemoryRound _round;
  int _score = 0;
  int _successes = 0;
  int _elapsedSeconds = 0;
  int _stationsPassed = 0;
  int _recordToBeat;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  bool _scoreSaved = false;
  bool _successSinceLastStation = false;
  GameStatus _status = GameStatus.ready;

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

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

  @override
  Journey get journey => _journey;

  @override
  GameStatus get status => _status;

  @override
  int get score => _score;

  @override
  int get recordToBeat => _recordToBeat;

  @override
  bool get recordBeaten => _recordBeaten;

  @override
  bool get isFirstRun => _recordToBeat <= 0;

  @override
  bool get isNewBest => _isNewBest;

  @override
  double get progress {
    final total = _journey.estimatedSeconds;
    if (total <= 0) return 1;
    return (_elapsedSeconds / total).clamp(0.0, 1.0);
  }

  @override
  double get recordProgress {
    if (isFirstRun) return 0;
    return (_score / _recordToBeat).clamp(0.0, 1.0);
  }

  @override
  int get remainingSeconds {
    final left = _journey.estimatedSeconds - _elapsedSeconds;
    return left < 0 ? 0 : left;
  }

  @override
  void start() {
    if (_status == GameStatus.playing) return;
    _status = GameStatus.playing;
    _startTimer();
    _scheduleShowFinish();
    notifyListeners();
  }

  @override
  void pause() {
    if (_status != GameStatus.playing) return;
    _stopTimer();
    _showTimer?.cancel();
    _status = GameStatus.paused;
    notifyListeners();
  }

  @override
  void resume() {
    if (_status != GameStatus.paused) return;
    _status = GameStatus.playing;
    _startTimer();
    if (_round.phase == StationMemoryPhase.showing) _scheduleShowFinish();
    notifyListeners();
  }

  @override
  void restart() {
    _stopTimer();
    _showTimer?.cancel();
    _score = 0;
    _successes = 0;
    _elapsedSeconds = 0;
    _stationsPassed = 0;
    _recordBeaten = false;
    _isNewBest = false;
    _scoreSaved = false;
    _successSinceLastStation = false;
    lastStationBonus = 0;
    stationBonusPulse = 0;
    _refreshRecord();
    _round = _createRound();
    _status = GameStatus.playing;
    _startTimer();
    _scheduleShowFinish();
    notifyListeners();
  }

  @override
  void abandon() {
    _stopTimer();
    _showTimer?.cancel();
    if (_status.isFinished) return;
    _status = GameStatus.abandoned;
    notifyListeners();
  }

  bool choose(String stationName) {
    if (_status != GameStatus.playing ||
        _round.phase != StationMemoryPhase.answering) {
      return false;
    }

    final expected = _round.sequence[_round.answerIndex];
    if (stationName != expected) {
      _finish(GameStatus.gameOver);
      return false;
    }

    final nextIndex = _round.answerIndex + 1;
    if (nextIndex < _round.sequence.length) {
      _round = _round.copyWith(answerIndex: nextIndex);
      notifyListeners();
      return true;
    }

    _successes++;
    _score += _round.sequence.length * 5;
    _successSinceLastStation = true;
    _checkRecord();
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
    if (_status != GameStatus.playing) return;
    _showTimer = Timer(showDuration, _finishShowing);
  }

  void _finishShowing() {
    if (_status != GameStatus.playing ||
        _round.phase != StationMemoryPhase.showing) {
      return;
    }
    _round = _round.copyWith(phase: StationMemoryPhase.answering);
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick() {
    if (_status != GameStatus.playing) return;
    _elapsedSeconds++;
    _awardStationBonusIfPassed();
    if (remainingSeconds <= 0) _finish(GameStatus.arrived);
    notifyListeners();
  }

  void _awardStationBonusIfPassed() {
    final stops = _journey.stopCount;
    if (stops <= 0) return;
    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;
    final earned = _successSinceLastStation;
    _successSinceLastStation = false;
    _stationsPassed = passed;
    if (earned) {
      _score += ScoreRules.stationBonus;
      lastStationBonus = ScoreRules.stationBonus;
      stationBonusPulse++;
      _checkRecord();
    }
  }

  bool _checkRecord() {
    if (_recordBeaten || isFirstRun) return false;
    if (_score <= _recordToBeat) return false;
    _recordBeaten = true;
    return true;
  }

  void _refreshRecord() {
    final stored = store?.bestScoreForGameRoute(
      gameId: gameId,
      originId: _journey.origin.id,
      destinationId: _journey.destination.id,
    );
    if (stored != null && stored > _recordToBeat) _recordToBeat = stored;
  }

  void _finish(GameStatus status) {
    _stopTimer();
    _showTimer?.cancel();
    _status = status;
    notifyListeners();
    unawaited(_persistScore());
  }

  Future<void> _persistScore() async {
    final target = store;
    if (target == null || _scoreSaved) return;
    _isNewBest = await target.submitGameRouteScore(
      gameId: gameId,
      originId: _journey.origin.id,
      destinationId: _journey.destination.id,
      score: _score,
    );
    _scoreSaved = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    _showTimer?.cancel();
    super.dispose();
  }
}
