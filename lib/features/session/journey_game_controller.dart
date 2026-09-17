import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/local_store.dart';
import '../games/blocks/domain/scoring.dart' show ScoreRules;
import '../journey/models/journey.dart';
import 'journey_run.dart';

/// Her oyunun paylaştığı yolculuk motoru.
///
/// Sayaç, varış tespiti, durak bonusu, rekor takibi ve kaydı burada bir kez
/// yazılır. Oyun yalnızca **kendi kurallarını** yazar.
///
/// Bu sınıf çıkarılmadan önce aynı mantık altı controller'da ayrı ayrı
/// duruyordu ve çoktan sapmıştı: kalan süre üç farklı şekilde yuvarlanıyordu
/// (`ceil`, `floor`, tam bölme). Tek kaynak bunu da tekleştirir.
///
/// **Zaman modeli tek:** [advance] saniye cinsinden `dt` alır. Sıra tabanlı
/// oyunlar saniyede bir 1.0 ile, gerçek zamanlı oyunlar 60 Hz'de ~0.016 ile
/// ilerler; ikisi de aynı ilerleme ve varış mantığını kullanır.
abstract class JourneyGameController extends ChangeNotifier
    implements JourneyRun {
  JourneyGameController({
    required this.gameId,
    required this.journey,
    required int recordToBeat,
    required this.tick,
    this.store,
    this.maxFrameSeconds,
    // Alan private + mutable (restart tazeliyor), parametre public kalmalı;
    // `this._recordToBeat` dışarıdan kullanılamayacak bir ad üretirdi.
    // ignore: prefer_initializing_formals
  }) : _recordToBeat = recordToBeat;

  /// Rekorlar oyun bazında tutulur; aynı rotanın her oyunda ayrı rekoru var.
  final String gameId;

  final LocalStore? store;

  /// Sayaç periyodu. Sıra tabanlı oyunlarda 1 sn, gerçek zamanlıda ~16 ms.
  final Duration tick;

  /// Gerçek zamanlı oyunlar için: tek karede en fazla sayılacak süre (sn).
  ///
  /// `null` ise her tik tam [tick] kadar sayılır (sıra tabanlı oyunlar).
  /// Doluysa geçen süre `package:clock` ile **ölçülür** ve bu değere
  /// kırpılır. Telefonda `Timer` düzenli gelmez; sabit [tick] varsaymak
  /// akışı yavaşlatıp sıçratıyordu. Kırpma da uzun bir donmadan sonra
  /// fiziğin tek karede engelin içinden geçmesini önler. `clock`, testte
  /// `fakeAsync` ile sahtelenebildiği için ham `DateTime.now()` yerine
  /// kullanılır. (Ray Uçuşu / Ray Değiştir ekibinin düzeltmesi; motora
  /// taşındı ki her gerçek zamanlı oyun yararlansın.)
  final double? maxFrameSeconds;

  DateTime? _lastFrameTime;

  @override
  final Journey journey;

  GameStatus _status = GameStatus.ready;
  double _elapsedSeconds = 0;
  int _score = 0;
  int _recordToBeat;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  bool _scoreSaved = false;
  int _stationsPassed = 0;

  /// Son duraktan beri bonusu hak edecek bir şey oldu mu?
  bool _stationProgress = false;

  Timer? _timer;

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

  // --- JourneyRun ---

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
    final total = journey.estimatedSeconds;
    if (total <= 0) return 1;
    return (_elapsedSeconds / total).clamp(0.0, 1.0);
  }

  @override
  double get recordProgress {
    if (isFirstRun) return 0;
    return (_score / _recordToBeat).clamp(0.0, 1.0);
  }

  /// Kalan süre. `floor` kullanılır: yolculuk, tahmin edilen saniye gerçekten
  /// dolmadan bitmez. (`ceil` bir saniye erken bitiriyordu.)
  @override
  int get remainingSeconds {
    final left = journey.estimatedSeconds - _elapsedSeconds.floor();
    return left < 0 ? 0 : left;
  }

  /// Sprintin açılması için gereken en az durak sayısı.
  ///
  /// Kısa yolculuklarda "son durak sprinti" anlamsız: iki duraklık bir
  /// yolculuğun son %15'i birkaç saniye sürer ve oyuncu farkına bile varmaz.
  static const int sprintMinStops = 5;

  /// Yolculuğun son dilimi: puanlar iki katı.
  @override
  bool get isSprint =>
      journey.stopCount >= sprintMinStops &&
      progress >= ScoreRules.sprintStartsAt;

  @override
  int sprintPulse = 0;
  bool _sprintAnnounced = false;

  /// Geçen süre (saniye). Gerçek zamanlı oyunlarda kesirli olabilir.
  ///
  /// Duraklatmada ilerlemez; ekranlar arka plan dokularını kaydırmak için
  /// de kullanır.
  double get elapsedSeconds => _elapsedSeconds;

  // --- Yaşam döngüsü ---

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
    onPause();
    notifyListeners();
  }

  @override
  void resume() {
    if (_status != GameStatus.paused) return;
    _status = GameStatus.playing;
    _startTimer();
    onResume();
    notifyListeners();
  }

  @override
  void restart() {
    _stopTimer();
    _score = 0;
    _elapsedSeconds = 0;
    _recordBeaten = false;
    _isNewBest = false;
    _scoreSaved = false;
    _stationsPassed = 0;
    _stationProgress = false;
    lastStationBonus = 0;
    sprintPulse = 0;
    _sprintAnnounced = false;
    _refreshRecord();
    onRestart();
    start();
  }

  @override
  void abandon() {
    _stopTimer();
    if (_status.isFinished) return;
    _status = GameStatus.abandoned;
    onAbandon();
    notifyListeners();
  }

  // --- Oyunun kullanacağı araçlar ---

  /// Puan ekler ve rekor geçildiyse işaretler. Geçildiyse `true` döner.
  ///
  /// Sprint çarpanı **burada** uygulanır; oyunların ayrı ayrı hatırlaması
  /// gerekmez.
  @protected
  bool addScore(int points) {
    if (points == 0) return false;
    _score += isSprint ? points * ScoreRules.sprintMultiplier : points;
    return _checkRecord();
  }

  /// "Bu duraktan beri kayda değer bir şey yaptım" — durak bonusunun koşulu.
  ///
  /// Blok oyununda satır temizlemek, Ray Uçuşu'nda kapı geçmek gibi.
  @protected
  void markStationProgress() => _stationProgress = true;

  /// Durak bonusu hakkını geri alır (geri alınan bir hamle bonus vermemeli).
  @protected
  void revokeStationProgress(bool previous) => _stationProgress = previous;

  @protected
  bool get hasStationProgress => _stationProgress;

  /// Tren kaç durağı geçti.
  int get stationsPassed => _stationsPassed;

  /// Sayacı durdurur ama **durumu değiştirmez**.
  ///
  /// Oyun hâlâ `playing` sayılır; yalnızca yolculuk ilerlemesi durur. Blok
  /// oyunu bunu "hamle kalmadı ama geri alma hakkın var" teklifinde
  /// kullanıyor: oyuncu karar verene kadar tren beklemeli, yoksa hiç
  /// oynamadan varışa ulaşılabilir. Duraklatmadan ([pause]) farkı, oyunun
  /// duraklatılmış görünmemesi.
  @protected
  void holdClock() => _stopTimer();

  /// [holdClock] ile durdurulan sayacı yeniden başlatır.
  @protected
  void releaseClock() {
    if (_status != GameStatus.playing) return;
    _startTimer();
  }

  /// Oyunun kendi kaydından ya da geri almasından dönen motor durumu.
  ///
  /// Motor skoru ve saati kendi tutar; oyunun bunlara doğrudan yazması
  /// gerekmez. Ama iki durumda geri sarmak şart:
  ///
  /// - **geri alma**: hamlenin kazandırdığı puan ve süre geri verilmeli,
  /// - **kayıttan devam**: yarım kalan oyun kaldığı yerden başlamalı.
  ///
  /// Verilmeyen alanlar olduğu gibi kalır.
  @protected
  void restoreProgress({
    int? score,
    double? elapsedSeconds,
    int? stationsPassed,
    bool? recordBeaten,
    bool? stationProgress,
  }) {
    if (score != null) _score = score < 0 ? 0 : score;
    if (elapsedSeconds != null) {
      _elapsedSeconds = elapsedSeconds < 0 ? 0 : elapsedSeconds;
    }
    if (stationsPassed != null) _stationsPassed = stationsPassed;
    if (recordBeaten != null) _recordBeaten = recordBeaten;
    if (stationProgress != null) _stationProgress = stationProgress;
  }

  /// Geçilecek rekoru doğrudan ayarlar.
  ///
  /// Kayıttan dönen oyun, kaydedildiği andaki rekoru taşır; depodaki değer
  /// bu arada yükselmiş olabilir. İkisinden **yüksek olan** hedeflenir.
  @protected
  void raiseRecordToBeat(int value) {
    if (value > _recordToBeat) _recordToBeat = value;
  }

  /// Oyunun durumunu doğrudan ayarlar (kayıttan `paused` dönmek gibi).
  @protected
  void setStatus(GameStatus value) => _status = value;

  /// Oyun kendi kuralına takıldı: hamle kalmadı, çarpıştı, süre doldu…
  @protected
  void endGame() => _finish(GameStatus.gameOver);

  /// Rekor bu anda geçildiyse işaretler ve geçildiğini döner.
  @protected
  bool checkRecord() => _checkRecord();

  // --- Oyunun dolduracağı kancalar ---

  /// Oyunun kendi kare güncellemesi. Sıra tabanlı oyunlarda boş kalabilir.
  @protected
  void onTick(double dt) {}

  /// Yeniden başlatmada oyunun kendi durumunu sıfırlaması.
  @protected
  void onRestart();

  @protected
  void onPause() {}

  @protected
  void onResume() {}

  @protected
  void onAbandon() {}

  /// Oyun bittiğinde (varış ya da kaybediş) oyunun kendi temizliği.
  @protected
  void onFinish(GameStatus status) {}

  // --- Motor ---

  void _startTimer() {
    _timer?.cancel();
    if (maxFrameSeconds == null) {
      _timer = Timer.periodic(tick, (_) {
        advance(tick.inMicroseconds / Duration.microsecondsPerSecond);
      });
      return;
    }
    _lastFrameTime = clock.now();
    _timer = Timer.periodic(tick, (_) {
      advance(_elapsedSecondsSince(clock.now()));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _lastFrameTime = null;
  }

  /// Son kareden bu yana ölçülen, [maxFrameSeconds] ile kırpılmış süre.
  ///
  /// İlk çağrı yalnızca referansı kurar ve 0 döner.
  double _elapsedSecondsSince(DateTime now) {
    final last = _lastFrameTime;
    _lastFrameTime = now;
    if (last == null) return 0;
    final elapsed =
        now.difference(last).inMicroseconds / Duration.microsecondsPerSecond;
    return elapsed.clamp(0.0, maxFrameSeconds ?? double.infinity);
  }

  /// Testte düzensiz kare senaryolarını gerçek zamanı beklemeden sınamak için.
  @visibleForTesting
  double debugElapsedSecondsSince(DateTime now) => _elapsedSecondsSince(now);

  /// Yolculuğu [dt] saniye ilerletir.
  ///
  /// Sayaç bunu kendi çağırır; gerçek zamanlı oyunlar testte kareyi elle
  /// ilerletmek için de kullanır.
  @protected
  void advance(double dt) {
    if (_status != GameStatus.playing) return;

    _elapsedSeconds += dt;
    onTick(dt);
    if (_status != GameStatus.playing) return; // oyun bu karede bitmiş olabilir

    _announceSprintIfStarted();
    _awardStationBonusIfPassed();

    if (remainingSeconds <= 0) {
      _finish(GameStatus.arrived);
      return;
    }
    notifyListeners();
  }

  /// Sprint bu karede başladıysa bir kez bildirir.
  void _announceSprintIfStarted() {
    if (_sprintAnnounced || !isSprint) return;
    _sprintAnnounced = true;
    sprintPulse++;
  }

  /// Testte yolculuğu elle ilerletmek için.
  @visibleForTesting
  void debugAdvance(double dt) => advance(dt);

  /// Tren yeni bir durağı geçtiyse ve o duraktan beri ilerleme olduysa bonus.
  void _awardStationBonusIfPassed() {
    final stops = journey.stopCount;
    if (stops <= 0) return;

    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;

    final earned = _stationProgress;
    _stationProgress = false;
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

  /// Geçilecek rekoru depodan tazeler.
  ///
  /// Sonuç panelinden "tekrar oyna" denince ekran yeniden kurulmaz;
  /// tazelenmezse ikinci oyun az önce kırılan eski rekoru hedefler.
  void _refreshRecord() {
    final stored = store?.bestScoreForGameRoute(
      gameId: gameId,
      originId: journey.origin.id,
      destinationId: journey.destination.id,
    );
    if (stored != null && stored > _recordToBeat) _recordToBeat = stored;
  }

  void _finish(GameStatus status) {
    _stopTimer();
    _status = status;
    onFinish(status);
    notifyListeners();
    unawaited(_persistScore());
  }

  Future<void> _persistScore() async {
    final target = store;
    if (target == null || _scoreSaved) return;
    _isNewBest = await target.submitGameRouteScore(
      gameId: gameId,
      originId: journey.origin.id,
      destinationId: journey.destination.id,
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
