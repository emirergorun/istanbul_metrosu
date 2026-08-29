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

  /// Serbest düşüş ivmesi. Kütleden bağımsızdır (Galileo) — büyük top küçük
  /// topla aynı hızda düşer; "ağırlık" hissi kütleye göre çarpışma
  /// tepkisinden gelir, yerçekiminden değil.
  static const double _gravity = 2.2;

  /// Serbest düşüşte hız burada kesilir. Sınır olmasa hızlı bir top, tek bir
  /// karede altındaki topun içinden geçip altına düşebilir (tünelleme);
  /// bu sınır tek bir alt-adımda kat edilecek mesafeyi en küçük top çapının
  /// altında tutar (2.7 × 0.016/4 ≈ 0.011, en küçük top çapı 0.09'un çok
  /// altında — güvenli pay var).
  static const double _maxFallSpeed = 2.7;

  /// Fizik her tikte bu kadar alt-adıma bölünür. Adım küçüldükçe hem
  /// tünelleme riski azalır hem de çarpışma çözümü daha kararlı yığınlar
  /// üretir.
  static const int _substeps = 4;

  /// Bir alt-adımda çakışmaları gidermek için kaç kez tekrar denenir.
  /// Tek geçiş, üst üste birkaç top varken çakışmaları tam gideremez ve
  /// yığın titrer/dağılır; birden çok geçiş (Gauss–Seidel gevşemesi) yığının
  /// oturmasını sağlar.
  static const int _solverIterations = 4;

  /// Duvara çarpan topun ne kadar geri sektiğini belirler.
  static const double _wallRestitution = 0.28;

  /// Zeminde ve top-top temaslarında yanal hız her alt-adımda bu oranda
  /// azalır — sürtünme olmadan yığınlar yavaşça yanlara doğru "sürünür".
  static const double _friction = 0.82;

  /// Top-top çarpışmalarında sekme payı. Sıfırsa toplar birbirine değince
  /// tüm yaklaşma hızını anında yutar ve "yapışmış" gibi durur; gerçek
  /// toplar gibi hafifçe sekip ayrılsınlar diye küçük bir pay bırakılır.
  /// Zemin sekmez (ayrı fizik, aşağıda) — yalnızca top-top teması için.
  /// Yalnızca `_restitutionThreshold` üzerindeki gerçek çarpmalarda
  /// uygulanır (aşağıya bakın).
  static const double _ballRestitution = 0.38;

  /// Bu hızın altındaki yaklaşmalarda sekme uygulanmaz, çarpışma tam
  /// sönümlenir. Eşik olmadan, yerçekiminin her alt-adımda oturmuş bir
  /// yığını yeniden hafifçe bastırması → sekme → tekrar bastırma... diye
  /// sonsuz bir mikro-titreşim döngüsü oluşuyordu; bu da tam olarak
  /// "yapışma/titreme" hissinin köküydü. Yalnızca gerçek, sert çarpmalar
  /// (bu eşiğin üzerindeki yaklaşma hızları) sekiyor.
  static const double _restitutionThreshold = 0.06;

  /// Bu kadarın altındaki iç içe geçmeler düzeltilmez (kayan nokta
  /// gürültüsü payı) — aksi hâlde toplar hiçbir zaman tam durmayıp
  /// mikroskobik ölçekte sürekli düzeltilip yeniden çakışabilir.
  static const double _positionSlop = 0.0015;

  /// Tehlike çizgisine değen bir top kaybettirmeden önce ne kadar orada
  /// kalmalı. Yalnızca oturmuş (`landed`) toplar için sayılır, bu yüzden
  /// çok kısa tutulabilir — asıl amaç anlık bir sekmeyi haksız kayıp
  /// saymamak, yeni bırakılan topun düşmesini beklemek değil.
  static const double _overflowGraceSeconds = 0.22;

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

    // Tek büyük adım yerine küçük alt-adımlar: hızlı düşen bir top, altındaki
    // topu tek bir karede "atlayıp" altına geçemesin diye (tünelleme).
    final subDt = dt / _substeps;
    for (var s = 0; s < _substeps; s++) {
      _integrate(subDt);
      for (var i = 0; i < _solverIterations; i++) {
        if (_mergeFirstOverlap()) continue;
        _resolveCollisions();
      }
    }

    _awardStationBonusIfPassed();

    if (_isOverflowing()) {
      _overflowSeconds += dt;
      if (_overflowSeconds > _overflowGraceSeconds) {
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
    final updated = <DropBall>[];
    for (final ball in _balls) {
      final radius = ball.radius;
      final onFloor = ball.y + radius >= worldHeight - 1e-6;
      // Zeminde dururken sürtünme, havadayken yalnızca hafif hava direnci.
      var vx = ball.vx * (onFloor ? _friction : 0.995);
      var vy = (ball.vy + _gravity * dt).clamp(-_maxFallSpeed, _maxFallSpeed);
      var x = ball.x + vx * dt;
      var y = ball.y + vy * dt;

      if (x - radius < 0) {
        x = radius;
        vx = vx.abs() * _wallRestitution;
      } else if (x + radius > worldWidth) {
        x = worldWidth - radius;
        vx = -vx.abs() * _wallRestitution;
      }

      var landed = ball.landed;
      if (y + radius > worldHeight) {
        y = worldHeight - radius;
        if (vy > 0) vy = 0;
        if (vx.abs() < 1e-4) vx = 0;
        landed = true;
      }

      updated.add(ball.copyWith(x: x, y: y, vx: vx, vy: vy, landed: landed));
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
        if (distance > a.radius + b.radius) continue;

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
          landed: true,
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

  /// Çakışan her top çiftini aynı anda hem konum hem hız düzeyinde çözer.
  ///
  /// 1. **Konum düzeltmesi (penetrasyon ayrıştırma)**: toplar, kütleleriyle
  ///    ters orantılı ölçüde ayrılır — büyük/ağır top az, küçük/hafif top
  ///    çok hareket eder. Eşit bölüşüm (eski davranış) büyük bir topun
  ///    küçük bir topla aynı miktarda itilmesine, yani "ağırlıksız" bir
  ///    hisse yol açıyordu.
  /// 2. **Hız düzeltmesi (impuls)**: yalnızca gerçekten yaklaşan çiftlerde
  ///    (`vn < 0`) uygulanır; kütleye göre dağıtılan bir impuls hem normal
  ///    yöndeki hızı çözer hem de gerçek, sert çarpmalarda hafif bir sekme
  ///    bırakır (`_ballRestitution`, yalnızca `_restitutionThreshold`
  ///    üzerindeki yaklaşma hızlarında). Eşik olmadan yerçekiminin her
  ///    alt-adımda oturmuş toplara verdiği minik yaklaşma hızı bile
  ///    sekmeye dönüşüp sonsuz bir titreşim/yapışma hissi yaratıyordu.
  ///    Teğet yöndeki hız sürtünmeyle söner.
  ///
  /// Alt-adım başına birden çok kez çağrılır (Gauss–Seidel gevşemesi):
  /// çok sayıda top üst üsteyken tek geçiş çakışmayı tam gideremez.
  void _resolveCollisions() {
    final balls = List<DropBall>.of(_balls);
    for (var i = 0; i < balls.length; i++) {
      for (var j = i + 1; j < balls.length; j++) {
        final a = balls[i];
        final b = balls[j];
        final minDistance = a.radius + b.radius;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance >= minDistance) continue;

        final safeDistance = distance <= 1e-6 ? 1e-6 : distance;
        final nx = dx / safeDistance;
        final ny = dy / safeDistance;
        final overlap = minDistance - safeDistance;

        final invMassA = 1 / a.mass;
        final invMassB = 1 / b.mass;
        final invMassSum = invMassA + invMassB;

        // Kayan nokta gürültüsü kadar çakışmayı düzeltmeye çalışma —
        // aksi hâlde toplar hiç tam durmayıp mikroskobik ölçekte titreşir.
        final penetration = max(overlap - _positionSlop, 0.0);
        final correctionA = penetration * (invMassA / invMassSum);
        final correctionB = penetration * (invMassB / invMassSum);

        var newA = a.copyWith(
          x: (a.x - nx * correctionA).clamp(a.radius, worldWidth - a.radius),
          y: (a.y - ny * correctionA).clamp(a.radius, worldHeight - a.radius),
          landed: true,
        );
        var newB = b.copyWith(
          x: (b.x + nx * correctionB).clamp(b.radius, worldWidth - b.radius),
          y: (b.y + ny * correctionB).clamp(b.radius, worldHeight - b.radius),
          landed: true,
        );

        final relVx = newB.vx - newA.vx;
        final relVy = newB.vy - newA.vy;
        final closingSpeed = relVx * nx + relVy * ny;
        if (closingSpeed < 0) {
          // Yalnızca gerçek, sert çarpmalarda sek; oturmuş bir yığını
          // yerçekiminin verdiği minik yaklaşma hızı sekmeye dönüşmesin.
          final restitution = closingSpeed < -_restitutionThreshold
              ? _ballRestitution
              : 0.0;
          final impulse = -(1 + restitution) * closingSpeed / invMassSum;
          newA = newA.copyWith(
            vx: newA.vx - impulse * nx * invMassA,
            vy: newA.vy - impulse * ny * invMassA,
          );
          newB = newB.copyWith(
            vx: newB.vx + impulse * nx * invMassB,
            vy: newB.vy + impulse * ny * invMassB,
          );
        }

        final tx = -ny;
        final ty = nx;
        final normalA = newA.vx * nx + newA.vy * ny;
        final tangentA = (newA.vx * tx + newA.vy * ty) * _friction;
        final normalB = newB.vx * nx + newB.vy * ny;
        final tangentB = (newB.vx * tx + newB.vy * ty) * _friction;

        balls[i] = newA.copyWith(
          vx: normalA * nx + tangentA * tx,
          vy: normalA * ny + tangentA * ty,
        );
        balls[j] = newB.copyWith(
          vx: normalB * nx + tangentB * tx,
          vy: normalB * ny + tangentB * ty,
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

  /// Yalnızca oturmuş toplar sayılır — yeni bırakılan top zaten tehlike
  /// çizgisinin üstünde doğuyor, o henüz hiçbir şeye değmeden anında
  /// kaybettirmemesi gerekiyor.
  bool _isOverflowing() {
    return _balls.any(
      (ball) => ball.landed && ball.y - ball.radius < mergeDropDangerLine,
    );
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
