import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_store.dart';
import '../../blocks/domain/scoring.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_run.dart';
import '../domain/rail_flight_state.dart';

class RailFlightController extends ChangeNotifier implements JourneyRun {
  RailFlightController({
    required Journey journey,
    required int recordToBeat,
    this.store,
    Random? random,
    this.tick = const Duration(milliseconds: 16),
  }) : _journey = journey,
       _recordToBeat = recordToBeat,
       _random = random ?? Random(),
       config = RailFlightConfig.forMinutes(journey.estimatedMinutes) {
    _resetFlight();
  }

  static const String gameId = 'rail_flight';

  final LocalStore? store;
  final Duration tick;
  final Journey _journey;
  final Random _random;
  final RailFlightConfig config;

  Timer? _timer;
  double _routeElapsedSeconds = 0;
  double _trainY = 0.5;
  double _velocity = 0;
  int _score = 0;
  int _gatesPassed = 0;
  int _stationsPassed = 0;
  int _recordToBeat;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  bool _scoreSaved = false;
  bool _passedGateSinceLastStation = false;
  GameStatus _status = GameStatus.ready;
  List<RailObstacle> _obstacles = const <RailObstacle>[];

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

  double get trainY => _trainY;
  double get velocity => _velocity;
  int get gatesPassed => _gatesPassed;
  int get lineLevel => railFlightLineLevelForPasses(_gatesPassed);
  String get lineLabel => railFlightLineLabelForPasses(_gatesPassed);
  List<RailObstacle> get obstacles =>
      List<RailObstacle>.unmodifiable(_obstacles);

  @visibleForTesting
  void debugSetFlight({
    double? trainY,
    double? velocity,
    List<RailObstacle>? obstacles,
  }) {
    _trainY = trainY ?? _trainY;
    _velocity = velocity ?? _velocity;
    _obstacles = obstacles ?? _obstacles;
    notifyListeners();
  }

  @visibleForTesting
  void debugStep(double seconds) {
    _advance(seconds);
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
    return (_routeElapsedSeconds / total).clamp(0.0, 1.0);
  }

  @override
  double get recordProgress {
    if (isFirstRun) return 0;
    return (_score / _recordToBeat).clamp(0.0, 1.0);
  }

  @override
  int get remainingSeconds {
    final left = _journey.estimatedSeconds - _routeElapsedSeconds.ceil();
    return left < 0 ? 0 : left;
  }

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
    _score = 0;
    _gatesPassed = 0;
    _stationsPassed = 0;
    _routeElapsedSeconds = 0;
    _recordBeaten = false;
    _isNewBest = false;
    _scoreSaved = false;
    _passedGateSinceLastStation = false;
    lastStationBonus = 0;
    stationBonusPulse = 0;
    _refreshRecord();
    _resetFlight();
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

  void flap() {
    if (_status != GameStatus.playing) return;
    _velocity = config.flapVelocity;
    notifyListeners();
  }

  void _resetFlight() {
    _trainY = 0.5;
    _velocity = 0;
    _obstacles = <RailObstacle>[_newObstacle(1.05)];
  }

  RailObstacle _newObstacle(double x) {
    final gapHeight = (config.gapHeight + (_random.nextDouble() - 0.5) * 0.12)
        .clamp(0.25, 0.43);
    return RailObstacle(
      x: x,
      gapCenter: 0.28 + _random.nextDouble() * 0.44,
      gapHeight: gapHeight,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      _advance(tick.inMicroseconds / Duration.microsecondsPerSecond);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _advance(double dt) {
    if (_status != GameStatus.playing) return;

    _routeElapsedSeconds += dt;
    _velocity += config.gravity * dt;
    _trainY += _velocity * dt;

    _obstacles = <RailObstacle>[
      for (final obstacle in _obstacles)
        obstacle.copyWith(x: obstacle.x - config.speed * dt),
    ];
    _scorePassedGates();
    _trimAndSpawnObstacles();
    _awardStationBonusIfPassed();

    if (_isColliding()) {
      _finish(GameStatus.gameOver);
      return;
    }
    if (remainingSeconds <= 0) {
      _finish(GameStatus.arrived);
    }
  }

  void _scorePassedGates() {
    final updated = <RailObstacle>[];
    for (final obstacle in _obstacles) {
      if (!obstacle.passed &&
          obstacle.x + railFlightObstacleWidth < railFlightTrainX) {
        _gatesPassed++;
        _score += 1;
        _passedGateSinceLastStation = true;
        _checkRecord();
        updated.add(obstacle.copyWith(passed: true));
      } else {
        updated.add(obstacle);
      }
    }
    _obstacles = updated;
  }

  void _trimAndSpawnObstacles() {
    _obstacles = _obstacles
        .where((obstacle) => obstacle.x + railFlightObstacleWidth > -0.1)
        .toList();
    final rightMost = _obstacles.isEmpty
        ? 0.0
        : _obstacles.map((obstacle) => obstacle.x).reduce(max);
    if (rightMost < 1 - config.spawnDistance) {
      _obstacles = <RailObstacle>[
        ..._obstacles,
        _newObstacle(rightMost + config.spawnDistance),
      ];
    }
  }

  bool _isColliding() {
    if (_trainY - railFlightTrainRadius <= 0) return true;
    if (_trainY + railFlightTrainRadius >= 1) return true;

    for (final obstacle in _obstacles) {
      final overlapsX =
          railFlightTrainX + railFlightTrainRadius > obstacle.x &&
          railFlightTrainX - railFlightTrainRadius <
              obstacle.x + railFlightObstacleWidth;
      if (!overlapsX) continue;

      final gapTop = obstacle.gapCenter - obstacle.gapHeight / 2;
      final gapBottom = obstacle.gapCenter + obstacle.gapHeight / 2;
      if (_trainY - railFlightTrainRadius < gapTop ||
          _trainY + railFlightTrainRadius > gapBottom) {
        return true;
      }
    }
    return false;
  }

  void _awardStationBonusIfPassed() {
    final stops = _journey.stopCount;
    if (stops <= 0) return;

    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;

    final earned = _passedGateSinceLastStation;
    _passedGateSinceLastStation = false;
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
