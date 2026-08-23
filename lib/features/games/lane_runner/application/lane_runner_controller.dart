import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_store.dart';
import '../../blocks/domain/scoring.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_run.dart';
import '../domain/lane_runner_state.dart';

class LaneRunnerController extends ChangeNotifier implements JourneyRun {
  LaneRunnerController({
    required Journey journey,
    required int recordToBeat,
    this.store,
    Random? random,
    this.tick = const Duration(milliseconds: 16),
  }) : _journey = journey,
       _recordToBeat = recordToBeat,
       _random = random ?? Random();

  static const String gameId = 'lane_runner';

  final LocalStore? store;
  final Duration tick;
  final Journey _journey;
  final Random _random;

  Timer? _timer;
  final List<LaneObstacle> _obstacles = <LaneObstacle>[];
  int _nextObstacleId = 0;
  int _score = 0;
  int _passes = 0;
  int _elapsedTicks = 0;
  int _stationsPassed = 0;
  int _recordToBeat;
  int _trainLane = 1;
  double _spawnDistance = 0.0;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  bool _scoreSaved = false;
  bool _passSinceLastStation = false;
  GameStatus _status = GameStatus.ready;

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

  List<LaneObstacle> get obstacles =>
      List<LaneObstacle>.unmodifiable(_obstacles);
  int get trainLane => _trainLane;
  int get passes => _passes;
  int get lineLevel => laneRunnerLineLevelForPasses(_passes);
  String get lineLabel => laneRunnerLineLabelForPasses(_passes);

  @visibleForTesting
  void debugSetObstacles(List<LaneObstacle> obstacles) {
    _obstacles
      ..clear()
      ..addAll(obstacles);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetTrainLane(int lane) {
    _trainLane = lane.clamp(0, laneRunnerLaneCount - 1);
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
    final totalTicks = _journey.estimatedSeconds * _ticksPerSecond;
    if (totalTicks <= 0) return 1;
    return (_elapsedTicks / totalTicks).clamp(0.0, 1.0);
  }

  @override
  double get recordProgress {
    if (isFirstRun) return 0;
    return (_score / _recordToBeat).clamp(0.0, 1.0);
  }

  @override
  int get remainingSeconds {
    final elapsed = _elapsedTicks ~/ _ticksPerSecond;
    final left = _journey.estimatedSeconds - elapsed;
    return left < 0 ? 0 : left;
  }

  int get _ticksPerSecond {
    final millis = tick.inMilliseconds <= 0 ? 16 : tick.inMilliseconds;
    return (AppConstants.playTick.inMilliseconds / millis).round().clamp(
      1,
      120,
    );
  }

  double get _speed => 0.0075 + min(_passes, 35) * 0.00018;

  @override
  void start() {
    if (_status == GameStatus.playing) return;
    _status = GameStatus.playing;
    _startTimer();
    notifyListeners();
  }

  @override
  void pause() {
    if (_status != GameStatus.playing) return;
    _stopTimer();
    _status = GameStatus.paused;
    notifyListeners();
  }

  @override
  void resume() {
    if (_status != GameStatus.paused) return;
    _status = GameStatus.playing;
    _startTimer();
    notifyListeners();
  }

  @override
  void restart() {
    _stopTimer();
    _obstacles.clear();
    _nextObstacleId = 0;
    _score = 0;
    _passes = 0;
    _elapsedTicks = 0;
    _stationsPassed = 0;
    _trainLane = 1;
    _spawnDistance = 0.0;
    _recordBeaten = false;
    _isNewBest = false;
    _scoreSaved = false;
    _passSinceLastStation = false;
    lastStationBonus = 0;
    stationBonusPulse = 0;
    _refreshRecord();
    _status = GameStatus.playing;
    _startTimer();
    notifyListeners();
  }

  @override
  void abandon() {
    _stopTimer();
    if (_status.isFinished) return;
    _status = GameStatus.abandoned;
    notifyListeners();
  }

  void moveLeft() => _setLane(_trainLane - 1);

  void moveRight() => _setLane(_trainLane + 1);

  void _setLane(int lane) {
    if (_status != GameStatus.playing) return;
    _trainLane = lane.clamp(0, laneRunnerLaneCount - 1);
    notifyListeners();
  }

  @visibleForTesting
  void step([int frames = 1]) {
    for (var i = 0; i < frames; i++) {
      if (_status != GameStatus.playing) return;
      _onFrame();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _onFrame());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onFrame() {
    if (_status != GameStatus.playing) return;

    _elapsedTicks++;
    _spawnDistance += _speed;
    if (_obstacles.isEmpty || _spawnDistance >= _nextGap()) {
      _spawnObstacle();
      _spawnDistance = 0.0;
    }

    for (var i = 0; i < _obstacles.length; i++) {
      final obstacle = _obstacles[i];
      final moved = obstacle.copyWith(y: obstacle.y + _speed);
      _obstacles[i] = moved;

      if (!moved.passed && moved.y > laneRunnerTrainY + 0.08) {
        _obstacles[i] = moved.copyWith(passed: true);
        _score += 10;
        _passes++;
        _passSinceLastStation = true;
        _checkRecord();
      }

      if (moved.lane == _trainLane &&
          (moved.y - laneRunnerTrainY).abs() < 0.07) {
        _finish(GameStatus.gameOver);
        return;
      }
    }

    _obstacles.removeWhere((obstacle) => obstacle.y > 1.14);
    _awardStationBonusIfPassed();
    if (remainingSeconds <= 0) {
      _finish(GameStatus.arrived);
      return;
    }
    notifyListeners();
  }

  double _nextGap() {
    final base = 0.34 - min(_passes, 28) * 0.003;
    return (base + _random.nextDouble() * 0.22).clamp(0.24, 0.56);
  }

  void _spawnObstacle() {
    var lane = _random.nextInt(laneRunnerLaneCount);
    if (_obstacles.isNotEmpty && _random.nextBool()) {
      lane =
          (_obstacles.last.lane + 1 + _random.nextInt(2)) % laneRunnerLaneCount;
    }
    _obstacles.add(LaneObstacle(id: _nextObstacleId++, lane: lane, y: -0.12));
  }

  void _awardStationBonusIfPassed() {
    final stops = _journey.stopCount;
    if (stops <= 0) return;
    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;
    final earned = _passSinceLastStation;
    _passSinceLastStation = false;
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
    super.dispose();
  }
}
