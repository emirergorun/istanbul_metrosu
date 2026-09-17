import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';

/// Uzun vadeli seri durumu.
///
/// Streak, combo ile **aynı şey değildir**. Combo tek tek hamleleri ölçer ve
/// birkaç saniyede söner; streak bütün bir koşunun temposunu ölçer.
///
/// Kural: her tepsi (üç parça) içinde en az bir line temizlenirse streak
/// artar. Bir tepsi baştan sona hiç temizlik yapmadan biterse streak
/// sıfırlanır. Ölçü birimi tepsi olduğu için oyuncunun elindeki parçalara
/// değil, onları **nasıl kullandığına** bakar: kötü bir tepsi geldiğinde
/// hazırlık yapıp bir sonrakinde temizlemek streak'i korumaz — her tepsi
/// kendi hesabını verir.
///
/// Immutable: geri alma streak'i de eski hâline döndürebilsin diye.
@immutable
class StreakState {
  const StreakState({
    this.value = 0,
    this.best = 0,
    this.piecesInSet = 0,
    this.clearedInSet = false,
  });

  /// Şu anki streak — kaç tepsi üst üste temizlikle kapandı.
  final int value;

  /// Bu oturumdaki en yüksek streak.
  final int best;

  /// Açık tepside kaç parça yerleştirildi (0..[AppConstants.traySize]).
  final int piecesInSet;

  /// Açık tepside en az bir line temizlendi mi?
  final bool clearedInSet;

  /// Streak'in bu tepside hâlâ kurtarılabilir olduğu.
  bool get isSafe => clearedInSet;

  /// Tepsi kapanmadan önce kaç parça kaldı.
  int get piecesLeftInSet => AppConstants.traySize - piecesInSet;

  /// Bir parça yerleştirmesini işler ve yeni durumu döner.
  StreakState register({required bool didClear}) {
    final pieces = piecesInSet + 1;
    final cleared = clearedInSet || didClear;

    if (pieces < AppConstants.traySize) {
      return StreakState(
        value: value,
        best: best,
        piecesInSet: pieces,
        clearedInSet: cleared,
      );
    }

    // Tepsi kapandı: hesap görülür ve yeni tepsi temiz sayfayla başlar.
    final next = cleared ? value + 1 : 0;
    return StreakState(value: next, best: next > best ? next : best);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreakState &&
          other.value == value &&
          other.best == best &&
          other.piecesInSet == piecesInSet &&
          other.clearedInSet == clearedInSet);

  @override
  int get hashCode => Object.hash(value, best, piecesInSet, clearedInSet);

  @override
  String toString() =>
      'StreakState($value, en iyi $best, tepside $piecesInSet parça'
      '${clearedInSet ? ", temizlik var" : ""})';
}
