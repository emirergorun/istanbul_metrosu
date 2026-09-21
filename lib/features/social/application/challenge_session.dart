import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../journey/models/journey.dart';
import '../domain/challenge.dart';

/// Kabul edilmiş meydan okumanın **oynanma anındaki** durumu.
///
/// Kısa ömürlü: kabul edildiğinde başlar, sonuç panelinden çıkılınca biter.
/// Kalıcı olan tek şey tamamlanmış maçların geçmişi ve o [SocialController]
/// içinde duruyor.
///
/// Bu sınıfın var oluş sebebi **sızıntıyı engellemek**. Meydan okuma modu,
/// oyunun rastgeleliğini tohumluyor; o tohumun Serbest Oyun'a karışması
/// demek, normal oyunların her seferinde aynı parçaları vermesi demek
/// olurdu. [randomFor] bu yüzden yalnızca rota **ve** oyun birebir
/// tuttuğunda tohum veriyor; başka her durumda `null` dönüyor ve oyun
/// kendi `Random()`'ını kuruyor.
class ChallengeSession extends ChangeNotifier {
  Challenge? _challenge;
  Journey? _journey;

  /// Şu anda oynanan meydan okuma. Yoksa `null` ve oyun normal moddadır.
  Challenge? get challenge => _challenge;

  Journey? get journey => _journey;

  bool get isActive => _challenge != null;

  /// Meydan okuma modunu başlatır.
  ///
  /// Yalnızca oyuncu **açıkça kabul ettikten sonra** çağrılır; kareyi
  /// okumak ya da önizlemeyi görmek oyun durumuna dokunmaz.
  void begin(Challenge challenge, Journey journey) {
    _challenge = challenge;
    _journey = journey;
    notifyListeners();
  }

  /// Meydan okuma modunu bitirir.
  ///
  /// Sonuç panelinden çıkarken ve oyun ekranı sökülürken çağrılır. İki kez
  /// çağrılması zararsız.
  void end() {
    if (_challenge == null) return;
    _challenge = null;
    _journey = null;
    notifyListeners();
  }

  /// Verilen oyun ve rota **bu** meydan okumaya mı ait?
  bool matches(String gameId, Journey journey) {
    final active = _challenge;
    if (active == null) return false;
    if (active.gameId != gameId) return false;
    return active.originId == journey.origin.canonicalId &&
        active.destinationId == journey.destination.canonicalId;
  }

  /// Bu koşunun rastgelelik kaynağı.
  ///
  /// Meydan okuma değilse `null` — oyun kendi tohumsuz `Random()`'ını
  /// kurar ve Serbest Oyun'un rastgeleliği hiç değişmez.
  Random? randomFor(String gameId, Journey journey) {
    if (!matches(gameId, journey)) return null;
    return Random(_challenge!.seed);
  }

  /// Bu koşuda geçilmesi gereken skor. Meydan okuma değilse `null`.
  int? targetFor(String gameId, Journey journey) =>
      matches(gameId, journey) ? _challenge!.targetScore : null;
}
