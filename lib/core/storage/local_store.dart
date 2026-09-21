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
  static const String _lastOriginKey = 'last_route_origin';
  static const String _lastDestinationKey = 'last_route_destination';
  static const String _playerNameKey = 'player_name';
  static const String _playerTagKey = 'player_tag';
  static const String _playerNameLockedKey = 'player_name_locked';
  static const String _usageStatsKey = 'usage_stats';
  static const String _errorLogKey = 'error_log';
  static const String _statsEnabledKey = 'stats_enabled';
  static const String _discoveredStationsKey = 'discovered_stations';
  static const String _discoverySeenTotalKey = 'discovery_seen_total';
  static const String _dailyCountersKey = 'daily_counters';
  static const String _dailyStreakKey = 'daily_streak';
  static const String _achievementsKey = 'achievements_unlocked';
  static const String _playerStatsKey = 'player_stats';
  static const String _friendCodeKey = 'friend_code';
  static const String _friendsKey = 'friends_v1';
  static const String _challengeHistoryKey = 'challenge_history_v1';
  static const String _platformNameKey = 'platform_display_name';

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

  /// Bir oyunda, **herhangi bir rotada** kurulmuş en yüksek skor.
  ///
  /// Rekorlar rota bazında tutuluyor; "bu oyunda ne kadar iyisin" sorusunun
  /// cevabı ise rotadan bağımsız. Pasaport başarımı bunu okuyor. Ayrı bir
  /// sayaç tutulmuyor: kayıtlı rekorlar zaten bu bilginin kaynağı.
  int bestScoreForGame(String gameId) {
    var best = 0;
    for (final record in allRecords()) {
      final owner = record.gameId ?? legacyRouteGameId;
      if (owner != gameId) continue;
      if (record.score > best) best = record.score;
    }
    return best;
  }

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

  /// Keşfedilmiş fiziksel durak kimlikleri.
  ///
  /// Saklanan tek keşif verisi budur. Sayaç, yüzde ve "hat tamamlandı"
  /// bilgisi **türetilir**; yazılsalardı metro.json'a bir hat eklendiğinde
  /// kayıtlı yüzde yalan söylerdi.
  ///
  /// Okunamayan veya bozuk kayıt boş liste olarak döner — keşif kaybolur ama
  /// uygulama açılır ve başka hiçbir kayıt etkilenmez.
  Set<String> get discoveredStationIds {
    try {
      final raw = _prefs?.getStringList(_discoveredStationsKey);
      if (raw == null) return <String>{};
      return <String>{
        for (final id in raw)
          if (id.isNotEmpty) id,
      };
    } catch (error) {
      debugPrint('Keşif kaydı okunamadı: $error');
      return <String>{};
    }
  }

  /// Keşif kümesinin tamamını yazar.
  ///
  /// Ekleme değil değiştirme: küme bellekte tutulur, disk yalnızca onun
  /// kopyasıdır. Sıralı yazılır ki iki cihaz kaydı `diff`'lenebilsin.
  Future<void> saveDiscoveredStations(Set<String> ids) async {
    final sorted = ids.toList()..sort();
    await _prefs?.setStringList(_discoveredStationsKey, sorted);
    notifyListeners();
  }

  /// Oyuncunun keşif ekranında **en son gördüğü** toplam durak sayısı.
  ///
  /// Keşif durumu değil, arayüzün okunma durumu — `onboarding_seen` ile aynı
  /// kategoride. Tamamlanma hâlâ keşfedilen duraklardan türetiliyor; bu sayı
  /// yalnızca "ağ büyüdü" anını yakalamak için var.
  ///
  /// Gerekçesi: keşfi bitiren bir oyuncu, metro.json'a yeni bir hat
  /// eklendiğinde ekranı açtığında %100'ün sessizce %88'e düştüğünü görürdü.
  /// Türetilmiş durumun doğru davranışı bu, ama açıklaması olmadan hata
  /// gibi okunuyor.
  int get discoverySeenTotal => _prefs?.getInt(_discoverySeenTotalKey) ?? 0;

  Future<void> markDiscoveryTotalSeen(int total) async {
    if (total <= discoverySeenTotal) return;
    await _prefs?.setInt(_discoverySeenTotalKey, total);
  }

  /// Bugünün günlük sayaçları (JSON). Yoksa `null`.
  ///
  /// Günün **planı** saklanmaz: rota, oyun ve görevler takvim gününden
  /// yeniden üretilir. Burada duran tek şey oyuncunun o gün ne yaptığı.
  /// Kayıt kendi tarihini taşır; başka bir güne aitse okuyan taraf atar.
  String? get dailyCountersRaw => _prefs?.getString(_dailyCountersKey);

  Future<void> saveDailyCounters(String raw) async {
    await _prefs?.setString(_dailyCountersKey, raw);
    notifyListeners();
  }

  /// Seri kaydı (JSON): son tamamlanan gün, seri uzunluğu, en uzun seri.
  ///
  /// Günlük sayaçlardan ayrı tutulur çünkü ömrü farklı: sayaçlar her gece
  /// atılır, seri **günler boyunca** yaşar.
  String? get dailyStreakRaw => _prefs?.getString(_dailyStreakKey);

  Future<void> saveDailyStreak(String raw) async {
    await _prefs?.setString(_dailyStreakKey, raw);
    notifyListeners();
  }

  /// Açılmış başarımların kimlikleri.
  ///
  /// Yalnızca **açılma olayı** saklanır, ilerleme değil: "kaç durak
  /// keşfedildi" sorusunun tek doğru cevabı keşif kaydında duruyor ve
  /// ikinci bir sayaç zamanla ondan ayrı düşerdi.
  Set<String> get unlockedAchievementIds {
    try {
      final raw = _prefs?.getStringList(_achievementsKey);
      if (raw == null) return <String>{};
      return <String>{
        for (final id in raw)
          if (id.isNotEmpty) id,
      };
    } catch (error) {
      debugPrint('Başarım kaydı okunamadı: $error');
      return <String>{};
    }
  }

  Future<void> saveUnlockedAchievements(Set<String> ids) async {
    final sorted = ids.toList()..sort();
    await _prefs?.setStringList(_achievementsKey, sorted);
    notifyListeners();
  }

  /// Ömür boyu biriken oyunculuk kaydı (JSON).
  ///
  /// Yalnızca **türetilemeyen** iki şey: tamamlanan yolculuk sayısı ve
  /// bitirilen oyunlar. Keşif, hat ve seri bilgisi buraya kopyalanmaz.
  String? get playerStatsRaw => _prefs?.getString(_playerStatsKey);

  Future<void> savePlayerStats(String raw) async {
    await _prefs?.setString(_playerStatsKey, raw);
    notifyListeners();
  }

  /// Bu cihazın arkadaş kodu.
  ///
  /// Ömründe **bir kez** üretilir ve değişmez: kod paylaşıldıktan sonra
  /// değişirse karşı tarafın listesindeki kayıt sahipsiz kalır.
  String? get friendCode => _prefs?.getString(_friendCodeKey);

  Future<void> saveFriendCode(String code) async {
    await _prefs?.setString(_friendCodeKey, code);
  }

  /// Arkadaş listesi (JSON).
  ///
  /// Anahtar sürümlü (`_v1`): kayıt biçimi değişirse eski anahtar okunmaz
  /// ve bozuk veri yeni sürüme sızmaz.
  String? get friendsRaw => _prefs?.getString(_friendsKey);

  Future<void> saveFriends(String raw) async {
    await _prefs?.setString(_friendsKey, raw);
    notifyListeners();
  }

  /// Tamamlanmış meydan okumaların yerel geçmişi (JSON).
  String? get challengeHistoryRaw => _prefs?.getString(_challengeHistoryKey);

  Future<void> saveChallengeHistory(String raw) async {
    await _prefs?.setString(_challengeHistoryKey, raw);
    notifyListeners();
  }

  /// Platform oyun servisinden gelen görünen ad (Game Center takma adı).
  ///
  /// Saklanıyor çünkü oyun **tünelde** açılıyor: her açılışta Game Center'a
  /// bağlanmayı beklemek kimliği ağa bağlamak olurdu. Bir kez alınıyor,
  /// çevrimdışı oturumlarda da aynı ad görünüyor ve karekoda aynı ad
  /// giriyor. Bağlantı kaldırılırsa kayıt siliniyor ve yerel ada dönülüyor.
  String? get platformDisplayName => _prefs?.getString(_platformNameKey);

  Future<void> savePlatformDisplayName(String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs?.remove(_platformNameKey);
    } else {
      await _prefs?.setString(_platformNameKey, name);
    }
    notifyListeners();
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
