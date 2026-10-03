import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/simit_catch_state.dart';

/// İzin bir noktası: martının geçtiği yer (dünya koordinatı).
@immutable
class SimitTrailPoint {
  const SimitTrailPoint(this.x, this.y);

  final double x;
  final double y;
}

/// Simit Kap — Flappy Dunk mantığı: martı simitlerin içinden yukarıdan
/// aşağı süzülür.
///
/// Dokunuş kanat çırpar. Simidin içinden geçmek puan; kenarına hiç
/// değmeden geçmek TAM İSABET ve seri. Kenar martıyı sektirir ama oyunu
/// bitirmez. Oyunu bitiren iki şey var: bir simidi kaçırmak ya da denize
/// düşmek (kullanıcı kararı: Flappy Dunk'taki gibi).
class SimitCatchController extends JourneyGameController {
  SimitCatchController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    super.discovery,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
    super.session,
  }) : _random = random ?? Random(),
       super(gameId: id, maxFrameSeconds: _maxFrameSeconds) {
    _resetFlight();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'simit_catch';

  /// Diğer gerçek zamanlı oyunlarla aynı kırpma: uzun bir donmadan sonra
  /// martı tek karede simidin içinden ışınlanmasın.
  static const double _maxFrameSeconds = 0.05;

  /// İz noktaları arasındaki süre ve en fazla kaç nokta tutulduğu.
  static const double _trailEvery = 0.05;
  static const int _trailLength = 9;

  final Random _random;

  SimitCatchPhase _phase = SimitCatchPhase.waiting;
  double _scroll = 0;
  double _birdY = _startY;
  double _velocity = 0;
  double _clock = 0;
  double _lastFlapAt = -10;
  double _trailClock = 0;
  final List<Simit> _simits = <Simit>[];
  final List<SimitTrailPoint> _trail = <SimitTrailPoint>[];
  int _nextId = 0;

  int _passed = 0;
  int _swishes = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _lastAward = 0;
  bool _lastAwardSwish = false;
  double _awardAt = -10;
  double _awardY = 0;
  int _awardPulse = 0;
  int _bumpPulse = 0;
  int _flapPulse = 0;
  SimitCatchEnd? _endReason;

  static const double _startY = 0.42;

  // ---------------------------------------------------------------- okuma

  SimitCatchPhase get phase => _phase;

  /// Oyunu bitiren sebep; oyun sürüyorsa `null`.
  SimitCatchEnd? get endReason => _endReason;
  bool get isWaiting => _phase == SimitCatchPhase.waiting;

  /// Şu anki zorluk ayarı — geçilen simit sayısıyla sertleşir.
  SimitCatchConfig get config => SimitCatchConfig.forSimits(_passed);

  /// Sahnenin başından beri kat edilen yol; çizici simitleri ve arka
  /// planı buna göre kaydırır.
  double get scroll => _scroll;

  /// Martının dünya x'i.
  double get birdWorldX => _scroll + simitCatchBirdX;
  double get birdY => _birdY;
  double get velocity => _velocity;

  /// Oyun saati (bekleme dahil); kanat ve dalga animasyonları için.
  double get clock => _clock;

  /// Son kanat çırpıştan geçen süre.
  double get sinceFlap => _clock - _lastFlapAt;

  /// Her kanatta artar — ekran ses ve titreşimi buna bağlar.
  int get flapPulse => _flapPulse;

  /// Kenara her çarpışta artar.
  int get bumpPulse => _bumpPulse;

  List<Simit> get simits => List<Simit>.unmodifiable(_simits);
  List<SimitTrailPoint> get trail => List<SimitTrailPoint>.unmodifiable(_trail);

  /// Sıradaki (henüz geçilmemiş) simit.
  Simit? get nextSimit {
    for (final simit in _simits) {
      if (simit.state == SimitState.ahead) return simit;
    }
    return null;
  }

  int get simitsPassed => _passed;
  int get swishes => _swishes;

  /// Üst üste TAM İSABET sayısı.
  int get streak => _streak;
  int get bestStreak => _bestStreak;

  /// Son geçişin yolculuğa kattığı puan. Ham sayı gösterilseydi skor
  /// tablosuyla tutmazdı (ham puan ortak ölçekle çarpılıyor).
  int get lastAward => _lastAward;
  bool get lastAwardSwish => _lastAwardSwish;

  /// Son puan yazısının üzerinden geçen süre ve çıktığı yükseklik.
  double get sinceAward => _clock - _awardAt;
  double get awardY => _awardY;
  int get awardPulse => _awardPulse;

  // ------------------------------------------------------------- girdiler

  void flap() {
    if (status != GameStatus.playing) return;
    _phase = SimitCatchPhase.flying;
    _velocity = config.flapVelocity;
    _lastFlapAt = _clock;
    _flapPulse++;
    notifyListeners();
  }

  // ----------------------------------------------------------------- akış

  @override
  void onRestart() {
    _passed = 0;
    _swishes = 0;
    _streak = 0;
    _bestStreak = 0;
    _lastAward = 0;
    _awardAt = -10;
    _resetFlight();
  }

  /// Testte elle kurulmuş bir sahne.
  @visibleForTesting
  void debugSetFlight({
    double? birdY,
    double? velocity,
    List<Simit>? simits,
    bool flying = true,
  }) {
    _birdY = birdY ?? _birdY;
    _velocity = velocity ?? _velocity;
    if (simits != null) {
      _simits
        ..clear()
        ..addAll(simits);
      _nextId = simits.isEmpty ? 0 : simits.last.id + 1;
    }
    if (flying) _phase = SimitCatchPhase.flying;
    notifyListeners();
  }

  /// Testte gerçek zamanlayıcıyı beklemeden ilerletir.
  @visibleForTesting
  void step(double seconds, {double dt = 1 / 60}) {
    var left = seconds;
    while (left > 1e-9 && status == GameStatus.playing) {
      final d = min(dt, left);
      advance(d);
      left -= d;
    }
  }

  @override
  void onTick(double dt) {
    _clock += dt;
    if (_phase == SimitCatchPhase.waiting) {
      // Martı yerinde süzülür; sahne ilk kanadı bekler.
      _birdY = _startY + 0.012 * sin(_clock * 4);
      notifyListeners();
      return;
    }

    final cfg = config;
    _scroll += cfg.speed * dt;
    final previousY = _birdY;
    _velocity += cfg.gravity * dt;
    _birdY += _velocity * dt;

    // Tavan öldürmez: martı orada durur.
    if (_birdY - simitCatchBirdRadius < 0) {
      _birdY = simitCatchBirdRadius;
      _velocity = max(_velocity, 0);
    }

    final birdX = birdWorldX;
    for (final simit in _simits) {
      if (simit.state != SimitState.ahead) continue;
      _collideRim(simit, simit.leftRim, birdX);
      _collideRim(simit, simit.rightRim, birdX);
    }
    for (final simit in _simits) {
      if (simit.state != SimitState.ahead) continue;
      final line = simit.lineYAt(birdX);
      if (previousY < line && _birdY >= line && simit.opensAt(birdX)) {
        _score(simit);
      }
    }

    _recordTrail(dt);
    _trimAndSpawn();

    if (_birdY + simitCatchBirdRadius >= simitCatchSeaLevel) {
      _endReason = SimitCatchEnd.sea;
      endGame();
      return;
    }
    for (final simit in _simits) {
      if (simit.state == SimitState.ahead && simit.behind(birdX)) {
        simit.state = SimitState.missed;
        _endReason = SimitCatchEnd.missed;
        endGame();
        return;
      }
    }
    notifyListeners();
  }

  /// Kenar halkasıyla çarpışma: martı **dikeyde** itilir ve seker.
  ///
  /// Yatayda itmek anlamsız: martının x'i sabit, sahne akıyor. Flappy
  /// Dunk'taki top da kenara çarpınca yalnız yukarı ya da aşağı seker.
  void _collideRim(Simit simit, Point<double> rim, double birdX) {
    const reach = simitCatchBirdRadius + simitCatchRimRadius;
    final dx = birdX - rim.x;
    if (dx.abs() >= reach) return;
    final allowed = sqrt(reach * reach - dx * dx);
    final dy = _birdY - rim.y;
    if (dy.abs() >= allowed) return;
    if (dy <= 0) {
      _birdY = rim.y - allowed;
      if (_velocity > 0) _velocity = -_velocity * simitCatchBounce;
    } else {
      _birdY = rim.y + allowed;
      if (_velocity < 0) _velocity = -_velocity * simitCatchBounce;
    }
    if (!simit.touched) _bumpPulse++;
    simit.touched = true;
  }

  void _score(Simit simit) {
    simit.state = SimitState.passed;
    _passed++;
    final swish = !simit.touched;
    if (swish) {
      _swishes++;
      _streak++;
      _bestStreak = max(_bestStreak, _streak);
    } else {
      _streak = 0;
    }
    final before = score;
    addScore(simitCatchPoints(swish: swish, streak: _streak));
    markStationProgress();
    _lastAward = score - before;
    _lastAwardSwish = swish;
    _awardAt = _clock;
    _awardY = simit.y;
    _awardPulse++;
  }

  void _recordTrail(double dt) {
    _trailClock += dt;
    if (_trailClock < _trailEvery) return;
    _trailClock = 0;
    _trail.add(SimitTrailPoint(birdWorldX, _birdY));
    if (_trail.length > _trailLength) _trail.removeAt(0);
  }

  void _resetFlight() {
    _phase = SimitCatchPhase.waiting;
    _endReason = null;
    _scroll = 0;
    _birdY = _startY;
    _velocity = 0;
    _lastFlapAt = -10;
    _trailClock = 0;
    _trail.clear();
    _simits.clear();
    _nextId = 0;
    // İlk simit martının hemen önünde ve aynı hizanın biraz altında: ilk
    // dokunuşlarda "yukarı çık, içine düş" kendiliğinden öğreniliyor.
    _simits.add(
      Simit(
        id: _nextId++,
        x: simitCatchBirdX + 0.42,
        y: 0.52,
        halfWidth: config.halfWidth,
        tilt: _randomTilt(),
      ),
    );
    _trimAndSpawn();
  }

  void _trimAndSpawn() {
    _simits.removeWhere((simit) => simit.x < _scroll - 0.4);
    final cfg = config;
    while (_simits.isEmpty ||
        _simits.last.x < birdWorldX + simitCatchSpawnAhead) {
      final last = _simits.isEmpty ? null : _simits.last;
      final x = (last?.x ?? birdWorldX) + cfg.spacing * _jitter(0.88, 1.12);
      final from = last?.y ?? 0.5;
      final y = (from + (_random.nextDouble() * 2 - 1) * cfg.maxRise).clamp(
        simitCatchTopLane,
        simitCatchBottomLane,
      );
      _simits.add(
        Simit(
          id: _nextId++,
          x: x,
          y: y,
          halfWidth: cfg.halfWidth,
          tilt: _randomTilt(),
        ),
      );
    }
  }

  double _jitter(double low, double high) =>
      low + _random.nextDouble() * (high - low);

  /// ±0,14 rad (~8°): hafif yan yatık; daha fazlası açıklığı daraltıp
  /// zorluğu simitten simide oynatıyordu.
  double _randomTilt() => (_random.nextDouble() * 2 - 1) * 0.14;
}
