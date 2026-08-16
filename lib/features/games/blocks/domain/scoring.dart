import 'package:flutter/foundation.dart';

/// Skorlama sabitleri — dengeleme tek yerden yapılır.
class ScoreRules {
  const ScoreRules._();

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

  /// Tren bir durağı geçerken, o duraktan beri en az bir line temizlendiyse
  /// verilen bonus. Yolculuğa ritim verir: "bir sonraki durağa kadar bir
  /// line çıkarmalıyım".
  static const int stationBonus = 25;

  /// Yolculuğun son diliminde puanlar bu katsayıyla çarpılır.
  static const int sprintMultiplier = 2;

  /// Sprintin başladığı ilerleme oranı (yolculuğun son %15'i).
  static const double sprintStartsAt = 0.85;
}

/// Bir hamlenin skor sonucu.
@immutable
class ScoreResult {
  const ScoreResult({
    required this.points,
    required this.combo,
    required this.linesCleared,
    required this.multiplier,
  });

  /// Bu hamlede kazanılan toplam puan.
  final int points;

  /// Hamle sonrası combo değeri (line temizlenmediyse 0).
  final int combo;

  /// Bu hamlede temizlenen toplam line sayısı (satır + sütun).
  final int linesCleared;

  /// Line puanına uygulanan çarpan.
  final int multiplier;

  @override
  String toString() =>
      'ScoreResult(+$points, combo $combo, $linesCleared line, x$multiplier)';
}

/// Bir hamlenin puanını hesaplar.
///
/// Kurallar:
/// - yerleştirilen her hücre +1
/// - temizlenen her satır +10, her sütun +10
/// - aynı hamlede 2 line +30, 3+ line +60 bonus
/// - line temizleyen ardışık hamleler combo'yu artırır ve **line puanı**
///   combo ile çarpılır (ilk temizlik x1, ikinci ardışık x2 ...)
/// - line temizlenmeyen hamle combo'yu sıfırlar
/// - [isSprint] ise (yolculuğun son dilimi) toplam puan iki katına çıkar
///
/// Yerleştirme puanı (hücre başına) combo'dan etkilenmez.
ScoreResult calculateScore({
  required int placedCells,
  required int clearedRows,
  required int clearedColumns,
  required int currentCombo,
  bool isSprint = false,
}) {
  assert(placedCells >= 0);
  assert(clearedRows >= 0 && clearedColumns >= 0);
  assert(currentCombo >= 0);

  final placementPoints = placedCells * ScoreRules.perPlacedCell;
  final totalLines = clearedRows + clearedColumns;

  final sprint = isSprint ? ScoreRules.sprintMultiplier : 1;

  if (totalLines == 0) {
    return ScoreResult(
      points: placementPoints * sprint,
      combo: 0,
      linesCleared: 0,
      multiplier: 1,
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

  final combo = currentCombo + 1;
  final multiplier = combo < 1 ? 1 : combo;

  return ScoreResult(
    points: (placementPoints + linePoints * multiplier) * sprint,
    combo: combo,
    linesCleared: totalLines,
    multiplier: multiplier,
  );
}
