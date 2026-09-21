import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/daily/domain/day_stamp.dart';
import 'package:istanbul_metro_game/features/daily/domain/streak_state.dart';

/// Seri kuralı.
///
/// Ürün sözü şu: **uygulamayı açmak seriyi büyütmez**; seri ancak günün
/// yolculuğu tamamlanınca ilerler ve günde bir kez ilerler.
void main() {
  const monday = DayStamp(2026, 9, 14);
  const tuesday = DayStamp(2026, 9, 15);
  const wednesday = DayStamp(2026, 9, 16);
  const friday = DayStamp(2026, 9, 18);

  test('ilk tamamlama seriyi 1 yapar', () {
    final state = StreakState.empty.completeOn(monday);
    expect(state.currentOn(monday), 1);
    expect(state.best, 1);
  });

  test('ardışık gün seriyi büyütür', () {
    final state = StreakState.empty.completeOn(monday).completeOn(tuesday);
    expect(state.currentOn(tuesday), 2);
    expect(state.best, 2);
  });

  test('aynı gün ikinci tamamlama hiçbir şeyi değiştirmez', () {
    final once = StreakState.empty.completeOn(monday);
    final twice = once.completeOn(monday).completeOn(monday);
    expect(twice, once);
    expect(twice.currentOn(monday), 1);
  });

  test('atlanan gün seriyi baştan başlatır', () {
    // Pazartesi, salı, cuma: iki gün kaçırılmış, af yetmiyor.
    final state = StreakState.empty
        .completeOn(monday)
        .completeOn(tuesday)
        .completeOn(friday);
    expect(state.currentOn(friday), 1);
    // En uzun seri küçülmez.
    expect(state.best, 2);
  });

  test('birden çok gün atlandığında da seri 1 olur', () {
    // Pazartesi'den cumaya dört gün: af bir günü kapsıyor, dördünü değil.
    final state = StreakState.empty.completeOn(monday).completeOn(friday);
    expect(state.currentOn(friday), 1);
  });

  test('seri dün tamamlandıysa bugün hâlâ yaşıyor', () {
    final state = StreakState.empty.completeOn(monday).completeOn(tuesday);
    expect(state.currentOn(wednesday), 2);
    expect(state.isAliveOn(wednesday), isTrue);
    expect(state.isCompletedOn(wednesday), isFalse);
  });

  group('af hakkı', () {
    test('bir gün kaçırmak seriyi kırmaz', () {
      // Her seri bir kaçırılmış gün hakkına sahip: tek yoğun günün otuz
      // günlük seriyi sıfırlaması oyuncuyu geri getirmiyor, kaçırıyor.
      final state = StreakState.empty.completeOn(monday);
      expect(state.currentOn(wednesday), 1);
      expect(state.isAliveOn(wednesday), isTrue);
      expect(state.isGraceActiveOn(wednesday), isTrue);
    });

    test('affedilen gün seriyi sürdürür', () {
      final state = StreakState.empty
          .completeOn(monday)
          .completeOn(wednesday);
      expect(state.currentOn(wednesday), 2);
      expect(state.graceUsed, isTrue);
    });

    test('hak bir kez kullanılır', () {
      // Pazartesi, çarşamba (af), cuma: ikinci kaçırma affedilmiyor.
      final state = StreakState.empty
          .completeOn(monday)
          .completeOn(wednesday)
          .completeOn(friday);
      expect(state.currentOn(friday), 1);
      expect(state.best, 2);
    });

    test('iki gün üst üste kaçırmak seriyi bitirir', () {
      final state = StreakState.empty.completeOn(monday);
      // Pazartesi'den Perşembe: üç gün boşluk, af yetmiyor.
      expect(state.currentOn(const DayStamp(2026, 9, 17)), 0);
      expect(state.isAliveOn(const DayStamp(2026, 9, 17)), isFalse);
      // Kayıt silinmiyor; yalnızca bugünü anlatmıyor.
      expect(state.length, 1);
    });

    test('seri kırılınca hak tazelenir', () {
      final broken = StreakState.empty
          .completeOn(monday)
          .completeOn(wednesday)
          .completeOn(friday);
      expect(broken.graceUsed, isFalse);
    });
  });

  test('toplam gün seri kırılsa da artar', () {
    final state = StreakState.empty
        .completeOn(monday)
        .completeOn(friday)
        .completeOn(const DayStamp(2026, 9, 30));
    expect(state.totalDays, 3);
    expect(state.currentOn(const DayStamp(2026, 9, 30)), 1);
  });

  test('aynı gün ikinci tamamlama toplamı da artırmaz', () {
    final once = StreakState.empty.completeOn(monday);
    expect(once.completeOn(monday).totalDays, 1);
  });

  test('ay sınırı seriyi kırmaz', () {
    const lastOfMonth = DayStamp(2026, 1, 31);
    const firstOfNext = DayStamp(2026, 2, 1);
    final state = StreakState.empty
        .completeOn(lastOfMonth)
        .completeOn(firstOfNext);
    expect(state.currentOn(firstOfNext), 2);
  });

  test('yıl sınırı seriyi kırmaz', () {
    const lastOfYear = DayStamp(2025, 12, 31);
    const firstOfYear = DayStamp(2026, 1, 1);
    final state = StreakState.empty
        .completeOn(lastOfYear)
        .completeOn(firstOfYear);
    expect(state.currentOn(firstOfYear), 2);
  });

  test('kayıt gidip geliyor', () {
    final state = StreakState.empty.completeOn(monday).completeOn(tuesday);
    final restored = StreakState.decode(state.encode());
    expect(restored, state);
  });

  test('bozuk kayıt seriyi sıfırlar ama çökmez', () {
    expect(StreakState.decode('{bozuk'), StreakState.empty);
    expect(StreakState.decode(''), StreakState.empty);
    expect(StreakState.decode(null), StreakState.empty);
    // Tarihi olmayan uzunluk anlamsız: hangi güne ait olduğu bilinmiyor.
    expect(StreakState.decode('{"length":9,"best":9}').length, 0);
    // Toplam gün alanı olmayan **eski** kayıt: bir kez tamamlanmış sayılır.
    expect(
      StreakState.decode('{"last":"2026-09-14","length":1,"best":1}').totalDays,
      1,
    );
  });
}
