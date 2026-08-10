import 'package:flutter/foundation.dart';

/// İki komşu istasyon arasındaki yaklaşık seyahat süresi.
///
/// MVP'de yön simetriktir (from->to == to->from).
/// TODO(PROD): Yön, servis takvimi ve aktarma süreleri ayrı ağırlıklarla modellenecek.
@immutable
class Edge {
  const Edge({required this.from, required this.to, required this.minutes});

  final String from;
  final String to;
  final int minutes;

  bool connects(String a, String b) =>
      (from == a && to == b) || (from == b && to == a);

  @override
  String toString() => 'Edge($from<->$to, $minutes dk)';
}
