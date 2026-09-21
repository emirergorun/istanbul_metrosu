import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'day_stamp.dart';

/// Üst üste kaç gün günlük yolculuk tamamlandı.
///
/// **Uygulamayı açmak seriyi büyütmez.** Seri, oyuncunun o gün gerçekten
/// oynayıp bugünün yolculuğunu bitirdiğini söyler; açılışa bağlı bir seri
/// hiçbir şey ölçmez ve oyuncuyu her gün uygulamayı açıp kapatmaya iter.
///
/// Gün farkı takvim günü üzerinden hesaplanır; geçen saatle çalışan bir
/// kayıt yaz saati geçişinde ve dilim değişiminde yanılır.
@immutable
class StreakState {
  const StreakState({
    this.lastCompleted,
    this.length = 0,
    this.best = 0,
    this.totalDays = 0,
    this.graceUsed = false,
  });

  static const StreakState empty = StreakState();

  /// Günlük yolculuğun en son tamamlandığı gün. Hiç tamamlanmadıysa `null`.
  final DayStamp? lastCompleted;

  /// [lastCompleted] gününde ulaşılan seri uzunluğu.
  ///
  /// **Ham** değerdir: aradan günler geçmişse hâlâ eski sayıyı taşır.
  /// Oyuncuya gösterilecek olan [currentOn].
  final int length;

  /// Bugüne kadarki en uzun seri. Seri kırılsa da küçülmez.
  final int best;

  /// Ömür boyu tamamlanan gün sayısı. Seri kırılsa da küçülmez.
  ///
  /// Pasaportta "kaç gün geldin" sorusunun cevabı. Seriden ayrı bir ölçü:
  /// seri sürekliliği, bu sayı sadakati anlatıyor.
  final int totalDays;

  /// Bu seride bir gün affedildi mi?
  ///
  /// Her seri **bir** kaçırılmış gün hakkına sahip. Gündelik bir oyunda tek
  /// bir yoğun günün otuz günlük seriyi sıfırlaması, oyuncuyu geri getirmek
  /// yerine kaçırıyor. Hak seri kırıldığında tazelenir; iki gün üst üste
  /// kaçırmak seriyi yine de bitirir.
  final bool graceUsed;

  /// [today] gününde geçerli olan seri.
  ///
  /// Seri dün ya da bugün tamamlanmışsa yaşıyordur. Bir gün atlanmışsa ve
  /// af hakkı duruyorsa yine yaşıyordur. Daha eskiyse kırılmış demektir ve
  /// sıfır görünür — kayıttaki sayı silinmez, yalnızca artık bugünü
  /// anlatmaz.
  int currentOn(DayStamp today) {
    final last = lastCompleted;
    if (last == null) return 0;
    final gap = last.daysUntil(today);
    if (gap < 0) return length; // saat geri alınmış: kayda güven
    if (gap <= 1) return length;
    if (gap == 2 && !graceUsed) return length;
    return 0;
  }

  /// [today] için seri hâlâ yaşıyor mu?
  bool isAliveOn(DayStamp today) => currentOn(today) > 0;

  /// Bugün tamamlandı mı?
  bool isCompletedOn(DayStamp today) => lastCompleted == today;

  /// [today] gününde af hakkı yakıldı mı? (Bir gün kaçırılmış ama seri
  /// ayakta.) Arayüz bunu bir kez söylüyor.
  bool isGraceActiveOn(DayStamp today) {
    final last = lastCompleted;
    if (last == null || graceUsed) return false;
    return last.daysUntil(today) == 2;
  }

  /// Günlük yolculuğun [today] gününde tamamlandığını işler.
  ///
  /// Aynı gün ikinci kez çağrılmak **hiçbir şeyi değiştirmez**: seri günde
  /// bir kez büyür. Oyuncunun günün yolculuğunu üç kez oynaması seriyi üçe
  /// katlayamaz.
  StreakState completeOn(DayStamp today) {
    final last = lastCompleted;
    if (last == today) return this;

    final gap = last == null ? -1 : last.daysUntil(today);
    final continuous = gap == 1;
    // Bir gün atlanmış ve af hakkı duruyorsa seri sürer, hak yanar.
    final forgiven = gap == 2 && !graceUsed;
    final next = (continuous || forgiven) ? length + 1 : 1;

    return StreakState(
      lastCompleted: today,
      length: next,
      best: next > best ? next : best,
      totalDays: totalDays + 1,
      // Hak seri kırıldığında tazelenir; süren seride yakıldıysa yanık kalır.
      graceUsed: forgiven || (continuous && graceUsed),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'last': lastCompleted?.toString(),
    'length': length,
    'best': best,
    'total': totalDays,
    'grace': graceUsed,
  };

  String encode() => jsonEncode(toJson());

  /// Kaydı çözer. Bozuksa [empty] — seri kaybolur ama uygulama açılır.
  static StreakState decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return empty;
      final last = DayStamp.tryParse(map['last'] as String?);
      final length = map['length'];
      final best = map['best'];
      final total = map['total'];
      return StreakState(
        lastCompleted: last,
        // Tarihi olmayan bir seri uzunluğu anlamsız: hangi güne ait
        // olduğu bilinmeyen sayı ne büyütülebilir ne de kırılabilir.
        length: last == null || length is! int || length < 0 ? 0 : length,
        best: best is! int || best < 0 ? 0 : best,
        // Eski kayıtta yok: bir kez tamamlamış oyuncunun en az bir günü var.
        totalDays: total is int && total >= 0
            ? total
            : (last == null ? 0 : 1),
        graceUsed: map['grace'] == true,
      );
    } catch (error) {
      debugPrint('Seri kaydı okunamadı: $error');
      return empty;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreakState &&
          other.lastCompleted == lastCompleted &&
          other.length == length &&
          other.best == best &&
          other.totalDays == totalDays &&
          other.graceUsed == graceUsed);

  @override
  int get hashCode =>
      Object.hash(lastCompleted, length, best, totalDays, graceUsed);

  @override
  String toString() =>
      'StreakState($lastCompleted, $length, en iyi $best, '
      '$totalDays gün${graceUsed ? ', af yanmış' : ''})';
}
