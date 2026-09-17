import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihaz üzerinde tutulan küçük kalıcı veriler.
///
/// Sadece **local**: en iyi skor ve haptic tercihi. Hesap, cloud save,
/// analytics veya network yoktur.
class LocalStore extends ChangeNotifier {
  LocalStore();

  static const String _bestScorePrefix = 'best_route_';
  static const String _bestGameScorePrefix = 'best_game_route_';

  /// Oyun kimliğiyle rotayı ayırır.
  ///
  /// Alt çizgi kullanılamaz: istasyon id'leri de alt çizgi içeriyor
  /// (`m2_taksim`), bu yüzden `<oyun>_<rota>` biçimi geri ayrıştırılamıyordu
  /// ve ayarlar ekranı bu kayıtları çizemeyip sessizce atlıyordu.
  static const String _gameRouteSeparator = '|';
  static const String _overallBestKey = 'best_score_overall';
  static const String _hapticsKey = 'haptics_enabled';
  static const String _soundKey = 'sound_enabled';
  static const String _musicKey = 'music_enabled';
  static const String _onboardingKey = 'onboarding_seen';
  static const String _savedGameKey = 'saved_game';
  static const String _lastOriginKey = 'last_route_origin';
  static const String _lastDestinationKey = 'last_route_destination';

  SharedPreferences? _prefs;
  bool _ready = false;
  bool _hapticsEnabled = true;

  /// Ses varsayılan olarak **kapalı**: kulaklıksız bir vagonda telefonun
  /// ötmesi istenmez, açmak kullanıcının tercihidir.
  bool _soundEnabled = false;

  /// Arka plan müziği de varsayılan olarak **kapalı** — efektlerden bile
  /// daha müdahaleci olduğu için aynı gerekçe fazlasıyla geçerli.
  bool _musicEnabled = false;

  bool get isReady => _ready;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;

  /// Storage kullanılamazsa (ör. test ortamı) uygulama yine çalışır;
  /// değerler sadece bellekte kalır.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _hapticsEnabled = _prefs?.getBool(_hapticsKey) ?? true;
      _soundEnabled = _prefs?.getBool(_soundKey) ?? false;
      _musicEnabled = _prefs?.getBool(_musicKey) ?? false;
    } catch (error, stack) {
      debugPrint('LocalStore init başarısız: $error\n$stack');
      _prefs = null;
    }
    _ready = true;
    notifyListeners();
  }

  /// Rekorlar **rota bazında** tutulur.
  ///
  /// Hat bazında olsaydı M4'te uçtan uca kurulan rekor, iki duraklık bir
  /// yolculukta kırılamaz olurdu. Yön rekoru bölmez: Taksim→Levent ile
  /// Levent→Taksim aynı süredir, aynı rekoru paylaşır.
  static String routeKey(String originId, String destinationId) {
    final pair = <String>[originId, destinationId]..sort();
    return '${pair[0]}__${pair[1]}';
  }

  int bestScoreForRoute(String originId, String destinationId) =>
      _prefs?.getInt('$_bestScorePrefix${routeKey(originId, destinationId)}') ??
      0;

  /// Rekorunu oyun adı taşımayan eski rota anahtarında tutan oyun.
  ///
  /// Blok Metro, oyun bazlı rekorlar gelmeden önce yazıldı ve hâlâ
  /// [submitRouteScore] ile kaydediyor. Okurken buraya yönlendirilmezse oyun
  /// seçim ekranı Blok Metro'da rekor olsa bile her rotada "ilk kez" diyordu.
  static const String legacyRouteGameId = 'blocks';

  int bestScoreForGameRoute({
    required String gameId,
    required String originId,
    required String destinationId,
  }) {
    if (gameId == legacyRouteGameId) {
      return bestScoreForRoute(originId, destinationId);
    }
    return _prefs?.getInt(
          '$_bestGameScorePrefix$gameId$_gameRouteSeparator'
          '${routeKey(originId, destinationId)}',
        ) ??
        0;
  }

  int get overallBest => _prefs?.getInt(_overallBestKey) ?? 0;

  /// Skoru rotaya kaydeder. Yeni rekorsa `true` döner.
  Future<bool> submitRouteScore({
    required String originId,
    required String destinationId,
    required int score,
  }) async {
    if (score <= 0) return false;
    final key = '$_bestScorePrefix${routeKey(originId, destinationId)}';
    final previous = bestScoreForRoute(originId, destinationId);
    final isNewBest = score > previous;

    if (isNewBest) {
      await _prefs?.setInt(key, score);
    }
    if (score > overallBest) {
      await _prefs?.setInt(_overallBestKey, score);
    }
    if (isNewBest || score > previous) notifyListeners();
    return isNewBest;
  }

  Future<bool> submitGameRouteScore({
    required String gameId,
    required String originId,
    required String destinationId,
    required int score,
  }) async {
    if (score <= 0) return false;
    final key =
        '$_bestGameScorePrefix$gameId$_gameRouteSeparator'
        '${routeKey(originId, destinationId)}';
    final previous = bestScoreForGameRoute(
      gameId: gameId,
      originId: originId,
      destinationId: destinationId,
    );
    final isNewBest = score > previous;

    if (isNewBest) {
      await _prefs?.setInt(key, score);
    }
    if (score > overallBest) {
      await _prefs?.setInt(_overallBestKey, score);
    }
    if (isNewBest || score > previous) notifyListeners();
    return isNewBest;
  }

  /// İlk açılış tanıtımı gösterildi mi?
  bool get hasSeenOnboarding => _prefs?.getBool(_onboardingKey) ?? false;

  Future<void> markOnboardingSeen() async {
    await _prefs?.setBool(_onboardingKey, true);
    notifyListeners();
  }

  /// Yarım kalan oyunun kaydı (JSON). Yoksa `null`.
  String? get savedGame => _prefs?.getString(_savedGameKey);

  bool get hasSavedGame => (savedGame?.isNotEmpty ?? false);

  Future<void> saveGame(String snapshot) async {
    await _prefs?.setString(_savedGameKey, snapshot);
    notifyListeners();
  }

  Future<void> clearSavedGame() async {
    if (_prefs?.containsKey(_savedGameKey) != true) return;
    await _prefs?.remove(_savedGameKey);
    notifyListeners();
  }

  /// Son oynanan rota — açılışta "tekrar oyna" için.
  ({String originId, String destinationId})? get lastRoute {
    final origin = _prefs?.getString(_lastOriginKey);
    final destination = _prefs?.getString(_lastDestinationKey);
    if (origin == null || destination == null) return null;
    return (originId: origin, destinationId: destination);
  }

  Future<void> rememberRoute(String originId, String destinationId) async {
    await _prefs?.setString(_lastOriginKey, originId);
    await _prefs?.setString(_lastDestinationKey, destinationId);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    await _prefs?.setBool(_hapticsKey, value);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    await _prefs?.setBool(_soundKey, value);
    notifyListeners();
  }

  Future<void> setMusicEnabled(bool value) async {
    _musicEnabled = value;
    await _prefs?.setBool(_musicKey, value);
    notifyListeners();
  }

  /// Tüm rota rekorlarını siler. Yanlışlıkla kurulan yüksek bir rekor bir
  /// rotayı oynanamaz hâle getirebiliyor; ayarlardan sıfırlanabilmeli.
  Future<int> clearRecords() async {
    final prefs = _prefs;
    if (prefs == null) return 0;
    final keys = prefs
        .getKeys()
        .where(
          (k) =>
              k.startsWith(_bestScorePrefix) ||
              k.startsWith(_bestGameScorePrefix),
        )
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    await prefs.remove(_overallBestKey);
    notifyListeners();
    return keys.length;
  }

  /// Kayıtlı bütün rekorlar.
  ///
  /// Ham anahtar yerine çözülmüş kayıt döner: arayüzün anahtar biçimini
  /// bilmesi gerekmez.
  /// Rotadaki en yüksek rekor ve hangi oyunda kurulduğu; yön fark etmez.
  ///
  /// Oyun henüz seçilmemiş ekranlar (rota planlayıcı, açılıştaki son rota)
  /// rekoru oyun adıyla birlikte gösterir; farklı oyunların puanları
  /// birbiriyle karşılaştırılamaz. Rekor yoksa `null`.
  ///
  /// Dönen kaydın [RouteRecord.gameId] değeri hiçbir zaman `null` değildir:
  /// eski rota anahtarındaki kayıt [legacyRouteGameId] olarak döner.
  RouteRecord? bestRecordForRoute(String originId, String destinationId) {
    final key = routeKey(originId, destinationId);
    RouteRecord? best;
    for (final record in allRecords()) {
      if (routeKey(record.originId, record.destinationId) != key) continue;
      if (record.score <= 0) continue;
      if (best == null || record.score > best.score) best = record;
    }
    if (best == null) return null;
    return RouteRecord(
      gameId: best.gameId ?? legacyRouteGameId,
      originId: best.originId,
      destinationId: best.destinationId,
      score: best.score,
    );
  }

  List<RouteRecord> allRecords() {
    final prefs = _prefs;
    if (prefs == null) return const <RouteRecord>[];

    final records = <RouteRecord>[];
    for (final key in prefs.getKeys()) {
      // Sayı, anahtarın bir rekor anahtarı olduğu **doğrulandıktan sonra**
      // okunur. Önce okunuyordu ve `getInt` içeride `as int?` yaptığı için
      // sayı olmayan ilk tercihte (titreşim, ses, yarım kalan oyun) ayarlar
      // ekranı açılır açılmaz çöküyordu.
      if (key.startsWith(_bestGameScorePrefix)) {
        final score = prefs.getInt(key) ?? 0;
        final rest = key.substring(_bestGameScorePrefix.length);
        final split = rest.indexOf(_gameRouteSeparator);
        if (split <= 0) continue;
        final pair = rest.substring(split + 1).split('__');
        if (pair.length != 2) continue;
        records.add(
          RouteRecord(
            gameId: rest.substring(0, split),
            originId: pair[0],
            destinationId: pair[1],
            score: score,
          ),
        );
        continue;
      }

      if (key.startsWith(_bestScorePrefix)) {
        final pair = key.substring(_bestScorePrefix.length).split('__');
        if (pair.length != 2) continue;
        records.add(
          RouteRecord(
            originId: pair[0],
            destinationId: pair[1],
            score: prefs.getInt(key) ?? 0,
          ),
        );
      }
    }
    return records;
  }
}

/// Çözülmüş bir rekor kaydı.
///
/// Anahtar biçimi [LocalStore] içinde kalır; arayüz yalnızca bu tipi görür.
@immutable
class RouteRecord {
  const RouteRecord({
    required this.originId,
    required this.destinationId,
    required this.score,
    this.gameId,
  });

  /// Hangi oyunda kurulduğu. `null` ise oyun ayrımından önceki eski kayıt
  /// (Blok Metro).
  final String? gameId;

  final String originId;
  final String destinationId;
  final int score;
}
