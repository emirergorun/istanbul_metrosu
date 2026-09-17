/// Yolculuk sonunda paylaşılan metin.
///
/// **Görsel değil, metin.** Wordle'ın yayılmasını sağlayan şey de bir
/// görsel değil, kopyalanabilir küçük bir desendi: karşı taraf ne
/// olduğunu bir bakışta anlıyor, tıklamak zorunda kalmıyor ve metin her
/// uygulamada aynı görünüyor. Görsel üretmek dosya yazmayı, izinleri ve
/// her cihazda farklı ölçeklenen bir tuvali beraberinde getirirdi.
///
/// Desen rotanın kendisi: geçilen duraklar dolu, geçilmeyenler boş.
///
/// ```
/// İstanbul Metrosu Oyunu · M1A
/// Yenikapı → Otogar
/// ●━●━●━●━○━○━○
/// Blok Metro · 6.180 puan · 7 durağın 4'ü
/// — Hızlı Kadıköylü
/// ```
library;

import '../../../core/utils/formatters.dart';

class ShareCard {
  const ShareCard._();

  /// Dolu durak işareti.
  static const String passed = '●';

  /// Geçilmemiş durak.
  static const String remaining = '○';

  /// Duraklar arası bağ.
  static const String link = '━';

  /// Metin uzun rotalarda taşmasın diye çizilen en fazla durak sayısı.
  ///
  /// 32 duraklı bir maraton rotası tek satıra sığmıyor ve paylaşım metni
  /// okunmaz hâle geliyordu. Üstünde kalan rotalarda desen örneklenir:
  /// oran korunur, uzunluk sabitlenir.
  static const int maxDots = 12;

  /// Rota deseni.
  static String route({required int stops, required int passedStops}) {
    if (stops <= 0) return '';
    final count = stops > maxDots ? maxDots : stops;
    final filled = stops > maxDots
        ? (passedStops * maxDots / stops).round()
        : passedStops;

    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      if (i > 0) buffer.write(link);
      buffer.write(i < filled ? passed : remaining);
    }
    return buffer.toString();
  }

  /// Paylaşılacak metnin tamamı.
  static String build({
    required String lineId,
    required String originName,
    required String destinationName,
    required String gameName,
    required int score,
    required int stops,
    required int passedStops,
    required String playerName,
    required bool arrived,
  }) {
    final pattern = route(stops: stops, passedStops: passedStops);
    final outcome = arrived
        ? 'Durağıma vardım'
        : '$stops durağın $passedStops\'ini geçtim';

    return <String>[
      'İstanbul Metrosu Oyunu · $lineId',
      '$originName → $destinationName',
      pattern,
      '$gameName · ${Formatters.score(score)} puan · $outcome',
      '— $playerName',
    ].where((line) => line.isNotEmpty).join('\n');
  }
}
