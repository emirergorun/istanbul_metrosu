import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/rail_flight_state.dart';

class RailFlightController extends JourneyGameController {
  RailFlightController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    super.discovery,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
  }) : _random = random ?? Random(),
       config = RailFlightConfig.forMinutes(journey.estimatedMinutes),
       super(gameId: id, maxFrameSeconds: _maxFrameSeconds) {
    _resetFlight();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'rail_flight';

  /// Tek bir fizik adımında en fazla bu kadar saniye sayılır.
  ///
  /// Telefonda `Timer` düzenli gelmeyebilir (arka plan kısıtlaması, çöp
  /// toplama, kısa donma). Ölçülen süreyi olduğu gibi fiziğe vermek treni
  /// tek karede engelin içinden ışınlayabilir ya da haksız bir ölüme yol
  /// açabilir; bu sınır sıçramayı nominal tikin ~3 katına hapseder.
  static const double _maxFrameSeconds = 0.05;

  final Random _random;
  final RailFlightConfig config;

  double _trainY = 0.5;
  double _velocity = 0;
  int _gatesPassed = 0;
  List<RailObstacle> _obstacles = const <RailObstacle>[];
  double _pendingSpawnGap = 0;

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

  /// Testte uçuşu elle ilerletmek için.
  @visibleForTesting
  void debugStep(double seconds) {
    advance(seconds);
    notifyListeners();
  }

  @override
  void onRestart() {
    _gatesPassed = 0;
    _resetFlight();
  }

  void flap() {
    if (status != GameStatus.playing) return;
    _velocity = config.flapVelocity;
    notifyListeners();
  }

  void _resetFlight() {
    _trainY = 0.5;
    _velocity = 0;
    _pendingSpawnGap = _randomSpawnGap();
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

  /// Engeller arası mesafe: bazıları kısa, bazıları uzun olsun diye
  /// `config.spawnDistance` etrafında ±45% rastgele oynatılır. Zorluk
  /// seviyesinin ortalama temposunu korur, sadece ritmi düzensizleştirir.
  double _randomSpawnGap() {
    final factor = 0.55 + _random.nextDouble() * 1.05;
    return config.spawnDistance * factor;
  }

  @override
  void onTick(double dt) {
    _velocity += config.gravity * dt;
    _trainY += _velocity * dt;

    _obstacles = <RailObstacle>[
      for (final obstacle in _obstacles)
        obstacle.copyWith(x: obstacle.x - config.speed * dt),
    ];
    _scorePassedGates();
    _trimAndSpawnObstacles();

    if (_isColliding()) endGame();
  }

  void _scorePassedGates() {
    final updated = <RailObstacle>[];
    for (final obstacle in _obstacles) {
      if (!obstacle.passed &&
          obstacle.x + railFlightObstacleWidth < railFlightTrainX) {
        _gatesPassed++;
        addScore(1);
        markStationProgress();
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
    if (rightMost < 1 - _pendingSpawnGap) {
      _obstacles = <RailObstacle>[
        ..._obstacles,
        _newObstacle(rightMost + _pendingSpawnGap),
      ];
      _pendingSpawnGap = _randomSpawnGap();
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
}
