import 'trivia_category.dart';

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

  /// Tek soruya verilen taban süre. Yolculuk uzunluğundan **bağımsız**.
  ///
  /// Uzun yolculuğa daha zor koşul koymak bu projede bir kez denendi ve
  /// varış oranını sıfıra indirdi; aynı hatayı tekrarlamıyoruz.
  static const Duration answerTime = Duration(seconds: 12);

  /// Zor sorulara eklenen süre.
  ///
  /// Zorluk etiketi önce yalnızca havuzdan seçimi etkiliyordu; oyuncu
  /// açısından zor soru ile kolay soru arasında hiçbir fark yoktu. Üç
  /// saniye, dört şıkkı okuyup elemeye yetiyor ama düşünmeyi bedava
  /// yapmıyor.
  static const Duration hardQuestionBonus = Duration(seconds: 3);

  /// Verilen zorluktaki sorunun süresi.
  static Duration answerTimeFor(TriviaDifficulty difficulty) =>
      difficulty == TriviaDifficulty.hard
      ? answerTime + hardQuestionBonus
      : answerTime;

  /// Son saniyelerinde sayaç nabız atmaya başlar.
  ///
  /// Yalnız renk değiştirmesi yetmiyordu: hareket eden vagonda göz şıkta
  /// olduğu için çubuğun rengini kimse görmüyor. Hareket çevresel görüşle
  /// de fark edilir.
  static const double urgentSeconds = 3;

  /// Yolculuk başına verilen joker hakkı.
  ///
  /// İki yanlış şıkkı eler. Bir bilgi yarışmasının oyuncuya verdiği tek
  /// gerçek karar aracı: "bunu bilmiyorum ama yarısını eleyebilirim".
  /// Tek hak bilinçli — sınırsız olsaydı her zor soruda basılır ve zorluk
  /// diye bir şey kalmazdı.
  static const int jokerCount = 1;

  /// Jokerin eleyeceği yanlış şık sayısı.
  static const int jokerEliminates = 2;

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

  /// Hızlı cevabın kazandırdığı en fazla ek puan.
  ///
  /// Sayacın tamamını kullanmakla iki saniyede cevaplamak aynı puanı
  /// veriyordu; süre çubuğu ekranda duruyor ama hiçbir kararı
  /// etkilemiyordu. Bonus **çarpanla çarpılmaz**: seri zaten kendi
  /// ödülünü veriyor, ikisi çarpılınca tek bir hızlı seri rekor tablosunu
  /// ele geçiriyordu.
  static const int speedBonusMax = 6;

  /// Kalan süre oranına göre hız bonusu.
  ///
  /// [remainingRatio] 0-1 arası; sayacın ne kadarı kullanılmadan kaldı.
  /// Yarıdan azı kalmışsa bonus yok — ödül gerçekten hızlı olana.
  static int speedBonus(double remainingRatio) {
    if (remainingRatio <= 0.5) return 0;
    final scaled = (remainingRatio - 0.5) * 2;
    return (scaled * speedBonusMax).round();
  }

  /// Serinin joker kazandırdığı basamak.
  ///
  /// Seri şu ana kadar yalnızca çarpan veriyordu. Beş doğrulukta bir
  /// joker, seriyi korumayı ikinci bir hedef yapar ve zor soruya
  /// takılan oyuncuya çıkış verir.
  static const int jokerRewardStreak = 5;

  /// Bir yolculukta biriktirilebilecek en fazla joker.
  static const int maxJokers = 3;

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
