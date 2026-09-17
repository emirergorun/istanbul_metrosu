/// Metro Bilgi'nin puan ve seri kuralları.
///
/// Hepsi tek yerde ve saf: denge ayarı yapmak için tek dosya okunur.
class QuizRules {
  const QuizRules._();

  /// Doğru cevabın ham puanı. Çarpan bunun üstüne biner.
  static const int basePoints = 10;

  /// Oyuncunun **yanlış cevap** hakkı. Dördüncü yanlışta yolculuk biter.
  ///
  /// Süre aşımı da bu hakkı yer: cevap vermemek bir cevaptır. Gerekçesi
  /// `MetroQuizController.onTick` içinde.
  ///
  /// Tek yanlışta bitirmek denenmedi bile: 32 dakikalık bir yolculukta
  /// varış sahnesini bir daha kimse göremezdi. Üç hak, hareket eden
  /// metroda yanlış dokunuşa yer bırakır ama dikkatsizliği de ödüllendirmez.
  static const int mistakeAllowance = 3;

  /// Tek soruya verilen süre. Yolculuk uzunluğundan **bağımsız**.
  ///
  /// Uzun yolculuğa daha zor koşul koymak bu projede bir kez denendi ve
  /// varış oranını sıfıra indirdi; aynı hatayı tekrarlamıyoruz.
  static const Duration answerTime = Duration(seconds: 12);

  /// Cevaptan sonra doğru şıkkın ekranda kaldığı süre.
  ///
  /// Yanlış yapan oyuncunun doğruyu **okuyabilmesi** gerekiyor; 900 ms
  /// bunun için kısaydı, hareket eden vagonda göz şıkka odaklanana kadar
  /// soru değişiyordu.
  static const Duration revealTime = Duration(milliseconds: 1200);

  /// Serinin çarpana dönüştüğü eşikler.
  ///
  /// 3 doğru → ×2, 6 → ×3, 10 → ×4. Tavan bilinçli: tavansız bırakılsaydı
  /// 20 doğru yapan biri tek soruda 200 puan alır, rekor tablosu tek bir
  /// şanslı seriye dönerdi.
  static const List<({int streak, int multiplier})> streakLadder =
      <({int streak, int multiplier})>[
        (streak: 10, multiplier: 4),
        (streak: 6, multiplier: 3),
        (streak: 3, multiplier: 2),
      ];

  /// Verilen seri uzunluğundaki çarpan.
  static int multiplierFor(int streak) {
    for (final step in streakLadder) {
      if (streak >= step.streak) return step.multiplier;
    }
    return 1;
  }

  /// Bu doğru cevabın kazandırdığı puan.
  ///
  /// [streak] **cevap sayıldıktan sonraki** seri uzunluğudur: üçüncü doğru
  /// cevap zaten ×2 kazanır, oyuncu çarpanı bir soru sonra değil, seriyi
  /// tamamladığı anda hisseder.
  static int pointsFor(int streak) => basePoints * multiplierFor(streak);

  /// Bir sonraki çarpana kaç doğru kaldı? Tavandaysa `null`.
  static int? answersToNextMultiplier(int streak) {
    final current = multiplierFor(streak);
    for (var i = streakLadder.length - 1; i >= 0; i--) {
      final step = streakLadder[i];
      if (step.multiplier > current) return step.streak - streak;
    }
    return null;
  }
}
