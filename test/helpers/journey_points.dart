import 'package:istanbul_metro_game/features/session/scoring/game_score_profile.dart';

/// Bir oyunun ham puanlarının ortak para birimindeki karşılığı.
///
/// Oyunlar kendi ham puanlarını hesaplar; yolculuk oturumu bunları
/// ölçekleyip ([GameScoreProfiles]) yolculuk skoruna yazar. Testlerin ham
/// sayıyı beklemesi bu yüzden yanlış olur — ölçek değişince hepsi kırılır.
/// Bu yardımcı huninin aynısını yapar: ölçek, kesir taşıması, yuvarlama.
///
/// [raws] tek tek verilmeli: kesir taşıması olay sırasına bağlı.
int journeyPoints(String gameId, List<int> raws) {
  final scale = GameScoreProfiles.scaleFor(gameId);
  var carry = 0.0;
  var total = 0;
  for (final raw in raws) {
    final scaled = raw * scale + carry;
    final whole = scaled.round();
    carry = scaled - whole;
    total += whole;
  }
  return total;
}
