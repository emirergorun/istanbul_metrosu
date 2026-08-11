import 'package:flutter/foundation.dart';

/// İki komşu istasyon arasındaki yaklaşık seyahat süresi.
///
/// Süre **saniye** cinsindendir. Dakika kullanılsaydı yuvarlama hatası
/// birikirdi: M4'ün 22 kenarı 2'şer dakikaya yuvarlansa hat uçtan uca
/// 52 dakika yerine 44 dakika çıkardı.
///
/// MVP'de yön simetriktir (from->to == to->from).
/// TODO(PROD): Yön ve servis takvimi ayrı ağırlıklarla modellenecek.
@immutable
class Edge {
  const Edge({required this.from, required this.to, required this.seconds});

  final String from;
  final String to;
  final int seconds;

  bool connects(String a, String b) =>
      (from == a && to == b) || (from == b && to == a);

  @override
  String toString() => 'Edge($from<->$to, $seconds sn)';
}
