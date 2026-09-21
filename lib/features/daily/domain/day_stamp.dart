import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// Yerel takvim günü — saat, dilim ve süre taşımayan bir tarih.
///
/// Günlük yolculuk "24 saat önce" değil **dün** kavramına dayanır. Geçen
/// süreyle çalışan bir kural yaz saati geçişlerinde (23 ya da 25 saatlik
/// günler) ve dilim değiştiren bir yolcuda yanlış sonuç verir; oyuncunun
/// telefonunda gördüğü takvim günü ise her zaman tektir.
///
/// Gün farkı [DateTime.difference] ile değil **sivil takvim** formülüyle
/// hesaplanır. `DateTime` farkı süre döndürür ve yaz saati geçen bir gecede
/// 23 saat çıkar; `inDays` bunu 0 gün diye okur ve seri sessizce kırılırdı.
@immutable
class DayStamp implements Comparable<DayStamp> {
  const DayStamp(this.year, this.month, this.day);

  /// Cihazın yerel takvimindeki bugün.
  ///
  /// `DateTime.now()` yerine `clock`: testte `withClock` ile herhangi bir
  /// güne oturulabiliyor ve günlük mantık deterministik kalıyor.
  factory DayStamp.today() {
    final now = clock.now();
    return DayStamp(now.year, now.month, now.day);
  }

  factory DayStamp.fromDateTime(DateTime time) =>
      DayStamp(time.year, time.month, time.day);

  /// `yyyy-MM-dd` biçimindeki kaydı çözer. Bozuksa `null`.
  static DayStamp? tryParse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DayStamp(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  /// 1970-01-01'den beri geçen gün sayısı.
  ///
  /// Howard Hinnant'ın `days_from_civil` algoritması: artık yılları ve ay
  /// uzunluklarını tam olarak çözer, saat ve dilim hiç işin içine girmez.
  int get epochDay {
    final y = month <= 2 ? year - 1 : year;
    final era = (y >= 0 ? y : y - 399) ~/ 400;
    final yoe = y - era * 400; // [0, 399]
    final doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) ~/ 5 + day - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy; // [0, 146096]
    return era * 146097 + doe - 719468;
  }

  /// [epochDay]'den takvim gününe dönüş — `civil_from_days`.
  static DayStamp fromEpochDay(int epochDay) {
    final z = epochDay + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final doe = z - era * 146097; // [0, 146096]
    final yoe =
        (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365; // [0, 399]
    final y = yoe + era * 400;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100); // [0, 365]
    final mp = (5 * doy + 2) ~/ 153; // [0, 11]
    final d = doy - (153 * mp + 2) ~/ 5 + 1; // [1, 31]
    final m = mp + (mp < 10 ? 3 : -9); // [1, 12]
    return DayStamp(m <= 2 ? y + 1 : y, m, d);
  }

  DayStamp get previous => fromEpochDay(epochDay - 1);
  DayStamp get next => fromEpochDay(epochDay + 1);

  /// Bu günden [other] gününe kaç gün var? Geçmiş için negatif.
  int daysUntil(DayStamp other) => other.epochDay - epochDay;

  bool get isToday => this == DayStamp.today();

  @override
  int compareTo(DayStamp other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DayStamp &&
          other.year == year &&
          other.month == month &&
          other.day == day);

  @override
  int get hashCode => epochDay.hashCode;

  /// `yyyy-MM-dd`. Kayıt biçimi budur; sıralanabilir ve okunabilir.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
