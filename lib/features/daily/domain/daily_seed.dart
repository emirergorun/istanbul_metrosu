import 'day_stamp.dart';

/// Günden türeyen, kayıttan bağımsız sayı üreteci.
///
/// Günün yolculuğu ve görevleri **saklanmaz, hesaplanır**. Aynı tarih her
/// zaman aynı sonucu verir; uygulama silinip yeniden kurulsa, telefon
/// değişse, kayıt bozulsa bile o günün yolculuğu aynıdır. Saklanan tek şey
/// oyuncunun o gün ne yaptığıdır.
///
/// `dart:math`'ın [Random] sınıfı kullanılmadı: tohumdan üretilen dizinin
/// Dart sürümleri arasında aynı kalacağı garanti edilmiyor. Bir güncelleme
/// günün yolculuğunu gün ortasında değiştirebilirdi.
class DailySeed {
  DailySeed(int seed) : _state = seed == 0 ? 0x9E3779B9 : seed;

  /// Günün tarihinden tohum üretir — FNV-1a, 32 bit.
  factory DailySeed.forDay(DayStamp day, {String salt = ''}) {
    var hash = 0x811C9DC5;
    for (final unit in '$day$salt'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return DailySeed(hash);
  }

  int _state;

  /// Sıradaki sayı — xorshift32. Küçük, hızlı ve tamamen belirlenmiş.
  int _next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// `[0, bound)` aralığında bir sayı. [bound] pozitif olmalı.
  int nextInt(int bound) {
    assert(bound > 0, 'Üst sınır pozitif olmalı');
    return _next() % bound;
  }

  /// Listeden bir öge seçer. Liste boşsa `null`.
  T? pick<T>(List<T> items) =>
      items.isEmpty ? null : items[nextInt(items.length)];
}
