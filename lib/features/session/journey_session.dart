import 'package:flutter/foundation.dart';

import '../games/blocks/domain/scoring.dart' show ScoreRules;
import '../journey/models/journey.dart';
import '../discovery/application/journey_discovery.dart';
import 'journey_run.dart';
import 'scoring/game_score_profile.dart';

/// Bir yolculuğun tamamı: saat, durak sayacı, puan ve rekor.
///
/// **Yolculuk oyundan uzun yaşar.** Oyuncu Blok Metro'dan Hat Düşür'e
/// geçtiğinde tren durmaz, puan sıfırlanmaz: ikisi de burada durur. Oyun
/// controller'ı ([JourneyGameController]) yalnızca kendi kurallarını
/// yazar ve kazandırdığı puanı buraya iletir.
///
/// [JourneyView] uyguladığı için ortak arayüz parçaları — skor göstergesi,
/// ilerleme şeridi, durak şeridi — oyun ekranı olmadan da beslenebilir;
/// oyun seçim ekranı canlı şeridi bu sayede hiçbir widget'ı değiştirmeden
/// gösterir.
class JourneySession extends ChangeNotifier implements JourneyView {
  JourneySession({
    required this.journey,
    int recordToBeat = 0,
    // Alan private + mutable (rekor tazelenebiliyor), parametre public
    // kalmalı; `this._recordToBeat` dışarıdan kullanılamayacak bir ad
    // üretirdi.
    // ignore: prefer_initializing_formals
  }) : _recordToBeat = recordToBeat;

  @override
  final Journey journey;

  GameStatus _status = GameStatus.ready;
  double _elapsedSeconds = 0;
  int _score = 0;
  int _recordToBeat;
  bool _recordBeaten = false;
  bool _isNewBest = false;
  int _stationsPassed = 0;

  /// Son duraktan beri bonusu hak edecek bir şey oldu mu?
  bool _stationProgress = false;

  /// Oyunun bu karede kazandırdığı, henüz saate yazılmamış saniye.
  double _pendingSeconds = 0;

  bool _sprintAnnounced = false;

  /// Puanın oyunlara göre dağılımı.
  ///
  /// Yolculuk boyunca hangi oyunun ne kazandırdığı buradan okunur; durak
  /// bonusu gibi yolculuğun kendi puanı [journeyBucket] altında toplanır.
  final Map<String, int> _scoreByGame = <String, int>{};

  /// Ölçekten artan kesirler — oyun başına birikir.
  ///
  /// Hızlı oyunlarda tek bir olay (bir kapı, bir engel) ortak para
  /// biriminde bir puandan azdır: dakikada 120 puan hedefi, saniyede iki
  /// olay üreten bir oyunda olay başına ~1 puan demek. Kesir atılsaydı o
  /// oyun hiç puan vermezdi. Artan burada birikir; eksi de olabilir
  /// (yuvarlama bir seferde fazla verdiyse, sonraki olaydan düşer).
  final Map<String, double> _scoreCarry = <String, double>{};

  /// Hangi oyunda kaç saniye oynandı.
  ///
  /// Puanın tek başına anlamı yok: 800 puan altı dakika oynandıysa normal,
  /// bir dakika oynandıysa bir denge hatasıdır. Sonuç paneli ikisini yan
  /// yana yazıyor ki fark gözle görülsün.
  final Map<String, double> _secondsByGame = <String, double>{};

  /// Oyuna değil yolculuğa ait puanların (durak bonusu) kovası.
  static const String journeyBucket = 'journey';

  /// Sprintin açılması için gereken en az durak sayısı.
  ///
  /// Kısa yolculuklarda "son durak sprinti" anlamsız: iki duraklık bir
  /// yolculuğun son %15'i birkaç saniye sürer ve oyuncu farkına bile varmaz.
  static const int sprintMinStops = 5;

  // --- JourneyView ---

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

  /// Yolculuğun son dilimi: puanlar iki katı.
  @override
  bool get isSprint =>
      journey.stopCount >= sprintMinStops &&
      progress >= ScoreRules.sprintStartsAt;

  @override
  int lastStationBonus = 0;

  @override
  int stationBonusPulse = 0;

  @override
  int stationPulse = 0;

  @override
  int sprintPulse = 0;

  // --- Okunabilir durum ---

  /// Geçen süre (saniye). Gerçek zamanlı oyunlarda kesirli olabilir.
  double get elapsedSeconds => _elapsedSeconds;

  /// Ortak yolculuğun keşif defteri yok.
  ///
  /// Keşfi koşuyu ilerleten oyun controller'ı yazıyor; oturum yalnız
  /// sayaçları tutuyor. Okuyan widget'lar (durak şeridi, sonuç paneli)
  /// burada `null` görüp keşif vurgusunu atlıyor.
  @override
  JourneyDiscovery? get discovery => null;

  /// Tren kaç durağı geçti.
  int get stationsPassed => _stationsPassed;

  bool get hasStationProgress => _stationProgress;

  /// Puanın oyunlara göre dağılımının kopyası.
  Map<String, int> get scoreByGame =>
      Map<String, int>.unmodifiable(_scoreByGame);

  /// Verilen oyunun bu yolculukta kazandırdığı puan.
  int scoreOf(String gameId) => _scoreByGame[gameId] ?? 0;

  /// Oyunlara göre oynanan sürenin (saniye) kopyası.
  Map<String, double> get secondsByGame =>
      Map<String, double>.unmodifiable(_secondsByGame);

  /// Verilen oyunda bu yolculukta geçirilen saniye.
  double secondsOf(String gameId) => _secondsByGame[gameId] ?? 0;

  /// Oyun ekranında geçen süreyi o oyunun hanesine yazar.
  ///
  /// Yalnızca **oynanan** süre sayılır: menüde ya da başlık ekranında
  /// geçen süre hiçbir oyunun değil, yolculuğun.
  void creditPlaySeconds(String gameId, double seconds) {
    if (seconds <= 0) return;
    _secondsByGame[gameId] = (_secondsByGame[gameId] ?? 0) + seconds;
  }

  // --- Saat ---

  /// Yolculuğu şu an bir oyun mu ilerletiyor?
  ///
  /// Oyun oynanırken saati oyunun kare döngüsü sürer; oyun yokken
  /// [JourneyHost] kalp atışı devralır. İkisi aynı anda ilerletirse süre iki
  /// kat hızlı akar, bu yüzden sürücü tek olmalı.
  bool get isDriven => _driver != null;
  Object? _driver;

  void attachDriver(Object token) => _driver = token;

  void detachDriver(Object token) {
    if (identical(_driver, token)) _driver = null;
  }

  /// Saati [dt] saniye ilerletir; durak ve varış kontrolü yapmaz.
  ///
  /// Kontroller [settle] içinde, oyunun kendi karesi işlendikten sonra
  /// çalışır: iyi oyunun kazandırdığı saniyeler ([rewardJourney]) o kareye
  /// yetişsin ve durak geçişi tek seferde hesaplansın diye.
  void addElapsed(double dt) {
    if (dt <= 0) return;
    _elapsedSeconds += dt;
  }

  /// Uygulama arka plandayken geçen süreyi yolculuğa yazar.
  ///
  /// Zamanlayıcılar arka planda kısılır; dönüşte aradaki fark bir kez
  /// buradan eklenir. Uygulama tamamen kapatılmışsa çağrılmaz: kapalı
  /// geçen süre yolculuğa yazılmaz.
  void creditElapsed(double seconds) {
    if (seconds <= 0) return;
    _elapsedSeconds += seconds;
  }

  /// Yolculuğa saniye ekler — iyi oyun treni hızlandırır.
  ///
  /// Saat hemen ilerletilmez, bir sonraki [settle] çağrısında yazılır;
  /// gerçek zamanlı oyunlar bunu kendi kare döngülerinden çağırıyor.
  void rewardJourney(double seconds) {
    if (seconds <= 0) return;
    _pendingSeconds += seconds;
  }

  /// Bekleyen saniyeleri yazar, sprinti duyurur, geçilen durakları işler.
  ///
  /// Varış anı geldiyse `true` döner; yolculuğu bitirmek çağıranın işi.
  bool settle() {
    if (_pendingSeconds > 0) {
      _elapsedSeconds += _pendingSeconds;
      _pendingSeconds = 0;
    }

    _announceSprintIfStarted();
    _awardStationBonusIfPassed();

    return remainingSeconds <= 0;
  }

  // --- Puan ---

  /// Puan ekler ve rekor geçildiyse işaretler. Geçildiyse `true` döner.
  ///
  /// Sprint çarpanı **burada** uygulanır; oyunların ayrı ayrı hatırlaması
  /// gerekmez. [gameId] verilirse puan o oyunun hanesine de yazılır.
  bool addScore(int points, {String? gameId}) {
    if (points == 0) return false;
    final awarded = isSprint ? points * ScoreRules.sprintMultiplier : points;
    _score += awarded;
    _credit(gameId ?? journeyBucket, awarded);
    return _checkRecord();
  }

  /// Bir oyunun ham puanını ortak para birimine çevirip ekler.
  ///
  /// Tek huni budur: ölçek ([GameScoreProfiles]) burada uygulanır, sprint
  /// çarpanı ölçekten **sonra** gelir, artan kesir oyunun hanesinde birikir.
  /// Oyunlar ham puanlarını kendi kurallarıyla hesaplar; tempo farkını
  /// kapatmak onların işi değil.
  bool addGameScore({required String gameId, required int raw}) {
    if (raw == 0) return false;
    final scaled =
        raw * GameScoreProfiles.scaleFor(gameId) + (_scoreCarry[gameId] ?? 0);
    // Aşağı değil **en yakına** yuvarlanır: 0,96 puanlık bir olay aşağı
    // yuvarlansaydı oyuncu yolcuyu toplar, skorun kıpırdamadığını görürdü.
    // Fazladan verilen kesir artana eksi olarak yazılır, uzun vadede
    // toplam birebir tutar.
    final whole = scaled.round();
    _scoreCarry[gameId] = scaled - whole;
    if (whole == 0) return false;
    return addScore(whole, gameId: gameId);
  }

  /// Geri alınan hamlenin puanını (ve kazandırdığı saniyeyi) geri alır.
  ///
  /// Puan önce oyunun kendi hanesinden düşülür; oyun o kadar puan
  /// kazanmamışsa kalanı yolculuğun hanesinden gider. Böylece hane
  /// toplamı her zaman skora eşit kalır — sonuç panelindeki dağılım
  /// satırları toplamı tutmalı.
  void refund({required int points, double seconds = 0, String? gameId}) {
    if (seconds > 0) {
      _elapsedSeconds -= seconds;
      if (_elapsedSeconds < 0) _elapsedSeconds = 0;
    }
    if (points <= 0) return;

    var remaining = points > _score ? _score : points;
    _score -= remaining;
    for (final bucket in <String>[gameId ?? journeyBucket, journeyBucket]) {
      if (remaining <= 0) break;
      final have = _scoreByGame[bucket] ?? 0;
      if (have <= 0) continue;
      final taken = have < remaining ? have : remaining;
      _scoreByGame[bucket] = have - taken;
      remaining -= taken;
    }
  }

  void _credit(String bucket, int points) {
    _scoreByGame[bucket] = (_scoreByGame[bucket] ?? 0) + points;
  }

  /// "Bu duraktan beri kayda değer bir şey yaptım" — durak bonusunun koşulu.
  void markStationProgress() => _stationProgress = true;

  /// Durak bonusu hakkını geri alır (geri alınan bir hamle bonus vermemeli).
  void revokeStationProgress(bool previous) => _stationProgress = previous;

  /// Rekor bu anda geçildiyse işaretler ve geçildiğini döner.
  bool checkRecord() => _checkRecord();

  /// Geçilecek rekoru yükseltir; düşürmez.
  ///
  /// Kayıttan dönen yolculuk, kaydedildiği andaki rekoru taşır; depodaki
  /// değer bu arada yükselmiş olabilir. İkisinden **yüksek olan** hedeflenir.
  void raiseRecordToBeat(int value) {
    if (value > _recordToBeat) _recordToBeat = value;
  }

  void markNewBest(bool value) {
    _isNewBest = value;
    notifyListeners();
  }

  void setStatus(GameStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  /// Kaydan dönen ya da geri alınan durum.
  ///
  /// Verilmeyen alanlar olduğu gibi kalır.
  void restore({
    int? score,
    double? elapsedSeconds,
    int? stationsPassed,
    bool? recordBeaten,
    bool? stationProgress,
    Map<String, int>? scoreByGame,
    Map<String, double>? secondsByGame,
  }) {
    if (score != null) _score = score < 0 ? 0 : score;
    if (scoreByGame != null) {
      _scoreByGame
        ..clear()
        ..addAll(scoreByGame);
    }
    if (secondsByGame != null) {
      _secondsByGame
        ..clear()
        ..addAll(secondsByGame);
    }
    if (elapsedSeconds != null) {
      _elapsedSeconds = elapsedSeconds < 0 ? 0 : elapsedSeconds;
    }
    if (stationsPassed != null) _stationsPassed = stationsPassed;
    if (recordBeaten != null) _recordBeaten = recordBeaten;
    if (stationProgress != null) _stationProgress = stationProgress;
  }

  /// Yolculuğu baştan başlatır: saat, puan, duraklar ve bildirimler sıfırlanır.
  void reset() {
    _status = GameStatus.ready;
    _elapsedSeconds = 0;
    _score = 0;
    _scoreByGame.clear();
    _scoreCarry.clear();
    _secondsByGame.clear();
    _recordBeaten = false;
    _isNewBest = false;
    _stationsPassed = 0;
    _stationProgress = false;
    _pendingSeconds = 0;
    _sprintAnnounced = false;
    lastStationBonus = 0;
    stationPulse = 0;
    stationBonusPulse = 0;
    sprintPulse = 0;
  }

  /// Dışarıdan tetiklenen bildirim — controller kendi karesini bitirince.
  void publish() => notifyListeners();

  // --- İç hesaplar ---

  /// Sprint bu karede başladıysa bir kez bildirir.
  void _announceSprintIfStarted() {
    if (_sprintAnnounced || !isSprint) return;
    _sprintAnnounced = true;
    sprintPulse++;
  }

  /// Tren yeni bir durağı geçtiyse ve o duraktan beri ilerleme olduysa bonus.
  void _awardStationBonusIfPassed() {
    final stops = journey.stopCount;
    if (stops <= 0) return;

    final passed = (progress * stops).floor();
    if (passed <= _stationsPassed) return;

    final earned = _stationProgress;
    _stationProgress = false;
    _stationsPassed = passed;

    // Durak geçişi **her hâlükârda** duyurulur; bonus ayrı bir şey. Arka
    // planda birden çok durak geçilmiş olsa bile tek bildirim yeter: sayaç
    // bir artar, oyuncu bir şerit görür.
    stationPulse++;

    if (earned) {
      _score += ScoreRules.stationBonus;
      // Durak bonusu trenin kazandırdığı puandır, oyunun değil.
      _credit(journeyBucket, ScoreRules.stationBonus);
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
}
