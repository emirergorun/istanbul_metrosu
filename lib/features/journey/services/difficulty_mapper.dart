import '../models/difficulty_profile.dart';

/// Yolculuk süresi (dakika) -> zorluk profili.
///
/// Sınırlar `01 - MVP` tablosuyla birebir aynıdır:
/// <=5 mini, <=10 kısa, <=20 standart, <=35 uzun, 36+ maraton.
DifficultyProfile difficultyFor(int minutes) {
  if (minutes <= 5) return DifficultyProfiles.mini;
  if (minutes <= 10) return DifficultyProfiles.short;
  if (minutes <= 20) return DifficultyProfiles.standard;
  if (minutes <= 35) return DifficultyProfiles.long;
  return DifficultyProfiles.marathon;
}

// TODO(PROD): Bucket yerine sürekli ölçekleme:
//   targetScore = baseScore + (minutes * scorePerMinute) + difficultyBias
//   hardPieceProbability = min(maxHard, baseHard + minutes * slope)
// Bucket sınırlarında hissedilen sıçramayı yumuşatır.
