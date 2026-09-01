import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/lane_runner_state.dart';

class LaneRunnerController extends JourneyGameController {
  LaneRunnerController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
  }) : _random = random ?? Random(),
       super(gameId: id);

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'lane_runner';

  final Random _random;

  final List<LaneObstacle> _obstacles = <LaneObstacle>[];
  int _nextObstacleId = 0;
  int _passes = 0;
  int _trainLane = 1;
  double _spawnDistance = 0.0;

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

  double get _speed => 0.0075 + min(_passes, 35) * 0.00018;

  @override
  void onRestart() {
    _obstacles.clear();
    _nextObstacleId = 0;
    _passes = 0;
    _trainLane = 1;
    _spawnDistance = 0.0;
  }

  void moveLeft() => _setLane(_trainLane - 1);

  void moveRight() => _setLane(_trainLane + 1);

  void _setLane(int lane) {
    if (status != GameStatus.playing) return;
    _trainLane = lane.clamp(0, laneRunnerLaneCount - 1);
    notifyListeners();
  }

  /// Testte kareyi elle ilerletmek için.
  @visibleForTesting
  void step([int frames = 1]) {
    final dt = tick.inMicroseconds / Duration.microsecondsPerSecond;
    for (var i = 0; i < frames; i++) {
      if (status != GameStatus.playing) return;
      advance(dt);
    }
  }

  @override
  void onTick(double dt) {
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
        addScore(10);
        _passes++;
        markStationProgress();
      }

      if (moved.lane == _trainLane &&
          (moved.y - laneRunnerTrainY).abs() < 0.07) {
        endGame();
        return;
      }
    }

    _obstacles.removeWhere((obstacle) => obstacle.y > 1.14);
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
}
