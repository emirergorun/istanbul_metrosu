import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/storage/local_store.dart';
import '../../blocks/domain/scoring.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_run.dart';
import '../domain/merge_drop_state.dart';

class MergeDropController extends ChangeNotifier implements JourneyRun {
  MergeDropController({
    required Journey journey,
    required int recordToBeat,
    this.store,
    Random? random,
    this.tick = const Duration(milliseconds: 16),
  }) : _journey = journey,
       _recordToBeat = recordToBeat,
       _random = random ?? Random() {
    _currentLevel = _randomLevel();
  }

  static const String gameId = 'merge_drop';
  static const double worldWidth = 1;
  static const double worldHeight = 1;

  final LocalStore? store;
  final Duration tick;
  final Journey _journey;
  final Random _random;

  Timer? _timer;
  double _routeElapsedSeconds = 0;
  double _aimX = 0.5;
  double _dropCooldown = 0;
  double _overflowSeconds = 0;
  int _nextId = 1;
  int _currentLevel = mergeDropMinLevel;
  int _score = 0;
  int _merges = 0;
  int _maxLevel = mergeDropMinLevel;
  int _stationsPassed = 0;
  int _recordToBeat;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  bool _scoreSaved = false;
  bool _mergedSinceLastStation = false;
  GameStatus _status = GameStatus.ready;
  List<DropBall> _balls = const <DropBall>[];

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

  double get aimX => _aimX;
  int get currentLevel => _currentLevel;
  String get currentLabel => mergeDropLabelForLevel(_currentLevel);
  int get merges => _merges;
  int get maxLevel => _maxLevel;
  String get maxLabel => mergeDropLabelForLevel(_maxLevel);
  bool get canDrop => _status == GameStatus.playing && _dropCooldown <= 0;
  List<DropBall> get balls => List<DropBall>.unmodifiable(_balls);

  @visibleForTesting
  void debugSetBalls(List<DropBall> balls) {
    _balls = List<DropBall>.of(balls);
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
    final left = _journey.estimatedSeconds - _routeElapsedSeconds.floor();
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
    _routeElapsedSeconds = 0;
    _aimX = 0.5;
    _dropCooldown = 0;
    _overflowSeconds = 0;
    _nextId = 1;
    _score = 0;
    _merges = 0;
    _maxLevel = mergeDropMinLevel;
    _stationsPassed = 0;
    _recordBeaten = false;
    _isNewBest = false;
    _scoreSaved = false;
    _mergedSinceLastStation = false;
    lastStationBonus = 0;
    stationBonusPulse = 0;
    _balls = const <DropBall>[];
    _currentLevel = _randomLevel();
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

  void moveAim(double x) {
    final radius = mergeDropRadiusForLevel(_currentLevel);
    _aimX = x.clamp(radius, worldWidth - radius);
    notifyListeners();
  }

  bool drop() {
    if (!canDrop) return false;
    final radius = mergeDropRadiusForLevel(_currentLevel);
    _balls = <DropBall>[
      ..._balls,
      DropBall(
        id: _nextId++,
        level: _currentLevel,
        x: _aimX.clamp(radius, worldWidth - radius),
        y: radius + 0.015,
      ),
    ];
    _currentLevel = _randomLevel();
    _dropCooldown = 0.32;
    notifyListeners();
    return true;
  }

  int _randomLevel() => _random.nextInt(3) + mergeDropMinLevel;

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
    _dropCooldown = max(0, _dropCooldown - dt);
    _integrate(dt);
    for (var i = 0; i < 3; i++) {
      if (_mergeFirstOverlap()) continue;
      _separateOverlaps();
    }
    _awardStationBonusIfPassed();

    if (_isOverflowing()) {
      _overflowSeconds += dt;
      if (_overflowSeconds > 1.0) {
        _finish(GameStatus.gameOver);
        return;
      }
    } else {
      _overflowSeconds = 0;
    }

    if (remainingSeconds <= 0) {
      _finish(GameStatus.arrived);
    }
  }

  void _integrate(double dt) {
    const gravity = 1.9;
    final updated = <DropBall>[];
    for (final ball in _balls) {
      final radius = ball.radius;
      var vx = ball.vx * 0.94;
      var vy = ball.vy + gravity * dt;
      var x = ball.x + vx * dt;
      var y = ball.y + vy * dt;

      if (x - radius < 0) {
        x = radius;
        vx = vx.abs() * 0.32;
      } else if (x + radius > worldWidth) {
        x = worldWidth - radius;
        vx = -vx.abs() * 0.32;
      }

      if (y + radius > worldHeight) {
        y = worldHeight - radius;
        vy = 0;
        if (vx.abs() < 0.012) vx = 0;
      }

      updated.add(ball.copyWith(x: x, y: y, vx: vx, vy: vy));
    }
    _balls = updated;
  }

  bool _mergeFirstOverlap() {
    for (var i = 0; i < _balls.length; i++) {
      for (var j = i + 1; j < _balls.length; j++) {
        final a = _balls[i];
        final b = _balls[j];
        if (a.level != b.level || a.level >= mergeDropMaxLevel) continue;
        final distance = _distance(a, b);
        if (distance > (a.radius + b.radius) * 1.02) continue;

        final merged = DropBall(
          id: _nextId++,
          level: a.level + 1,
          x: ((a.x + b.x) / 2).clamp(
            mergeDropRadiusForLevel(a.level + 1),
            worldWidth - mergeDropRadiusForLevel(a.level + 1),
          ),
          y: ((a.y + b.y) / 2).clamp(
            mergeDropRadiusForLevel(a.level + 1),
            worldHeight - mergeDropRadiusForLevel(a.level + 1),
          ),
          vy: min(a.vy, b.vy) * 0.25,
        );
        _balls = <DropBall>[
          for (var k = 0; k < _balls.length; k++)
            if (k != i && k != j) _balls[k],
          merged,
        ];
        _merges++;
        _maxLevel = max(_maxLevel, merged.level);
        _score += merged.level * 10;
        _mergedSinceLastStation = true;
        _checkRecord();
        return true;
      }
    }
    return false;
  }

  void _separateOverlaps() {
    final balls = List<DropBall>.of(_balls);
    for (var i = 0; i < balls.length; i++) {
      for (var j = i + 1; j < balls.length; j++) {
        final a = balls[i];
        final b = balls[j];
        final minDistance = a.radius + b.radius;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance <= 0 || distance >= minDistance) continue;

        final overlap = (minDistance - distance) / 2;
        final nx = dx / distance;
        final ny = dy / distance;
        balls[i] = a.copyWith(
          x: (a.x - nx * overlap).clamp(a.radius, worldWidth - a.radius),
          y: (a.y - ny * overlap).clamp(a.radius, worldHeight - a.radius),
          vx: a.vx - nx * 0.004,
          vy: a.vy - ny * 0.004,
        );
        balls[j] = b.copyWith(
          x: (b.x + nx * overlap).clamp(b.radius, worldWidth - b.radius),
          y: (b.y + ny * overlap).clamp(b.radius, worldHeight - b.radius),
          vx: b.vx + nx * 0.004,
          vy: b.vy + ny * 0.004,
        );
      }
    }
    _balls = balls;
  }

  double _distance(DropBall a, DropBall b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  bool _isOverflowing() {
    return _balls.any((ball) => ball.y - ball.radius < mergeDropDangerLine);
  }

  void _awardStationBonusIfPassed() {
    final stops = _journey.stopCount;
    if (stops <= 0) return;

    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;

    final earned = _mergedSinceLastStation;
    _mergedSinceLastStation = false;
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
