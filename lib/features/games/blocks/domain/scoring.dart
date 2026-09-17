import 'package:flutter/foundation.dart';

import 'clear_result.dart';

/// Skorlama ve yolculuk kazancı sabitleri — dengeleme tek yerden yapılır.
///
/// Oyun kodunda çıplak sayı yoktur: bir değeri değiştirmek için yalnızca bu
/// sınıfa bakmak yeter.
class ScoreRules {
  const ScoreRules._();

  // --- Yerleştirme ve line ---

  /// Yerleştirilen her hücre.
  static const int perPlacedCell = 1;

  /// Temizlenen her satır.
  static const int perClearedRow = 10;

  /// Temizlenen her sütun.
  static const int perClearedColumn = 10;

  /// Aynı hamlede 2 line temizlenirse ek puan.
  static const int doubleLineBonus = 30;

  /// Aynı hamlede 3 veya daha fazla line temizlenirse ek puan.
  static const int tripleLineBonus = 60;

  // --- Combo ---

  /// Combo sönmeden önce izin verilen temizlemeyen hamle sayısı.
  ///
  /// 0 olsaydı eski davranışa dönerdi: temizlemeyen tek hamle combo'yu
  /// keser. 8x8 tahtada bir satırı tamamlamak çoğu zaman önce bir hazırlık
  /// parçası ister; pay olmadan combo oyuncunun becerisini değil şansını
  /// ölçüyordu.
  static const int comboGraceMoves = 2;

  /// Line puanına uygulanan combo çarpanının tavanı.
  ///
  /// Hazırlık payı geldiği için combo artık uzun sürebiliyor; çarpan
  /// sınırsız olsaydı tek bir uzun seri bütün rotayı anlamsızlaştırırdı.
  static const int comboMaxMultiplier = 6;

  // --- Streak ---

  /// Her streak seviyesi için line puanına eklenen sabit bonus.
  static const int streakBonusPerLevel = 5;

  /// Bonusun sayıldığı en yüksek streak seviyesi.
  static const int streakMaxLevel = 10;

  // --- Durak ve sprint ---

  /// Tren bir durağı geçerken, o duraktan beri en az bir line temizlendiyse
  /// verilen bonus. Yolculuğa ritim verir: "bir sonraki durağa kadar bir
  /// line çıkarmalıyım".
  static const int stationBonus = 25;

  /// Yolculuğun son diliminde puanlar bu katsayıyla çarpılır.
  static const int sprintMultiplier = 2;

  /// Sprintin başladığı ilerleme oranı (yolculuğun son %15'i).
  static const double sprintStartsAt = 0.85;
}

/// İyi oyunun yolculuğa kattığı saniye.
///
/// Ürünün vaadi değişmedi: yolculuk hâlâ gerçek rotanın gerçek süresi kadar
/// ve tek final varış. Değişen şu — **iyi oynayan oyuncu daha erken varır.**
/// Temizlik, combo ve streak trenin hızını artırır; kötü oynayan yolculuğu
/// tahmini süresinde tamamlar. Böylece puzzle performansı ilerlemeyi
/// besler ama zaman modeli yerinde kalır.
///
/// Değerler bilinçli olarak küçük: bir hamlenin kazancı saniyelerle
/// ölçülür, dakikalarla değil. Kazanç aynı zamanda durak geçişlerini de
/// hızlandırdığı için (durakta kalabalık satırlar boşalıyor) etkisi
/// bileşiktir; `test/balance_report_test.dart` ölçümü buna göre yapılır.
class JourneyRules {
  const JourneyRules._();

  /// Kademe başına temel saniye kazancı.
  static const Map<ClearTier, int> secondsPerTier = <ClearTier, int>{
    ClearTier.none: 0,
    ClearTier.single: 6,
    ClearTier.double: 12,
    ClearTier.triple: 20,
    ClearTier.mega: 30,
  };

  /// Combo bonusunun başladığı combo değeri.
  static const int comboBonusStartsAt = 3;

  /// Combo bonusunun tavanı (saniye).
  static const int comboBonusCap = 14;

  /// Kaç streak seviyesi bir saniye eder.
  static const int streakLevelsPerSecond = 4;

  /// Streak bonusunun tavanı (saniye).
  static const int streakBonusCap = 10;

  /// Bir hamlenin yolculuğa katacağı toplam saniye.
  ///
  /// [combo] ve [streak] hamle **sonrası** değerlerdir.
  static int secondsFor({
    required ClearTier tier,
    required int combo,
    required int streak,
  }) {
    if (!tier.isClear) return 0;

    final base = secondsPerTier[tier] ?? 0;

    var comboBonus = 0;
    if (combo >= comboBonusStartsAt) {
      comboBonus = combo - comboBonusStartsAt + 1;
      if (comboBonus > comboBonusCap) comboBonus = comboBonusCap;
    }

    var streakBonus = streak ~/ streakLevelsPerSecond;
    if (streakBonus > streakBonusCap) streakBonus = streakBonusCap;

    return base + comboBonus + streakBonus;
  }
}

/// Bir hamlenin skor sonucu ve dökümü.
///
/// Döküm ayrı alanlarda tutulur: hata ayıklama günlüğü ve dengeleme, tek
/// bir toplam sayıdan hangi kuralın ne kadar katkı verdiğini çıkaramaz.
@immutable
class ScoreResult {
  const ScoreResult({
    required this.points,
    required this.combo,
    required this.streak,
    required this.linesCleared,
    required this.multiplier,
    required this.placementPoints,
    required this.linePoints,
    required this.comboBonus,
    required this.streakBonus,
  });

  /// Bu hamlede kazanılan toplam puan.
  final int points;

  /// Hamle sonrası combo değeri (girdiyle aynıdır, günlük için taşınır).
  final int combo;

  /// Hamle sonrası streak değeri.
  final int streak;

  /// Bu hamlede temizlenen toplam line sayısı (satır + sütun).
  final int linesCleared;

  /// Line puanına uygulanan combo çarpanı.
  final int multiplier;

  /// Yerleştirilen hücrelerden gelen puan.
  final int placementPoints;

  /// Line ve çoklu temizlik bonusu (çarpan uygulanmadan önce).
  final int linePoints;

  /// Combo çarpanının getirdiği fazladan puan.
  final int comboBonus;

  /// Streak'in getirdiği fazladan puan.
  final int streakBonus;

  ClearTier get tier => ClearTier.of(linesCleared);

  @override
  String toString() =>
      'ScoreResult(+$points, combo $combo, streak $streak, '
      '$linesCleared line, x$multiplier)';
}

/// Bir hamlenin puanını hesaplar.
///
/// Kurallar:
/// - yerleştirilen her hücre +1
/// - temizlenen her satır +10, her sütun +10
/// - aynı hamlede 2 line +30, 3+ line +60 bonus
/// - **line puanı** combo ile çarpılır (ilk temizlik x1, ikinci ardışık
///   x2 …), çarpan [ScoreRules.comboMaxMultiplier] ile sınırlıdır
/// - streak her seviyesi için sabit bonus ekler, yalnızca temizleyen
///   hamlede
/// - [isSprint] ise (yolculuğun son dilimi) toplam puan iki katına çıkar
///
/// Yerleştirme puanı (hücre başına) combo'dan etkilenmez.
///
/// **Combo ve streak burada ilerletilmez.** Bu fonksiyon saf bir
/// hesaplayıcıdır; sıra takibi `ComboState` ve `StreakState` içindedir.
/// [combo] ve [streak] hamle **sonrası** değerler olarak verilir.
ScoreResult calculateScore({
  required int placedCells,
  required int clearedRows,
  required int clearedColumns,
  required int combo,
  int streak = 0,
  bool isSprint = false,
}) {
  assert(placedCells >= 0);
  assert(clearedRows >= 0 && clearedColumns >= 0);
  assert(combo >= 0);
  assert(streak >= 0);

  final placementPoints = placedCells * ScoreRules.perPlacedCell;
  final totalLines = clearedRows + clearedColumns;
  final sprint = isSprint ? ScoreRules.sprintMultiplier : 1;

  if (totalLines == 0) {
    return ScoreResult(
      points: placementPoints * sprint,
      combo: combo,
      streak: streak,
      linesCleared: 0,
      multiplier: 1,
      placementPoints: placementPoints * sprint,
      linePoints: 0,
      comboBonus: 0,
      streakBonus: 0,
    );
  }

  var linePoints =
      clearedRows * ScoreRules.perClearedRow +
      clearedColumns * ScoreRules.perClearedColumn;

  if (totalLines >= 3) {
    linePoints += ScoreRules.tripleLineBonus;
  } else if (totalLines == 2) {
    linePoints += ScoreRules.doubleLineBonus;
  }

  final multiplier = combo < 1
      ? 1
      : (combo > ScoreRules.comboMaxMultiplier
            ? ScoreRules.comboMaxMultiplier
            : combo);

  final comboBonus = linePoints * (multiplier - 1);

  final streakLevel = streak > ScoreRules.streakMaxLevel
      ? ScoreRules.streakMaxLevel
      : streak;
  final streakBonus = streakLevel * ScoreRules.streakBonusPerLevel;

  final total = placementPoints + linePoints + comboBonus + streakBonus;

  return ScoreResult(
    points: total * sprint,
    combo: combo,
    streak: streak,
    linesCleared: totalLines,
    multiplier: multiplier,
    placementPoints: placementPoints * sprint,
    linePoints: linePoints * sprint,
    comboBonus: comboBonus * sprint,
    streakBonus: streakBonus * sprint,
  );
}
