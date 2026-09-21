import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/daily/domain/day_stamp.dart';

/// Takvim günü aritmetiği.
///
/// Bu testlerin varlık sebebi: seri kuralı "dün" kavramına dayanıyor ve
/// süreye dayanan bir hesap yaz saati geçişinde, ay sonunda ve yıl sonunda
/// yanılıyor. Burada yanılmadığı gösteriliyor.
void main() {
  test('bugün cihazın saatinden okunur', () {
    withClock(Clock.fixed(DateTime(2026, 3, 14, 23, 59)), () {
      expect(DayStamp.today(), const DayStamp(2026, 3, 14));
    });
  });

  test('gün dönümü: bir dakika sonra yeni gün', () {
    withClock(Clock.fixed(DateTime(2026, 3, 15, 0, 1)), () {
      expect(DayStamp.today(), const DayStamp(2026, 3, 15));
    });
  });

  group('gün farkı', () {
    test('ardışık gün', () {
      expect(
        const DayStamp(2026, 9, 19).daysUntil(const DayStamp(2026, 9, 20)),
        1,
      );
    });

    test('ay sonu', () {
      expect(
        const DayStamp(2026, 1, 31).daysUntil(const DayStamp(2026, 2, 1)),
        1,
      );
    });

    test('yıl sonu', () {
      expect(
        const DayStamp(2025, 12, 31).daysUntil(const DayStamp(2026, 1, 1)),
        1,
      );
    });

    test('artık yıl 29 Şubat', () {
      expect(
        const DayStamp(2028, 2, 28).daysUntil(const DayStamp(2028, 2, 29)),
        1,
      );
      expect(
        const DayStamp(2028, 2, 29).daysUntil(const DayStamp(2028, 3, 1)),
        1,
      );
    });

    test('artık olmayan yüzyıl yılı: 1900 artık değil', () {
      expect(
        const DayStamp(1900, 2, 28).daysUntil(const DayStamp(1900, 3, 1)),
        1,
      );
    });

    test('artık olan dörtyüz yılı: 2000 artık', () {
      expect(
        const DayStamp(2000, 2, 28).daysUntil(const DayStamp(2000, 3, 1)),
        2,
      );
    });

    test('geçmiş gün negatif', () {
      expect(
        const DayStamp(2026, 9, 20).daysUntil(const DayStamp(2026, 9, 18)),
        -2,
      );
    });
  });

  test('yaz saati gecesi yine bir gündür', () {
    // Türkiye kalıcı yaz saatinde; yine de kural saate bakmadığı için
    // 23 saatlik bir gece de tam bir gün sayılmalı.
    final before = DayStamp.fromDateTime(DateTime(2026, 3, 28, 23, 30));
    final after = DayStamp.fromDateTime(DateTime(2026, 3, 29, 0, 30));
    expect(before.daysUntil(after), 1);
  });

  test('önceki ve sonraki gün', () {
    const day = DayStamp(2026, 1, 1);
    expect(day.previous, const DayStamp(2025, 12, 31));
    expect(day.next, const DayStamp(2026, 1, 2));
  });

  test('metin biçimi sıralanabilir', () {
    expect(const DayStamp(2026, 9, 7).toString(), '2026-09-07');
    expect(DayStamp.tryParse('2026-09-07'), const DayStamp(2026, 9, 7));
  });

  test('bozuk metin çözülmez', () {
    expect(DayStamp.tryParse(null), isNull);
    expect(DayStamp.tryParse(''), isNull);
    expect(DayStamp.tryParse('2026-13-01'), isNull);
    expect(DayStamp.tryParse('bugün'), isNull);
  });

  test('epochDay iki yönlü', () {
    for (final day in <DayStamp>[
      const DayStamp(1970, 1, 1),
      const DayStamp(2026, 9, 20),
      const DayStamp(2028, 2, 29),
      const DayStamp(1999, 12, 31),
    ]) {
      expect(DayStamp.fromEpochDay(day.epochDay), day);
    }
    expect(const DayStamp(1970, 1, 1).epochDay, 0);
  });
}
