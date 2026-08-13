import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihaz üzerinde tutulan küçük kalıcı veriler.
///
/// Sadece **local**: en iyi skor ve haptic tercihi. Hesap, cloud save,
/// analytics veya network yoktur.
class LocalStore extends ChangeNotifier {
  LocalStore();

  static const String _bestScorePrefix = 'best_route_';
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
        .where((k) => k.startsWith(_bestScorePrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    await prefs.remove(_overallBestKey);
    notifyListeners();
    return keys.length;
  }

  /// Kayıtlı rekoru olan rotalar: `{rota anahtarı: skor}`.
  Map<String, int> allRecords() {
    final prefs = _prefs;
    if (prefs == null) return const <String, int>{};
    return <String, int>{
      for (final key in prefs.getKeys())
        if (key.startsWith(_bestScorePrefix))
          key.substring(_bestScorePrefix.length): prefs.getInt(key) ?? 0,
    };
  }
}
