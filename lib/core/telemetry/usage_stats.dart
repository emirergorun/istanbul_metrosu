import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'analytics.dart';

/// Cihazda biriken kullanım sayaçları.
///
/// Denge ayarları bugüne kadar simülasyonla yapıldı: `balance_report_test`
/// içindeki yapay oyuncu hep en iyi hamleyi seçiyor. Gerçek oyuncu böyle
/// oynamıyor ve varış oranının gerçekte ne olduğunu kimse bilmiyor.
///
/// Bu sınıf o boşluğu **veri göndermeden** kapatıyor: sayaçlar cihazda
/// tutuluyor, oyuncu kendi istatistiğini ayarlarda görüyor, TestFlight
/// turunda ekran görüntüsü olarak paylaşabiliyor. Uzak gönderim
/// eklenecekse aynı sayaçlar kaynak olur.
class UsageStats implements Analytics {
  UsageStats({required this.load, required this.save});

  /// Kayıttan okunan ham JSON; yoksa `null`.
  final String? Function() load;

  /// Sayaçları kaydeder.
  final Future<void> Function(String raw) save;

  final Map<String, int> _counts = <String, int>{};
  bool _loaded = false;

  /// Sayaçların okunabilir kopyası.
  Map<String, int> get counts => Map<String, int>.unmodifiable(_counts);

  /// Tek bir sayacın değeri.
  int valueOf(AnalyticsEvent event, {String? suffix}) {
    _ensureLoaded();
    return _counts[_key(event, suffix)] ?? 0;
  }

  /// Kaç yolculuk tamamlandı, kaçı yarıda kaldı?
  ///
  /// Varış oranı bu ikisinden çıkar ve ürünün en çok merak ettiği sayı
  /// bu: oyuncu gerçekten durağına varabiliyor mu?
  double get arrivalRate {
    final arrived = valueOf(AnalyticsEvent.journeyArrived);
    final lost = valueOf(AnalyticsEvent.gameOver);
    final quit = valueOf(AnalyticsEvent.gameAbandoned);
    final total = arrived + lost + quit;
    return total == 0 ? 0 : arrived / total;
  }

  @override
  void log(AnalyticsEvent event, {Map<String, String> params = const {}}) {
    _ensureLoaded();
    _bump(_key(event, null));
    // Kategorik kırılımlar ayrı sayaç: "hangi oyun bitirilemiyor"
    // sorusunun cevabı burada.
    for (final entry in params.entries) {
      _bump('${event.id}.${entry.key}.${entry.value}');
    }
    _persist();
  }

  /// Sayaçları sıfırlar — ayarlardaki "verilerimi sil" buna da dokunur.
  Future<void> reset() async {
    _counts.clear();
    _loaded = true;
    await save(jsonEncode(_counts));
  }

  String _key(AnalyticsEvent event, String? suffix) =>
      suffix == null ? event.id : '${event.id}.$suffix';

  void _bump(String key) => _counts[key] = (_counts[key] ?? 0) + 1;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = load();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is int) _counts[entry.key] = value;
      }
    } catch (error) {
      // Bozuk sayaç dosyası oyunu durdurmaz; sayaçlar sıfırdan başlar.
      debugPrint('UsageStats okunamadı: $error');
      _counts.clear();
    }
  }

  void _persist() {
    // Yazma bilinçli olarak beklenmiyor: sayaç kaydı oyunun akışını
    // hiçbir koşulda geciktirmemeli.
    unawaited(save(jsonEncode(_counts)));
  }
}

/// `Future`'ı bilerek beklemediğimizi söyleyen küçük yardımcı.
void unawaited(Future<void> future) {}
