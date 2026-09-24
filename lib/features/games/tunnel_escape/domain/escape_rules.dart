/// Tünele Kaç'ın puan ve yıldız kuralları — tek yerde.
///
/// Bulmaca ilerlemesi (yıldız, en iyi hamle) ile yolculuk puanı ayrı
/// kavramlar; ikisi de buradaki sayılardan türüyor ama birbirinin yerine
/// geçmiyor. Yıldız ustalığı ölçer, puan yolculuğun ortak kovasına yazılır.
abstract final class EscapeRules {
  /// Üç ve iki yıldız sınırları (en fazla hamle).
  ///
  /// **Tek formül değil, iki ölçü.** Üç yıldız en iyi çözümdür; çözüm
  /// uzadıkça bir-iki hamlelik pay tanınır, çünkü 25 hamlelik bir bölümde
  /// tek fazladan kaydırma ustalığı ölçmez, dikkati ölçer. İki yıldız payı
  /// hem çözüm uzunluğuna hem de **dallanmaya** (bir durumda kaç yasal
  /// hamle var) bağlı: çok seçenekli tahtada deneme-yanılma daha pahalı,
  /// pay daha geniş.
  static (int threeStar, int twoStar) parFor({
    required int optimal,
    required double branching,
  }) {
    final threeSlack = optimal >= 30
        ? 3
        : optimal >= 20
        ? 2
        : optimal >= 12
        ? 1
        : 0;
    final branchingSlack = (branching / 6).clamp(0.0, 3.0);
    final twoSlack = (optimal * 0.45 + branchingSlack).ceil().clamp(2, 14);
    final three = optimal + threeSlack;
    final two = optimal + (twoSlack > threeSlack ? twoSlack : threeSlack + 1);
    return (three, two);
  }

  /// En fazla yıldız.
  static const int maxStars = 3;

  /// Bitirilen bölümün yıldızı.
  ///
  /// İpucu alınan denemede üçüncü yıldız verilmez: ipucu en kısa çözümün
  /// sıradaki adımını gösterdiği için ipucuyla alınan üç yıldız ustalık
  /// değil, takip olurdu. Bölüm yine biter ve bir sonrakini açar.
  static int starsFor({
    required int moves,
    required int threeStarMoves,
    required int twoStarMoves,
    bool usedHint = false,
  }) {
    final stars = moves <= threeStarMoves
        ? 3
        : moves <= twoStarMoves
        ? 2
        : 1;
    return usedHint && stars > 2 ? 2 : stars;
  }

  /// "Kusursuz sefer" sayılacak en kısa bölüm.
  ///
  /// İki hamlelik öğretici bölümü en iyi çözümle bitirmek bir başarı değil.
  static const int perfectMinimumMoves = 10;

  /// Bölümün yolculuk puanı (ham, ölçek öncesi).
  ///
  /// Emekle orantılı: en kısa çözüm uzunluğu, bir bölümün ne kadar sürdüğünün
  /// en iyi tek göstergesi. Böylece kolay bölümü hızlı bitiren de zor
  /// bölümü yavaş bitiren de dakikada benzer puan alıyor; oyunlar arası
  /// ölçek (`GameScoreProfiles`) geri kalanını eşitliyor.
  static int basePoints(int optimal) => 12 + 8 * optimal;

  /// Yıldızın puan çarpanı — ustalık puana da yansısın.
  static double starMultiplier(int stars) => switch (stars) {
    >= 3 => 1.5,
    2 => 1.25,
    _ => 1.0,
  };

  static int fullPoints({required int optimal, required int stars}) =>
      (basePoints(optimal) * starMultiplier(stars)).round();

  /// Bu tamamlanışın yolculuğa kattığı ham puan.
  ///
  /// **Tekrar oynayarak puan kasılamaz.** Bölümler sonlu ve oyuncu çözümü
  /// ezberleyebilir; ezberlenmiş kolay bölümü tekrar tekrar bitirmek rota
  /// rekorunun kestirme yolu olurdu. Kural:
  ///
  /// * Bölüm **ilk kez** bitiyorsa tam puan.
  /// * Daha önce bitmişse yalnız yıldız **artışının** farkı.
  /// * Artış yoksa küçük bir tekrar payı — bir yolculukta bölüm başına
  ///   bir kez ([alreadyCreditedThisJourney]).
  static int journeyPoints({
    required int optimal,
    required int stars,
    required int previousBestStars,
    required bool alreadyCreditedThisJourney,
  }) {
    final full = fullPoints(optimal: optimal, stars: stars);
    if (previousBestStars <= 0) return full;
    final improvement =
        full - fullPoints(optimal: optimal, stars: previousBestStars);
    if (improvement > 0) return improvement;
    if (alreadyCreditedThisJourney) return 0;
    return (basePoints(optimal) * replayShare).round();
  }

  /// Tekrarın tam puana oranı.
  static const double replayShare = 0.2;
}
