import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/player/domain/player_name.dart';

/// Cihaz üzerinde tutulan küçük kalıcı veriler.
///
/// Sadece **local**: en iyi skor ve haptic tercihi. Hesap, cloud save,
/// analytics veya network yoktur.
class LocalStore extends ChangeNotifier {
  LocalStore();

  static const String _bestScorePrefix = 'best_route_';
  static const String _bestGameScorePrefix = 'best_game_route_';

  /// Yolculuk rekoru: rotanın **tüm oyunlardan** toplanan en iyi puanı.
  ///
  /// Puan artık oyuna değil yolculuğa ait; oyuncu bir rotada oyun
  /// değiştirerek tek bir skor biriktiriyor. Oyun bazlı eski anahtarlar
  /// silinmiyor: yeni rekor yazılana kadar onların en yükseği devralınıyor
  /// (bkz. [bestJourneyScore]), böylece kimsenin emeği çöpe gitmiyor.
  static const String _bestJourneyPrefix = 'best_journey_';

  /// Oyun kimliğiyle rotayı ayırır.
  ///
  /// Alt çizgi kullanılamaz: istasyon id'leri de alt çizgi içeriyor
  /// (`m2_taksim`), bu yüzden `<oyun>_<rota>` biçimi geri ayrıştırılamıyordu
  /// ve ayarlar ekranı bu kayıtları çizemeyip sessizce atlıyordu.
  static const String _gameRouteSeparator = '|';
  static const String _overallBestKey = 'best_score_overall';

  // --- Koşu rekorları ---
  //
  // Skor "ne kadar iyi oynadım"ı ölçüyor; bunlar **nasıl** oynadığımı.
  // Aynı skora iki farklı yoldan varılabilir: uzun bir seriyle ya da çok
  // sayıda küçük temizlikle. Oyuncunun kendi tarzını görebilmesi için üçü
  // ayrı tutulur.
  //
  // Skor gibi rota bazında saklanırlar: iki duraklık bir yolculukta kurulan
  // combo ile uçtan uca bir yolculuğunki kıyaslanamaz.
  static const String _bestComboPrefix = 'best_combo_';
  static const String _bestStreakPrefix = 'best_streak_';
  static const String _bestStationsPrefix = 'best_stations_';
  static const String _hapticsKey = 'haptics_enabled';
  static const String _soundKey = 'sound_enabled';
  static const String _musicKey = 'music_enabled';
  static const String _onboardingKey = 'onboarding_seen';
  static const String _savedGameKey = 'saved_game';

  /// Yarım kalan **yolculuğun** zarfı (bkz. `JourneySave`).
  ///
  /// `saved_game` ondan önceki biçim: yalnızca Blok Metro'yu, yolculuk
  /// alanlarıyla birlikte tutuyordu. Bir sürüm boyunca silinmiyor; göç
  /// `JourneyController` içinde, zarf yoksa okunarak yapılıyor.
  static const String _savedJourneyKey = 'journey_save';
  static const String _lastOriginKey = 'last_route_origin';
  static const String _lastDestinationKey = 'last_route_destination';
  static const String _playerNameKey = 'player_name';
  static const String _playerTagKey = 'player_tag';
  static const String _playerNameLockedKey = 'player_name_locked';
  static const String _usageStatsKey = 'usage_stats';
  static const String _errorLogKey = 'error_log';
  static const String _statsEnabledKey = 'stats_enabled';

  SharedPreferences? _prefs;
  bool _ready = false;
  bool _hapticsEnabled = true;

  /// Ses efektleri varsayılan olarak **açık**.
  ///
  /// Eskiden kapalıydı; gerekçesi "kulaklıksız bir vagonda telefonun ötmesi
  /// istenmez" idi. Pratikte ters etki yaptı: oyun sessiz açılıyor, çoğu
  /// oyuncu ayarlara hiç girmediği için sesin var olduğunu bile fark
  /// etmiyordu. Telefonun kendi sessiz modu ve ses tuşları zaten bu işi
  /// görüyor; istemeyen ayarlardan kapatabilir.
  bool _soundEnabled = true;

  /// Arka plan müziği de varsayılan olarak **açık**.
  ///
  /// Efektlerle aynı gerekçe: ayarlara hiç girmeyen oyuncu, oyunun müziği
  /// olduğunu fark etmeden oynuyordu. Sessiz isteyen ayarlardan kapatır.
  bool _musicEnabled = true;

  /// Oyuncu adı — ilk açılışta sessizce atanır.
  ///
  /// Kurulum akışına "ad seç" adımı konmadı: oyuncu daha oyunu görmeden
  /// karar vermek zorunda kalıyor ve bu ilk deneyime sürtünme ekliyor.
  /// Ad zaten var, beğenmeyen ayarlardan değiştiriyor.
  String _playerName = '';
  String _playerTag = '';

  /// Ad bir kez onaylandıktan sonra kilitlenir.
  ///
  /// Ürün kararı: ad bir imza, takma ad değil. Her istediğinde
  /// değiştirilebilseydi paylaşılan sonuç kartındaki ad ile skor
  /// tablosundaki ad tutmazdı ve "bu rekoru kim kırdı" sorusunun
  /// cevabı oynak olurdu.
  ///
  /// Kilit **ilk seçimden sonra** iniyor, atamadan sonra değil: rastgele
  /// verilmiş bir adla ömür boyu yaşamak zorunda kalmak kötü bir
  /// karşılama olurdu. Oyuncu bir kez seçiyor, o seçim kalıcı.
  bool _playerNameLocked = false;

  bool get isReady => _ready;

  /// Oyuncunun görünen adı.
  String get playerName => _playerName;

  /// Aynı adı taşıyanları ayıran sonek. Ad değişse bile sabit kalır.
  String get playerTag => _playerTag;

  /// Ad onaylandı mı? Onaylandıysa bir daha değişmez.
  bool get isPlayerNameLocked => _playerNameLocked;

  /// Kullanım sayaçları tutulsun mu?
  ///
  /// Sayaçlar **cihazdan çıkmıyor**; bu anahtar oyuncuya kendi
  /// verisi üzerinde söz hakkı veriyor ve uzak gönderim eklendiği gün
  /// hazır duruyor. Varsayılan açık: hiçbir şey gönderilmediği için
  /// kapalı başlamasının bir karşılığı yok.
  bool _statsEnabled = true;
  bool get statsEnabled => _statsEnabled;

  /// Kullanım sayaçlarının ham kaydı.
  String? get usageStatsRaw => _prefs?.getString(_usageStatsKey);

  /// Hata kaydının ham hâli.
  String? get errorLogRaw => _prefs?.getString(_errorLogKey);

  Future<void> writeUsageStats(String raw) async {
    await _prefs?.setString(_usageStatsKey, raw);
  }

  Future<void> writeErrorLog(String raw) async {
    await _prefs?.setString(_errorLogKey, raw);
  }

  Future<void> setStatsEnabled(bool value) async {
    _statsEnabled = value;
    await _prefs?.setBool(_statsEnabledKey, value);
  }

  bool get hapticsEnabled => _hapticsEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;

  /// Storage kullanılamazsa (ör. test ortamı) uygulama yine çalışır;
  /// değerler sadece bellekte kalır.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _hapticsEnabled = _prefs?.getBool(_hapticsKey) ?? true;
      _soundEnabled = _prefs?.getBool(_soundKey) ?? true;
      _musicEnabled = _prefs?.getBool(_musicKey) ?? true;
      _statsEnabled = _prefs?.getBool(_statsEnabledKey) ?? true;
      _restorePlayerIdentity();
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

  /// Rotanın yolculuk rekoru.
  ///
  /// Henüz yolculuk rekoru yazılmamışsa, oyun bazlı eski rekorların en
  /// yükseği devralınır: puanlama değişti diye oyuncunun elindeki en iyi
  /// sonuç sıfırlanmasın.
  int bestJourneyScore(String originId, String destinationId) {
    final stored = _prefs?.getInt(
      '$_bestJourneyPrefix${routeKey(originId, destinationId)}',
    );
    if (stored != null) return stored;
    return bestRecordForRoute(originId, destinationId)?.score ?? 0;
  }

  /// Yolculuk puanını rotaya yazar. Yeni rekorsa `true` döner.
  Future<bool> submitJourneyScore({
    required String originId,
    required String destinationId,
    required int score,
  }) async {
    if (score <= 0) return false;
    final previous = bestJourneyScore(originId, destinationId);
    final isNewBest = score > previous;

    if (isNewBest) {
      await _prefs?.setInt(
        '$_bestJourneyPrefix${routeKey(originId, destinationId)}',
        score,
      );
    }
    if (score > overallBest) {
      await _prefs?.setInt(_overallBestKey, score);
    }
    notifyListeners();
    return isNewBest;
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

  String _runKey(
    String prefix,
    String gameId,
    String originId,
    String destinationId,
  ) =>
      '$prefix$gameId$_gameRouteSeparator'
      '${routeKey(originId, destinationId)}';

  /// Bu rotada bu oyunda kurulmuş en iyi combo.
  int bestComboForRoute({
    required String gameId,
    required String originId,
    required String destinationId,
  }) =>
      _prefs?.getInt(
        _runKey(_bestComboPrefix, gameId, originId, destinationId),
      ) ??
      0;

  /// Bu rotada bu oyunda kurulmuş en iyi seri.
  int bestStreakForRoute({
    required String gameId,
    required String originId,
    required String destinationId,
  }) =>
      _prefs?.getInt(
        _runKey(_bestStreakPrefix, gameId, originId, destinationId),
      ) ??
      0;

  /// Bu rotada tek koşuda geçilen en çok durak.
  int maxStationsForRoute({
    required String gameId,
    required String originId,
    required String destinationId,
  }) =>
      _prefs?.getInt(
        _runKey(_bestStationsPrefix, gameId, originId, destinationId),
      ) ??
      0;

  /// Bir koşunun combo / seri / durak rekorlarını kaydeder.
  ///
  /// Her biri bağımsız değerlendirilir: oyuncu düşük skorlu bir koşuda bile
  /// en iyi serisini kurmuş olabilir. Hangilerinin kırıldığı döner.
  Future<RunRecordResult> submitRunRecords({
    required String gameId,
    required String originId,
    required String destinationId,
    required int bestCombo,
    required int bestStreak,
    required int stationsPassed,
  }) async {
    Future<bool> put(String prefix, int value) async {
      if (value <= 0) return false;
      final key = _runKey(prefix, gameId, originId, destinationId);
      final previous = _prefs?.getInt(key) ?? 0;
      if (value <= previous) return false;
      await _prefs?.setInt(key, value);
      return true;
    }

    final result = RunRecordResult(
      combo: await put(_bestComboPrefix, bestCombo),
      streak: await put(_bestStreakPrefix, bestStreak),
      stations: await put(_bestStationsPrefix, stationsPassed),
    );
    if (result.any) notifyListeners();
    return result;
  }

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

  /// Yarım kalan yolculuğun kaydı (JSON). Yoksa `null`.
  String? get savedJourney => _prefs?.getString(_savedJourneyKey);

  bool get hasSavedJourney => (savedJourney?.isNotEmpty ?? false);

  Future<void> saveJourney(String envelope) async {
    await _prefs?.setString(_savedJourneyKey, envelope);
    notifyListeners();
  }

  /// Yolculuk kaydını siler — eski biçimdeki kayıt da gider, yoksa göç
  /// bir dahaki açılışta onu yeniden diriltir.
  Future<void> clearSavedJourney() async {
    final had = _prefs?.containsKey(_savedJourneyKey) == true;
    if (had) await _prefs?.remove(_savedJourneyKey);
    await clearSavedGame();
    if (had) notifyListeners();
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

  /// Adı ve soneki kayıttan okur; yoksa üretir.
  ///
  /// Kayıttaki ad sözlükten üretilmemişse atılır ve yenisi verilir: elle
  /// düzenlenmiş bir tercih dosyası uygulamaya rastgele metin sokamaz.
  void _restorePlayerIdentity() {
    final saved = _prefs?.getString(_playerNameKey);
    _playerName = (saved != null && PlayerName.isValid(saved))
        ? saved
        : PlayerName.random();
    _playerTag = _prefs?.getString(_playerTagKey) ?? PlayerName.discriminator();
    _playerNameLocked = _prefs?.getBool(_playerNameLockedKey) ?? false;
    if (saved != _playerName) {
      _prefs?.setString(_playerNameKey, _playerName);
    }
    if (_prefs?.getString(_playerTagKey) == null) {
      _prefs?.setString(_playerTagKey, _playerTag);
    }
  }

  /// Oyuncu adını **bir kez** belirler ve kilitler.
  ///
  /// Kilit inmişse ya da ad sözlük dışıysa `false` döner ve hiçbir şey
  /// değişmez.
  Future<bool> confirmPlayerName(String name) async {
    if (_playerNameLocked) return false;
    if (!PlayerName.isValid(name)) return false;
    _playerName = name;
    _playerNameLocked = true;
    await _prefs?.setString(_playerNameKey, name);
    await _prefs?.setBool(_playerNameLockedKey, true);
    return true;
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
              k.startsWith(_bestGameScorePrefix) ||
              k.startsWith(_bestJourneyPrefix) ||
              k.startsWith(_bestComboPrefix) ||
              k.startsWith(_bestStreakPrefix) ||
              k.startsWith(_bestStationsPrefix),
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

  /// Rota rekorları: **rota başına tek satır**, yolculuğun toplam puanı.
  ///
  /// Rekor artık oyunun değil yolculuğun: oyuncu Blok Metro'dan Hat
  /// Düşür'e geçse de aynı skora yazıyor. Eski oyun bazlı kayıtlar hâlâ
  /// diskte duruyor ve [bestJourneyScore] onları devralıyor; liste de o
  /// yüzden ikisinin birleşiminden kuruluyor — aynı rota iki kez
  /// görünmesin.
  List<RouteRecord> journeyRecords() {
    final prefs = _prefs;
    if (prefs == null) return const <RouteRecord>[];

    final routes = <String, ({String originId, String destinationId})>{};
    void remember(String originId, String destinationId) {
      routes[routeKey(originId, destinationId)] = (
        originId: originId,
        destinationId: destinationId,
      );
    }

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_bestJourneyPrefix)) continue;
      final pair = key.substring(_bestJourneyPrefix.length).split('__');
      if (pair.length != 2) continue;
      remember(pair[0], pair[1]);
    }
    for (final record in allRecords()) {
      if (record.score <= 0) continue;
      remember(record.originId, record.destinationId);
    }

    final records = <RouteRecord>[];
    for (final route in routes.values) {
      final score = bestJourneyScore(route.originId, route.destinationId);
      if (score <= 0) continue;
      records.add(
        RouteRecord(
          originId: route.originId,
          destinationId: route.destinationId,
          score: score,
        ),
      );
    }
    records.sort((a, b) => b.score.compareTo(a.score));
    return records;
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
      // Koşu rekorları skor değildir; rota rekor listesine girmemeliler.
      if (key.startsWith(_bestComboPrefix) ||
          key.startsWith(_bestStreakPrefix) ||
          key.startsWith(_bestStationsPrefix)) {
        continue;
      }

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

/// Bir koşuda hangi rekorların kırıldığı.
@immutable
class RunRecordResult {
  const RunRecordResult({
    required this.combo,
    required this.streak,
    required this.stations,
  });

  const RunRecordResult.none()
    : combo = false,
      streak = false,
      stations = false;

  final bool combo;
  final bool streak;
  final bool stations;

  bool get any => combo || streak || stations;
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
