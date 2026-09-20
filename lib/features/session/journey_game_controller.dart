import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/local_store.dart';
import '../journey/models/journey.dart';
import 'journey_run.dart';
import 'journey_session.dart';

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
///
/// **Yolculuğun kendisi burada durmaz.** Saat, puan, durak sayacı ve rekor
/// [JourneySession] içindedir; bu sınıf onları yönetir ama sahiplenmez.
/// Böylece aynı yolculuk birden çok oyunu peş peşe taşıyabilir: oyun
/// ekranı kapanır, oturum yaşamaya devam eder.
abstract class JourneyGameController extends ChangeNotifier
    implements JourneyRun {
  JourneyGameController({
    required this.gameId,
    required Journey journey,
    required int recordToBeat,
    required this.tick,
    this.store,
    this.maxFrameSeconds,
    this.onGamePayload,
    JourneySession? session,
  }) : _ownsSession = session == null,
       _session =
           session ??
           JourneySession(journey: journey, recordToBeat: recordToBeat) {
    assert(
      session == null ||
          (session.journey.origin.id == journey.origin.id &&
              session.journey.destination.id == journey.destination.id),
      'Oturum başka bir rotaya ait',
    );
  }

  // Kimlik değil **rota** karşılaştırılıyor: kayıttan dönen yolculuk
  // rotayı yeniden hesaplıyor, ekranın taşıdığı `Journey` ise başka bir
  // nesne. İkisi aynı rotayı gösterdiği sürece aynı yolculuktur.

  /// Yolculuğun kendisi: saat, puan, durak sayacı ve rekor.
  ///
  /// Dışarıdan verilmezse oyun kendi oturumunu kurar — tek oyunluk bir
  /// yolculuk. Ortak oturum verildiğinde ise oyun, süren bir yolculuğun
  /// içine girer.
  final JourneySession _session;

  /// Oturumu bu oyun mu kurdu?
  ///
  /// Kurduysa yolculuk tek oyunluktur: yeniden başlatmak yolculuğu da
  /// sıfırlar, oyun bitince skor oyun bazlı rekora yazılır. Ortak bir
  /// oturuma bağlandıysa ikisini de yapmaz — yolculuk oyundan bağımsız
  /// sürer ve rekoru [JourneyController] yazar.
  final bool _ownsSession;

  /// Oyunun yarım kalan durumunu yolculuk kaydına yazan geri çağrı.
  ///
  /// Kayıt artık yolculuğun: puan, süre ve durak zarfta duruyor. Oyunun
  /// kendi durumu (Blok Metro'nun tahtası gibi) oraya bir metin olarak
  /// iliştiriliyor. `null` yük, "bu oyun bitti, sürdürülecek bir şey yok"
  /// demek.
  ///
  /// Tüm oyunlar kullanmak zorunda değil: gerçek zamanlı oyunlar zaten
  /// sıfırdan başlıyor, yolculuk puanı ve süresi onlar için yeterli.
  final void Function(String gameId, String? payload)? onGamePayload;

  JourneySession get journeySession => _session;

  /// Bu oyunun **bu yolculukta** kazandırdığı puan.
  ///
  /// [score] yolculuğun toplamı; oyuncu ikinci oyuna geçtiğinde HUD'ın
  /// neden yüksek bir sayıdan başladığını ancak bu ayrım açıklıyor.
  int get scoreThisGame => _session.scoreOf(gameId);

  /// Yolculuk başka oyunlarla paylaşılıyor mu?
  ///
  /// Paylaşılıyorsa bu oyunun bitmesi yolculuğu bitirmez: oyuncu puanını ve
  /// kalan süresini koruyarak başka bir oyuna geçebilir.
  bool get sharesJourney => !_ownsSession;

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

  GameStatus _status = GameStatus.ready;
  bool _scoreSaved = false;

  Timer? _timer;

  // --- JourneyRun: yolculuk yarısı oturuma devredilir ---

  @override
  Journey get journey => _session.journey;

  @override
  GameStatus get status => _status;

  @override
  int get score => _session.score;

  @override
  int get recordToBeat => _session.recordToBeat;

  @override
  bool get recordBeaten => _session.recordBeaten;

  @override
  bool get isFirstRun => _session.isFirstRun;

  @override
  bool get isNewBest => _session.isNewBest;

  @override
  double get progress => _session.progress;

  @override
  double get recordProgress => _session.recordProgress;

  @override
  int get remainingSeconds => _session.remainingSeconds;

  @override
  bool get isSprint => _session.isSprint;

  @override
  int get lastStationBonus => _session.lastStationBonus;

  @override
  int get stationBonusPulse => _session.stationBonusPulse;

  @override
  int get stationPulse => _session.stationPulse;

  @override
  int get sprintPulse => _session.sprintPulse;

  /// Sprintin açılması için gereken en az durak sayısı.
  static const int sprintMinStops = JourneySession.sprintMinStops;

  /// Geçen süre (saniye). Gerçek zamanlı oyunlarda kesirli olabilir.
  ///
  /// Duraklatmada ilerlemez; ekranlar arka plan dokularını kaydırmak için
  /// de kullanır.
  double get elapsedSeconds => _session.elapsedSeconds;

  // --- Yaşam döngüsü ---

  @override
  void start() {
    if (_status == GameStatus.playing) return;
    _setStatus(GameStatus.playing);
    _startTimer();
    notifyListeners();
  }

  @override
  void pause() {
    if (_status != GameStatus.playing) return;
    _stopTimer();
    _setStatus(GameStatus.paused);
    onPause();
    notifyListeners();
  }

  @override
  void resume() {
    if (_status != GameStatus.paused) return;
    _setStatus(GameStatus.playing);
    _startTimer();
    onResume();
    notifyListeners();
  }

  @override
  void restart() {
    _stopTimer();
    _scoreSaved = false;
    // Ortak yolculukta yeniden başlatmak **yalnızca oyunu** sıfırlar: puan,
    // kalan süre ve geçilen duraklar yolculuğa ait, tek bir oyunun yeniden
    // başlaması onları silmez.
    if (_ownsSession) {
      _session.reset();
      _refreshRecord();
    }
    onRestart();
    start();
  }

  @override
  void abandon() {
    _stopTimer();
    if (_status.isFinished) return;
    _setStatus(GameStatus.abandoned);
    onAbandon();
    notifyListeners();
  }

  // --- Oyunun kullanacağı araçlar ---

  /// Oyunun **ham** puanını yolculuğa ekler; rekor geçildiyse `true` döner.
  ///
  /// Oyun kendi kurallarıyla hesapladığı sayıyı verir. Oyunlar arası tempo
  /// farkını kapatan ölçek ([GameScoreProfiles]) ve sprint çarpanı
  /// oturumda uygulanır; oyunların ikisini de bilmesi gerekmez.
  @protected
  bool addScore(int points) =>
      _session.addGameScore(gameId: gameId, raw: points);

  /// Geri alınan hamlenin puanını ve kazandırdığı saniyeyi geri verir.
  ///
  /// [points] **verilmiş** puandır (ölçek ve sprint uygulanmış hâli); geri
  /// alma, hamleden önceki toplamı hedefler.
  @protected
  void refundScore({required int points, double seconds = 0}) =>
      _session.refund(points: points, seconds: seconds, gameId: gameId);

  /// "Bu duraktan beri kayda değer bir şey yaptım" — durak bonusunun koşulu.
  ///
  /// Blok oyununda satır temizlemek, Ray Uçuşu'nda kapı geçmek gibi.
  ///
  /// Aynı zamanda yolculuk kazancının tetikleyicisi: oyun
  /// [journeySecondsPerGoodMove] tanımlamışsa tren o kadar hızlanır.
  @protected
  void markStationProgress() {
    _session.markStationProgress();
    rewardJourney(journeySecondsPerGoodMove);
  }

  /// Bir "iyi hamle"nin yolculuğa kattığı saniye.
  ///
  /// **İyi oyun treni hızlandırır.** Yolculuk hâlâ gerçek rotanın gerçek
  /// süresi kadar, ama iyi oynayan oyuncu daha erken varır.
  ///
  /// Varsayılan 0: kazanç açıkça açılmadan hiçbir oyunda çalışmaz. Değer
  /// oyunun kendi temposuna göre belirlenir — saniyede birkaç kapı geçilen
  /// gerçek zamanlı bir oyunla, hamlesi yedi saniyede bir gelen sıra
  /// tabanlı bir oyun aynı sayıyı kullanamaz.
  ///
  /// Blok Metro bu kancayı kullanmaz: onun kazancı temizlenen hat sayısına,
  /// combo'ya ve seriye göre değişiyor, tek bir sabite sığmıyor. Kendi
  /// hesabını yapıp [rewardJourney] çağırıyor.
  @protected
  double get journeySecondsPerGoodMove => 0;

  /// Yolculuğa saniye ekler.
  ///
  /// Saat **hemen** ilerletilmez, bir sonraki kareye yazılır. Gerçek zamanlı
  /// oyunlar bunu [onTick] içinden çağırıyor; oradan doğrudan [advance]
  /// çağırmak sonsuz özyinelemeye girerdi. Biriken saniye [advance] içinde,
  /// oyunun kendi karesi işlendikten hemen sonra saate ekleniyor; durak ve
  /// varış kontrolleri tek seferde, birleşmiş süreyle çalışıyor.
  @protected
  void rewardJourney(double seconds) => _session.rewardJourney(seconds);

  /// Durak bonusu hakkını geri alır (geri alınan bir hamle bonus vermemeli).
  @protected
  void revokeStationProgress(bool previous) =>
      _session.revokeStationProgress(previous);

  @protected
  bool get hasStationProgress => _session.hasStationProgress;

  /// Tren kaç durağı geçti.
  int get stationsPassed => _session.stationsPassed;

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
    _session.restore(
      score: score,
      elapsedSeconds: elapsedSeconds,
      stationsPassed: stationsPassed,
      recordBeaten: recordBeaten,
      stationProgress: stationProgress,
    );
  }

  /// Geçilecek rekoru doğrudan ayarlar.
  ///
  /// Kayıttan dönen oyun, kaydedildiği andaki rekoru taşır; depodaki değer
  /// bu arada yükselmiş olabilir. İkisinden **yüksek olan** hedeflenir.
  @protected
  void raiseRecordToBeat(int value) => _session.raiseRecordToBeat(value);

  /// Oyunun durumunu doğrudan ayarlar (kayıttan `paused` dönmek gibi).
  @protected
  void setStatus(GameStatus value) => _setStatus(value);

  /// Durumu hem oyunda hem oturumda günceller.
  ///
  /// Oturumun durumu, oyun ekranı olmadan çizilen ortak parçalar için
  /// gerekli: oyun seçim ekranındaki şerit treni durumu buradan okur.
  void _setStatus(GameStatus value) {
    _status = value;
    // Yolculuğun durumu oyunun durumu değildir: oyun bittiğinde (hamle
    // kalmadı, çarptın) yolculuk sürer, oyuncu başka bir oyuna geçip aynı
    // puandan devam eder. Yalnızca varış ikisini birden bitirir.
    if (_ownsSession ||
        value == GameStatus.arrived ||
        value == GameStatus.playing ||
        value == GameStatus.paused) {
      _session.setStatus(value);
    }
  }

  /// Oyun kendi kuralına takıldı: hamle kalmadı, çarpıştı, süre doldu…
  @protected
  void endGame() => _finish(GameStatus.gameOver);

  /// Rekor bu anda geçildiyse işaretler ve geçildiğini döner.
  @protected
  bool checkRecord() => _session.checkRecord();

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
    // Saati artık bu oyun sürüyor; yolculuğun kalp atışı geri çekilir,
    // yoksa süre iki kat hızlı akar.
    _session.attachDriver(this);
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
    _session.detachDriver(this);
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

    _session.addElapsed(dt);
    // Bu saniyeler bu oyunda geçti: puanın yanında süre de dursun ki
    // "hangi oyun ne kazandırdı" sorusu tek sayıya bakarak yanıtlanmasın.
    _session.creditPlaySeconds(gameId, dt);
    onTick(dt);
    if (_status != GameStatus.playing) return; // oyun bu karede bitmiş olabilir

    // Bekleyen kazanç saniyeleri, durak ve varış kontrolünden **önce**
    // yazılır ki kazanç bir durağı geçirebilsin.
    final arrived = _session.settle();
    if (arrived) {
      _finish(GameStatus.arrived);
      return;
    }
    notifyListeners();
  }

  /// Testte yolculuğu elle ilerletmek için.
  @visibleForTesting
  void debugAdvance(double dt) => advance(dt);

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
    if (stored != null) _session.raiseRecordToBeat(stored);
  }

  void _finish(GameStatus status) {
    _stopTimer();
    _setStatus(status);
    onFinish(status);
    notifyListeners();
    unawaited(_persistScore());
  }

  Future<void> _persistScore() async {
    // Ortak yolculukta rekoru yolculuk yazar; oyun kendi başına yazsaydı
    // aynı rotaya iki farklı ölçüden iki rekor girerdi.
    if (!_ownsSession) return;
    final target = store;
    if (target == null || _scoreSaved) return;
    final isNewBest = await target.submitGameRouteScore(
      gameId: gameId,
      originId: journey.origin.id,
      destinationId: journey.destination.id,
      score: score,
    );
    _session.markNewBest(isNewBest);
    _scoreSaved = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
