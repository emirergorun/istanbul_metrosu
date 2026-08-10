import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihaz üzerinde tutulan küçük kalıcı veriler.
///
/// Sadece **local**: en iyi skor ve haptic tercihi. Hesap, cloud save,
/// analytics veya network yoktur.
class LocalStore extends ChangeNotifier {
  LocalStore();

  static const String _bestScorePrefix = 'best_score_';
  static const String _overallBestKey = 'best_score_overall';
  static const String _hapticsKey = 'haptics_enabled';

  SharedPreferences? _prefs;
  bool _ready = false;
  bool _hapticsEnabled = true;

  bool get isReady => _ready;
  bool get hapticsEnabled => _hapticsEnabled;

  /// Storage kullanılamazsa (ör. test ortamı) uygulama yine çalışır;
  /// değerler sadece bellekte kalır.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _hapticsEnabled = _prefs?.getBool(_hapticsKey) ?? true;
    } catch (error, stack) {
      debugPrint('LocalStore init başarısız: $error\n$stack');
      _prefs = null;
    }
    _ready = true;
    notifyListeners();
  }

  int bestScoreFor(String profileId) =>
      _prefs?.getInt('$_bestScorePrefix$profileId') ?? 0;

  int get overallBest => _prefs?.getInt(_overallBestKey) ?? 0;

  /// Skoru kaydeder. Yeni rekorsa `true` döner.
  Future<bool> submitScore(String profileId, int score) async {
    if (score <= 0) return false;
    final key = '$_bestScorePrefix$profileId';
    final previous = bestScoreFor(profileId);
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

  Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    await _prefs?.setBool(_hapticsKey, value);
    notifyListeners();
  }
}
