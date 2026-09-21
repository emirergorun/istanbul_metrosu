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
    super.discovery,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
    super.session,
  }) : _random = random ?? Random(),
       super(gameId: id, maxFrameSeconds: _maxFrameSeconds);

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'lane_runner';

  /// Hızın ve engel doğuşunun ayarlandığı hedef kare süresi.
  ///
  /// Eskiden her `Timer` tetiklenişinde bu kadar süre geçmiş varsayılıyordu;
  /// telefonda zamanlayıcı sapınca akış düzensizleşiyordu. Artık ölçülen
  /// gerçek süre bu değere oranlanıp hız ölçekleniyor: aynı denge (0.0075
  /// vb.) korunur, yalnızca gerçek zamana bağlanır.
  static const double _nominalFrameSeconds = 0.016;

  /// Tek karede en fazla bu kadar süre sayılır; uzun bir donmadan sonra
  /// engelin çarpışma penceresi atlanıp "içinden geçilmesin".
  static const double _maxFrameSeconds = 0.05;

  /// Ray değiştirirken trenin görsel konumu hedefe ne hızda yaklaşsın.
  /// Yüksek değer daha keskin geçiş demek.
  static const double _laneEaseRate = 18.0;

  final Random _random;

  final List<LaneObstacle> _obstacles = <LaneObstacle>[];
  int _nextObstacleId = 0;
  int _passes = 0;
  int _trainLane = 1;

  /// Trenin ekranda çizilen konumu: [_trainLane]'e (hedef ray) doğru
  /// yumuşakça yaklaşır, ışınlanmaz.
  double _trainLaneVisual = 1.0;
  double _spawnDistance = 0.0;

  List<LaneObstacle> get obstacles =>
      List<LaneObstacle>.unmodifiable(_obstacles);
  int get trainLane => _trainLane;

  /// Trenin çizilecek yumuşatılmış ray konumu.
  double get trainLaneVisual => _trainLaneVisual;
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
    _trainLaneVisual = 1.0;
    _spawnDistance = 0.0;
  }

  void moveLeft() => _setLane(_trainLane - 1);

  void moveRight() => _setLane(_trainLane + 1);

  void _setLane(int lane) {
    if (status != GameStatus.playing) return;
    _trainLane = lane.clamp(0, laneRunnerLaneCount - 1);
    notifyListeners();
  }

  /// Testte gerçek zamanlayıcıyı beklemeden nominal kareler ilerletir.
  @visibleForTesting
  void step([int frames = 1]) {
    for (var i = 0; i < frames; i++) {
      if (status != GameStatus.playing) return;
      advance(_nominalFrameSeconds);
    }
  }

  @override
  void onTick(double dt) {
    // `_speed` nominal (16 ms) kare için ayarlı; gerçek dt'ye oranlanır.
    final frameStep = _speed * (dt / _nominalFrameSeconds);

    // Ray değiştirme ışınlanmaz, hedefe doğru yumuşak kayar.
    _trainLaneVisual +=
        (_trainLane - _trainLaneVisual) * (1 - exp(-_laneEaseRate * dt));

    _spawnDistance += frameStep;
    if (_obstacles.isEmpty || _spawnDistance >= _nextGap()) {
      _spawnObstacle();
      _spawnDistance = 0.0;
    }

    for (var i = 0; i < _obstacles.length; i++) {
      final obstacle = _obstacles[i];
      final moved = obstacle.copyWith(y: obstacle.y + frameStep);
      _obstacles[i] = moved;

      if (!moved.passed && moved.y > laneRunnerTrainY + 0.08) {
        _obstacles[i] = moved.copyWith(passed: true);
        _passes++;
        // Geçiş başına sabit 10 puan beceri taşımıyordu; hat seviyesi
        // (`lineLevel`) zaten ekranda ilerliyordu, puan da ona bağlandı.
        addScore(lineLevel);
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
