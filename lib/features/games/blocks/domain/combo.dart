import 'package:flutter/foundation.dart';

import 'scoring.dart';

/// Kısa vadeli combo durumu.
///
/// Combo, **art arda line temizleyen hamlelerdir**. Tek fark şu: arada
/// hazırlık hamlesine izin verilir. Eski kural katıydı — temizlemeyen tek
/// bir hamle combo'yu sıfırlıyordu — ve oyuncuyu cezalandırıyordu: 8x8
/// tahtada bir satırı tamamlamak çoğu zaman önce bir parça yerleştirmeyi
/// gerektirir. Hazırlık payı ([ScoreRules.comboGraceMoves]) combo'yu
/// "şansın yaver gitmesi" olmaktan çıkarıp planlanabilir bir şey yapar.
///
/// Immutable: her hamle yeni bir durum döndürür, böylece geri alma
/// combo'yu da eski hâline döndürebilir.
@immutable
class ComboState {
  const ComboState({
    this.value = 0,
    this.movesSinceLastClear = 0,
    this.best = 0,
  });

  /// Şu anki combo. 0 = combo yok.
  final int value;

  /// Son temizlikten beri yapılan temizlemeyen hamle sayısı.
  final int movesSinceLastClear;

  /// Bu oturumdaki en yüksek combo.
  final int best;

  bool get isActive => value > 0;

  /// Combo sönmeden önce kaç hazırlık hamlesi kaldı.
  int get graceLeft {
    if (!isActive) return 0;
    final left = ScoreRules.comboGraceMoves - movesSinceLastClear;
    return left < 0 ? 0 : left;
  }

  /// Bir hamleyi işler ve yeni durumu döner.
  ///
  /// - Temizleyen hamle combo'yu artırır ve hazırlık sayacını sıfırlar.
  /// - Temizlemeyen hamle sayacı artırır; pay aşılırsa combo sıfırlanır.
  ComboState register({required bool didClear}) {
    if (didClear) {
      final next = value + 1;
      return ComboState(
        value: next,
        movesSinceLastClear: 0,
        best: next > best ? next : best,
      );
    }

    if (!isActive) {
      // Combo zaten yok; sayaç tutmanın anlamı yok.
      return this;
    }

    final moves = movesSinceLastClear + 1;
    if (moves > ScoreRules.comboGraceMoves) {
      return ComboState(best: best);
    }
    return ComboState(value: value, movesSinceLastClear: moves, best: best);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComboState &&
          other.value == value &&
          other.movesSinceLastClear == movesSinceLastClear &&
          other.best == best);

  @override
  int get hashCode => Object.hash(value, movesSinceLastClear, best);

  @override
  String toString() =>
      'ComboState(x$value, $movesSinceLastClear hazırlık, en iyi $best)';
}
