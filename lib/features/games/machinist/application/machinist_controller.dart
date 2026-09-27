import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/machinist_rules.dart';

/// Duruşun sonucu — ekran şerit ve ses için okur.
@immutable
class StopResult {
  const StopResult({
    required this.station,
    required this.error,
    this.grade,
    this.points = 0,
    this.passengers = 0,
    this.streak = 0,
  });

  final String station;

  /// Durak işaretine göre sapma (m): eksi erken, artı geç.
  final double error;

  /// `null`: durak kaçırıldı.
  final StopGrade? grade;
  final int points;
  final int passengers;
  final int streak;

  bool get missed => grade == null;
}

/// Makinist: gaz ve fren pedallarıyla metroyu sür, durak işaretinde dur.
///
/// Tren hep ileri gider (geri vites yok). Durak işaretinin ±6 m'sinde
/// duran tren kapılarını açar, yolcu alır ve puan yazar; işareti 14 m
/// geçen tren durağı kaçırır. Üç kaçırılan durakta oyun biter.
class MachinistController extends JourneyGameController {
  MachinistController({
    required super.journey,
    required super.recordToBeat,
    required List<String> stationNames,
    super.store,
    super.discovery,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
    super.session,
  }) : _random = random ?? Random(),
       _names = stationNames.isEmpty ? _fallbackNames : stationNames,
       super(gameId: id, maxFrameSeconds: 0.05) {
    _buildLine();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'machinist';

  static const List<String> _fallbackNames = <String>[
    'Taksim',
    'Şişhane',
    'Haliç',
    'Vezneciler',
    'Yenikapı',
  ];

  final Random _random;

  /// Sırayla uğranacak istasyon adları; hat biterse geri döner.
  final List<String> _names;

  final List<MachinistStation> _stations = <MachinistStation>[];

  double _position = 0;
  double _speed = 0;
  bool _throttleHeld = false;
  bool _brakeHeld = false;
  double _throttle = 0;
  double _brake = 0;

  /// Kapı döngüsünde geçen süre; `null` ise tren istasyonda beklemiyor.
  double? _dwell;
  MachinistStation? _dwellStation;

  int _targetIndex = 1;
  int _served = 0;
  int _misses = 0;
  int _streak = 0;
  int _passengersTotal = 0;
  double _elapsed = 0;

  /// Son fizik adımının duvar saati; çizim konumunu ileri kestirmek için.
  DateTime? _lastTickAt;

  StopResult? _lastResult;
  int _resultPulse = 0;
  int _hintPulse = 0;

  // ---------------------------------------------------------------- okuma

  List<MachinistStation> get stations =>
      List<MachinistStation>.unmodifiable(_stations);

  /// Trenin ön ucunun konumu.
  double get position => _position;
  double get speed => _speed;
  double get speedKmh => _speed * 3.6;
  double get throttleLevel => _throttle;
  double get brakeLevel => _brake;
  bool get throttleHeld => _throttleHeld;
  bool get brakeHeld => _brakeHeld;
  int get served => _served;
  int get misses => _misses;
  int get streak => _streak;
  int get passengersTotal => _passengersTotal;

  /// Oyun başından beri geçen süre; çizimdeki yanıp sönmeler için.
  double get clockSeconds => _elapsed;

  /// Son fizik adımından bu yana geçen süre (en fazla 50 ms).
  ///
  /// Fizik motorun `Timer`'ıyla ilerliyor ve o zamanlayıcı ekran
  /// yenilemesine (vsync) hizalı değil: tarayıcıda bazı karelerde hiç adım
  /// gelmiyor, bazılarında iki adım geliyor, tren kasarak ilerliyordu.
  /// Çizim her vsync karesinde konumu bu süre kadar ileri kestirir.
  double get _sinceTick {
    final at = _lastTickAt;
    if (at == null || status != GameStatus.playing || isDwelling) return 0;
    final s = clock.now().difference(at).inMicroseconds / 1e6;
    return s.clamp(0.0, 0.05);
  }

  /// Çizilecek ön uç konumu: fizik konumu + hız × son adımdan geçen süre.
  double get renderPosition => _position + _speed * _sinceTick;

  /// Çizilecek oyun saati (titreşim ve yanıp sönmeler için).
  double get renderClock => _elapsed + _sinceTick;

  StopResult? get lastResult => _lastResult;
  int get resultPulse => _resultPulse;

  /// "Biraz daha ilerle" ipucu.
  int get hintPulse => _hintPulse;

  MachinistStation get target => _stations[_targetIndex];

  /// Durak işaretine kalan mesafe; eksi ise geçildi.
  double get distanceToStop => target.stopPos - _position;

  bool get isDwelling => _dwell != null;
  MachinistStation? get dwellStation => _dwellStation;

  /// Kapı açıklığı, 0 kapalı – 1 tam açık.
  double get doorOpen {
    final t = _dwell;
    if (t == null) return 0;
    if (t < MachinistRules.doorOpenSeconds) {
      return t / MachinistRules.doorOpenSeconds;
    }
    final closeAt =
        MachinistRules.doorOpenSeconds + MachinistRules.boardingSeconds;
    if (t < closeAt) return 1;
    return (1 - (t - closeAt) / MachinistRules.doorCloseSeconds).clamp(0, 1);
  }

  /// Biniş ilerlemesi, 0 – 1.
  double get boardingProgress {
    final t = _dwell;
    if (t == null) return 0;
    return ((t - MachinistRules.doorOpenSeconds * 0.6) /
            MachinistRules.boardingSeconds)
        .clamp(0.0, 1.0);
  }

  /// Sayaç: 3, 2, 1, 0 (DUR) ya da yok.
  int? get countdown =>
      isDwelling ? null : MachinistRules.countdownFor(distanceToStop);

  /// Sarı ışık: istasyon yaklaşıyor.
  bool get approaching =>
      !isDwelling && distanceToStop <= MachinistRules.approachWarning;

  /// Bu hızla tam frende bile işareti geçecek mi?
  bool get tooFast =>
      approaching &&
      distanceToStop > 0 &&
      MachinistRules.brakingDistance(_speed) >
          distanceToStop + MachinistRules.stopTolerance;

  /// Frene basmanın vakti geldi mi?
  bool get shouldBrake =>
      approaching &&
      distanceToStop > 0 &&
      MachinistRules.brakingDistance(_speed) > distanceToStop - 12;

  // ------------------------------------------------------------- girdiler

  void setThrottle(bool held) {
    if (_throttleHeld == held) return;
    _throttleHeld = held;
    notifyListeners();
  }

  void setBrake(bool held) {
    if (_brakeHeld == held) return;
    _brakeHeld = held;
    notifyListeners();
  }

  // ----------------------------------------------------------------- akış

  @override
  void onRestart() {
    _position = 0;
    _speed = 0;
    _throttle = 0;
    _brake = 0;
    _throttleHeld = false;
    _brakeHeld = false;
    _dwell = null;
    _dwellStation = null;
    _served = 0;
    _misses = 0;
    _streak = 0;
    _passengersTotal = 0;
    _elapsed = 0;
    _lastTickAt = null;
    _lastResult = null;
    _buildLine();
  }

  @override
  void onPause() {
    _throttleHeld = false;
    _brakeHeld = false;
  }

  /// Testte gerçek zamanlayıcıyı beklemeden ilerletir.
  @visibleForTesting
  void step(double seconds, {double dt = 0.016}) {
    var left = seconds;
    while (left > 1e-9 && status == GameStatus.playing) {
      final d = min(dt, left);
      advance(d);
      left -= d;
    }
  }

  @override
  void onTick(double dt) {
    _elapsed += dt;
    _lastTickAt = clock.now();
    _ensureAhead();

    final dwell = _dwell;
    if (dwell != null) {
      _speed = 0;
      _throttle = 0;
      _brake = _rampTo(_brake, _brakeHeld ? 1 : 0, dt, 0.35);
      final next = dwell + dt;
      if (next >= MachinistRules.dwellSeconds) {
        _dwell = null;
        _dwellStation = null;
      } else {
        _dwell = next;
      }
      return;
    }

    // Aynı anda iki pedal: fren kazanır, gaz kesilir.
    final wantThrottle = _throttleHeld && !_brakeHeld;
    _throttle = _rampTo(
      _throttle,
      wantThrottle ? 1 : 0,
      dt,
      MachinistRules.throttleRampSeconds,
    );
    _brake = _rampTo(
      _brake,
      _brakeHeld ? 1 : 0,
      dt,
      MachinistRules.brakeRampSeconds,
    );

    final wasMoving = _speed > 0;
    final accel =
        _throttle * MachinistRules.throttleAt(_speed) -
        _brake * MachinistRules.brakeDecel -
        MachinistRules.dragAt(_speed);
    _speed = (_speed + accel * dt).clamp(0.0, MachinistRules.maxSpeed);
    // Sürünerek sonsuza dek gitmesin: çok yavaşta pedal yoksa dur.
    if (_speed < 0.08 && _throttle < 0.05) _speed = 0;
    _position += _speed * dt;

    final station = target;
    final error = _position - station.stopPos;
    if (error > MachinistRules.missDistance) {
      _miss(station, error);
      return;
    }
    if (wasMoving && _speed == 0) _onStopped(station, error);
  }

  double _rampTo(double value, double goal, double dt, double seconds) {
    final stepSize = dt / seconds;
    if (value < goal) return min(goal, value + stepSize);
    return max(goal, value - stepSize * 1.6);
  }

  void _onStopped(MachinistStation station, double error) {
    final grade = StopGrade.forError(error);
    if (grade != null) {
      _serve(station, error, grade);
    } else if (error > 0) {
      _miss(station, error);
    } else if (-error < MachinistRules.approachWarning) {
      _hintPulse++;
    }
  }

  void _serve(MachinistStation station, double error, StopGrade grade) {
    station.state = StationState.served;
    _streak = grade.keepsStreak ? _streak + 1 : 0;
    final streakBonus = min(max(_streak - 1, 0), 3) * 8;
    final points = grade.points + station.passengers ~/ 2 + streakBonus;
    _served++;
    _passengersTotal += station.passengers;
    _dwell = 0;
    _dwellStation = station;
    _targetIndex++;
    addScore(points);
    markStationProgress();
    _lastResult = StopResult(
      station: station.name,
      error: error,
      grade: grade,
      points: points,
      passengers: station.passengers,
      streak: _streak,
    );
    _resultPulse++;
  }

  void _miss(MachinistStation station, double error) {
    station.state = StationState.missed;
    _misses++;
    _streak = 0;
    _targetIndex++;
    _lastResult = StopResult(station: station.name, error: error);
    _resultPulse++;
    if (_misses >= MachinistRules.maxMisses) endGame();
  }

  // ------------------------------------------------------------------ hat

  void _buildLine() {
    _stations.clear();
    _targetIndex = 1;
    // Tren biniş istasyonunda, kapıları kapalı, durak işaretinde bekliyor.
    _stations.add(
      MachinistStation(
        index: 0,
        name: _names[0],
        stopPos: 0,
        passengers: 0,
        curve: _nextCurve(0),
        state: StationState.served,
      ),
    );
    _ensureAhead();
  }

  /// Önümüzdeki 1,5 km'yi hep hazır tutar; geride kalanları atar.
  void _ensureAhead() {
    while (_stations.last.stopPos < _position + 1500) {
      final last = _stations.last;
      final index = last.index + 1;
      final gap =
          MachinistRules.minStationGap +
          _random.nextDouble() *
              (MachinistRules.maxStationGap - MachinistRules.minStationGap);
      _stations.add(
        MachinistStation(
          index: index,
          name: _nameAt(index),
          stopPos: last.stopPos + gap,
          passengers: 6 + _random.nextInt(25),
          curve: _nextCurve(index),
        ),
      );
    }
    while (_stations.length > 3 &&
        _stations[1].hallEnd < _position - 400 &&
        _targetIndex > 1) {
      _stations.removeAt(0);
      _targetIndex--;
    }
  }

  double _nextCurve(int index) {
    final side = index.isEven ? 1.0 : -1.0;
    return side * (7 + _random.nextDouble() * 9);
  }

  /// Hat sonuna gelince geri döner: A B C D C B A B …
  String _nameAt(int index) {
    final n = _names.length;
    if (n == 1) return _names.first;
    final period = 2 * (n - 1);
    final k = index % period;
    return _names[k < n ? k : period - k];
  }
}
