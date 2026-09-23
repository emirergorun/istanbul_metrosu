import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/storage/local_store.dart';
import '../discovery/application/journey_discovery.dart';
import '../journey/models/journey.dart';
import '../journey/services/route_service.dart';
import 'journey_run.dart';
import 'run_report.dart';
import 'journey_save.dart';
import 'journey_session.dart';

/// Süren yolculuğu ekranlardan bağımsız yaşatan tutamak.
///
/// Oyun ekranı kapanır, oyun seçim ekranı açılır, oyuncu başlığa döner —
/// yolculuk hepsinin üstünde durur.
///
/// İki işi var:
///
/// 1. **Saati sürdürmek.** Bir oyun oynanırken treni o oyunun kare döngüsü
///    ilerletir; oyun yokken (oyun seçimi, başlık ekranı, duraklatma) buranın
///    saniyelik kalp atışı devralır. İkisi aynı anda ilerletmez.
/// 2. **Arka planı telafi etmek.** Uygulama arka plandayken zamanlayıcılar
///    kısılır; dönüşte aradaki gerçek süre bir kez yolculuğa yazılır.
///    Uygulama tamamen kapatılırsa bu telafi olmaz — kapalı geçen süre
///    yolculuğa yazılmaz.
/// 3. **Yolculuğu diske yazmak.** Uygulama öldürülse bile puan, kalan süre
///    ve oynanan oyunun durumu kaybolmaz ([JourneySave]).
class JourneyController extends ChangeNotifier {
  JourneyController({
    required this.store,
    required this.routes,
    this.discoveryFactory,
    this.reporter,
  });

  final LocalStore store;
  final RouteService routes;

  /// Yolculuk başlayınca açılan keşif defteri.
  ///
  /// Yolculuk oyun ekranından uzun yaşıyor: tren oyun seçim ekranında,
  /// başlık ekranında ve uygulama arka plandayken de yol alıyor. Oyun
  /// controller'ının kendi defteri yalnız oyun açıkken yazıyordu, bu yüzden
  /// o duraklar keşfedilmeden geçiliyordu. `null` ise keşif kapalıdır.
  final JourneyDiscovery Function(Journey journey)? discoveryFactory;

  /// Oyun açık değilken biten yolculuğu dinleyen taraf.
  ///
  /// Oyun açıkken raporu oyun controller'ı gönderiyor; ikisi birden
  /// göndermesin diye buradaki rapor yalnız yolculuğu bir oyun
  /// sürmüyorken varış olursa çıkar.
  final RunReporter? reporter;

  JourneyDiscovery? _discovery;

  /// Varış bir kez kapatıldı mı? Rekor iki kez yazılmamalı.
  bool _finalized = false;

  JourneySession? _session;
  Timer? _heartbeat;
  DateTime? _leftForeground;
  String? _activeGameId;
  String? _gamePayload;

  /// Kayıt kaç kalp atışında bir tazelenir.
  ///
  /// Her saniye yazmak gereksiz: kaybedilebilecek en fazla şey birkaç
  /// saniyelik yolculuk. Oyunun kendi durumu zaten hamle başına yazılıyor.
  static const int _saveEveryBeats = 5;
  int _beatsSinceSave = 0;

  /// Süren yolculuk; yoksa `null`.
  JourneySession? get session => _session;

  /// Yarım kalan yolculukta son oynanan oyun.
  String? get activeGameId => _activeGameId;

  /// Verilen oyunun yarım kalan durumu; yoksa `null`.
  ///
  /// Yalnızca **son oynanan** oyunun durumu saklanıyor: oyuncu oyun
  /// değiştirince öncekinin tahtası artık geçerli değil (puanı ve süresi
  /// yolculukta duruyor, tahtası değil).
  String? payloadFor(String gameId) =>
      _activeGameId == gameId ? _gamePayload : null;

  /// Oyunun yarım kalan durumunu yolculuk kaydına yazar.
  ///
  /// [payload] `null` ise oyun bitmiş demektir: yük düşer, yolculuk sürer.
  void setGamePayload(String gameId, String? payload) {
    _activeGameId = gameId;
    _gamePayload = payload;
    _persistSave();
  }

  /// Açılışta yarım kalan yolculuğu geri getirir.
  ///
  /// Kapalı geçen süre **yolculuğa yazılmaz**: tren, uygulama kapalıyken
  /// beklemiş sayılır (bkz. [JourneySave]).
  JourneySession? restore() {
    if (_session != null) return _session;
    final save = _readSave();
    if (save == null) return null;

    final journey = routes.estimate(save.originId, save.destinationId).journey;
    if (journey == null) {
      // Metro verisi değişmiş: kayıt artık okunamıyor.
      unawaited(store.clearSavedJourney());
      return null;
    }

    final session =
        JourneySession(journey: journey, recordToBeat: save.recordToBeat)
          ..raiseRecordToBeat(
            store.bestJourneyScore(save.originId, save.destinationId),
          );
    session.restore(
      score: save.score,
      elapsedSeconds: save.elapsedSeconds,
      stationsPassed: save.stationsPassed,
      recordBeaten: save.recordBeaten,
      scoreByGame: save.scoreByGame,
      secondsByGame: save.secondsByGame,
    );
    _activeGameId = save.activeGameId;
    _gamePayload = save.gamePayload;
    _session = session;
    _finalized = false;
    session.addListener(_onSessionChanged);
    _discovery = discoveryFactory?.call(journey);
    _syncDiscovery(session);

    if (session.remainingSeconds <= 0) {
      // Kayıt varış anında yazılmış olabilir; tören açılan ilk ekranda
      // oynar.
      _arrive(session);
    } else {
      session.setStatus(GameStatus.playing);
      _startHeartbeat();
    }
    notifyListeners();
    return session;
  }

  /// Zarfı, yoksa ortak yolculuktan önceki Blok Metro kaydını okur.
  JourneySave? _readSave() {
    final envelope = store.savedJourney;
    if (envelope != null && envelope.isNotEmpty) {
      final decoded = JourneySave.decode(envelope);
      if (decoded != null) return decoded;
    }
    final legacy = store.savedGame;
    if (legacy == null || legacy.isEmpty) return null;
    return JourneySave.fromLegacyGameSave(
      legacy,
      gameId: LocalStore.legacyRouteGameId,
    );
  }

  void _persistSave() {
    final session = _session;
    if (session == null) return;
    if (session.status == GameStatus.arrived) return;
    _beatsSinceSave = 0;
    unawaited(
      store.saveJourney(
        JourneySave(
          originId: session.journey.origin.id,
          destinationId: session.journey.destination.id,
          elapsedSeconds: session.elapsedSeconds,
          score: session.score,
          scoreByGame: session.scoreByGame,
          secondsByGame: session.secondsByGame,
          stationsPassed: session.stationsPassed,
          recordToBeat: session.recordToBeat,
          recordBeaten: session.recordBeaten,
          activeGameId: _activeGameId,
          gamePayload: _gamePayload,
          savedAt: clock.now(),
        ).encode(),
      ),
    );
  }

  /// Verilen rota için yolculuğu başlatır.
  ///
  /// Aynı rotada süren bir yolculuk varsa ona devam edilir — oyuncu oyun
  /// seçimine girip çıktığında yolculuk baştan başlamaz. Başka bir rota
  /// istendiğinde önceki yolculuk kapanır ve puanı rotasına yazılır.
  JourneySession start(Journey journey) {
    final current = _session;
    if (current != null) {
      final sameRoute =
          current.journey.origin.id == journey.origin.id &&
          current.journey.destination.id == journey.destination.id;
      if (sameRoute && current.status != GameStatus.arrived) return current;
      close();
    }

    final session = JourneySession(
      journey: journey,
      recordToBeat: store.bestJourneyScore(
        journey.origin.id,
        journey.destination.id,
      ),
    );
    session.setStatus(GameStatus.playing);
    _session = session;
    _finalized = false;
    session.addListener(_onSessionChanged);
    _discovery = discoveryFactory?.call(journey);
    _activeGameId = null;
    _gamePayload = null;
    _startHeartbeat();
    _persistSave();
    notifyListeners();
    return session;
  }

  /// Yolculuğu bitirir ve puanı rotanın rekoruna yazar.
  void close() {
    final session = _session;
    if (session == null) return;
    _heartbeat?.cancel();
    _heartbeat = null;
    session.removeListener(_onSessionChanged);
    _finalized = false;
    _session = null;
    _discovery = null;
    _activeGameId = null;
    _gamePayload = null;
    unawaited(store.clearSavedJourney());
    unawaited(_persist(session));
    notifyListeners();
  }

  /// Yolculuğun puanını rotanın rekoruna yazar.
  Future<void> _persist(JourneySession session) async {
    if (session.score <= 0) return;
    final isNewBest = await store.submitJourneyScore(
      originId: session.journey.origin.id,
      destinationId: session.journey.destination.id,
      score: session.score,
    );
    session.markNewBest(isNewBest);
  }

  /// Oturumun durumu değişti.
  ///
  /// Varış oyun oynanırken gelirse yolculuğu bitiren taraf oyun oluyor;
  /// tutamak bunu yalnız buradan duyar. Rekorun yazılması, kaydın düşmesi
  /// ve keşfin kapanması her iki yoldan da aynı yerde olsun diye.
  void _onSessionChanged() {
    final session = _session;
    if (session == null) return;
    if (session.status != GameStatus.arrived) return;
    _arrive(session);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => beat());
  }

  /// Oyun yokken treni ilerleten saniyelik atış.
  ///
  /// Bir oyun kendi kare döngüsüyle yolculuğu ilerletiyorsa burada hiçbir şey
  /// yapılmaz; yoksa saat burada akar. Testler bunu elle çağırabilir.
  @visibleForTesting
  void beat() {
    final session = _session;
    if (session == null) return;
    if (session.status == GameStatus.arrived) return;
    if (session.isDriven) return;

    session.addElapsed(1);
    final arrived = session.settle();
    _syncDiscovery(session);
    if (arrived) {
      _arrive(session);
      return;
    }
    session.publish();

    if (++_beatsSinceSave >= _saveEveryBeats) _persistSave();
  }

  void _arrive(JourneySession session) {
    if (_finalized) return;
    _finalized = true;
    session.setStatus(GameStatus.arrived);
    // Varan yolculuk yarım kalmış sayılmaz: kayıt düşer, puan rekora gider.
    unawaited(store.clearSavedJourney());
    unawaited(_persist(session));
    // Oyun açıkken varışı oyun controller'ı bildiriyor (keşif, günlük görev,
    // başarım). Oyun yokken — oyun seçiminde, başlık ekranında ya da arka
    // plandan dönüşte — o zincir hiç çalışmıyordu.
    _discovery?.reportArrival();
    if (session.runReportedByGame) return;
    final gameId = _activeGameId;
    // Hiç oyun oynanmadıysa bildirilecek koşu da yok: yolculuk tek başına
    // "oyun bitirdim" saymaz.
    if (gameId == null) return;
    reporter?.reportRun(
      RunReport(
        gameId: gameId,
        journey: session.journey,
        status: GameStatus.arrived,
        score: session.score,
        stationsPassed: session.stationsPassed,
      ),
    );
  }

  /// Oturumun durak sayacını keşif defterine aktarır.
  ///
  /// Yalnız **geçilmiş** durak bildirilir: rota seçmek ya da oyun seçim
  /// ekranını açmak keşif üretmez, bu kural
  /// `game_hub_discovery_safety_test` ile kilitli.
  void _syncDiscovery(JourneySession session) {
    if (session.stationsPassed < 1) return;
    _discovery?.reportReached(session.stationsPassed);
  }

  /// Uygulama arka plandan döndü: aradaki gerçek süre yolculuğa yazılır.
  void onForeground() {
    final session = _session;
    final left = _leftForeground;
    _leftForeground = null;
    if (session == null || left == null) return;
    if (session.status == GameStatus.arrived) return;

    // Metroda telefon cebe girince tren durmaz.
    final away = clock.now().difference(left).inMilliseconds / 1000;
    session.creditElapsed(away);
    final arrived = session.settle();
    _syncDiscovery(session);
    if (arrived) {
      _arrive(session);
    } else {
      session.publish();
    }
  }

  /// Uygulama arka plana alındı: dönüş anında telafi edebilmek için
  /// işaretle ve yolculuğu diske yaz — geri dönülmeyebilir.
  void onBackground() {
    _leftForeground ??= clock.now();
    _persistSave();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _session = null;
    super.dispose();
  }
}

/// [JourneyController]'ı kurup uygulama yaşam döngüsüne bağlayan sarmalayıcı.
///
/// `Navigator`'ın **üstünde** durur ([MetroGameApp]); hiçbir ekran değişimi
/// onu yeniden kurmaz.
class JourneyHost extends StatefulWidget {
  const JourneyHost({
    super.key,
    required this.store,
    required this.routes,
    required this.child,
    this.discoveryFactory,
    this.reporter,
  });

  final LocalStore store;
  final RouteService routes;

  /// Yolculuk için keşif defteri açan işlev; `null` ise keşif kapalı.
  final JourneyDiscovery Function(Journey journey)? discoveryFactory;

  /// Oyun açık değilken biten yolculuğu dinleyen taraf.
  final RunReporter? reporter;
  final Widget child;

  @override
  State<JourneyHost> createState() => _JourneyHostState();
}

class _JourneyHostState extends State<JourneyHost> with WidgetsBindingObserver {
  late final JourneyController _controller = JourneyController(
    store: widget.store,
    routes: widget.routes,
    discoveryFactory: widget.discoveryFactory,
    reporter: widget.reporter,
  )..addListener(_onChanged);

  void _onChanged() {
    if (!mounted) return;
    // Yolculuk build sırasında da başlayabilir (oyun seçim ekranı açılırken);
    // o anda `setState` çağırmak Flutter'ı kızdırır. Kare biterken yapılır.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Yarım kalan yolculuk varsa uygulama onunla açılır: başlık ekranındaki
    // kart canlı oturumu gösteriyor.
    _controller.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onForeground();
    } else {
      _controller.onBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return JourneyScope(
      controller: _controller,
      session: _controller.session,
      child: widget.child,
    );
  }
}

/// Süren yolculuğu widget ağacına taşır.
///
/// Bilinçli olarak düz bir [InheritedWidget]: yolculuk saniyede bir haber
/// veriyor ve `InheritedNotifier` olsaydı her atışta tüm ekran yeniden
/// kurulurdu. Saniyelik veriyi kullanan yapraklar oturuma kendileri abone
/// olur (`ListenableBuilder`), gerisi yalnızca yolculuk değişince yeniden
/// kurulur.
class JourneyScope extends InheritedWidget {
  const JourneyScope({
    super.key,
    required this.controller,
    required this.session,
    required super.child,
  });

  final JourneyController controller;
  final JourneySession? session;

  static JourneyController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<JourneyScope>();
    assert(scope != null, 'JourneyScope widget ağacında bulunamadı');
    return scope!.controller;
  }

  /// Yolculuk tutamağı; ağaçta yoksa `null`.
  ///
  /// Uygulamada her zaman var ([JourneyHost] `MaterialApp`'in üstünde), ama
  /// tek bir ekranı kuran testler onu kurmuyor: oyun ekranları yolculuk
  /// olmadan da çalışabilmeli — o zaman yolculuk tek oyunluk olur.
  static JourneyController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JourneyScope>()?.controller;

  /// Süren yolculuk; yoksa `null`.
  static JourneySession? sessionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JourneyScope>()?.session;

  /// Süren yolculuk — **yalnız aynı rotaysa**.
  ///
  /// Oyun ekranları açıldıkları rotayı biliyor; süren yolculuk başka bir
  /// rotaya aitse ona bağlanmak yanlış olur (puan ve kalan süre başka bir
  /// yolculuğun). Uygulamada oyun seçim ekranı rotayı zaten eşitliyor, bu
  /// yüzden burası bir emniyet kemeri: eşleşmezse oyun kendi tek oyunluk
  /// yolculuğunu kurar.
  static JourneySession? sessionFor(BuildContext context, Journey journey) {
    final session = sessionOf(context);
    if (session == null) return null;
    final same =
        session.journey.origin.id == journey.origin.id &&
        session.journey.destination.id == journey.destination.id;
    return same ? session : null;
  }

  @override
  bool updateShouldNotify(JourneyScope oldWidget) =>
      controller != oldWidget.controller || session != oldWidget.session;
}
