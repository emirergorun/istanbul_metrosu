import 'package:flutter/foundation.dart';

/// Oyunların ham puanını ortak para birimine çeviren ölçek.
///
/// **Neden gerekli.** Rota rekoru artık tek: yolculuk boyunca hangi oyun
/// oynanırsa oynansın puan aynı kovaya yazılıyor. Oyunların ham puanları ise
/// birbirinden bağımsız doğmuştu — Ray Uçuşu kapı başına 1, Hat Düşür
/// birleşme başına seviye × 10 veriyordu. Ölçülen fark **85 kata** kadar
/// çıkıyordu (Ray Uçuşu 25 puan/dk, Hat Düşür 2124 puan/dk). Ölçek olmadan
/// rota rekoru "en cömert oyunu açan kazanır" demek olurdu.
///
/// **Ölçüm.** `test/balance/points_per_minute_test.dart` her oyunu orta
/// seviye bir botla 25 tohumla **bir yolculuk boyu** oynatır (yanınca
/// baştan başlar, tıpkı oyuncunun yapacağı gibi) ve medyan puan/dk'yı
/// yazar. [GameScoreProfile.measuredPerMinute] o tablonun **ölçek
/// uygulandıktan sonraki** değeridir: hepsi hedefin etrafında toplanmalı,
/// `test/balance/parity_test.dart` bunu her koşuda denetler. Tabloyu
/// yeniden üretmek için:
///
/// ```
/// flutter test test/balance/points_per_minute_test.dart --tags balance
/// ```
///
/// **Blok Metro çıpadır (ölçek 1.0).** Devralınan rota rekorlarının çoğu
/// Blok Metro rekoru; çıpa oynarsa eski rekorlar bir anda ulaşılmaz ya da
/// anlamsız olurdu. Hedef tempo da bu yüzden Blok Metro'nun ölçülen
/// temposudur.
///
/// **Rota uzunluğu.** Ölçekler 9 dakikalık bir rotada ayarlandı. Uzun
/// rotada (52 dk ölçüldü) bütün oyunlar birlikte yukarı kayıyor —
/// oyuncu ısınıyor, seviyeler yükseliyor — ama birbirlerine göre yerleri
/// değişmiyor: 131-157 puan/dk aralığında toplanıyorlar. Rekor rota
/// bazında tutulduğu için önemli olan da bu: aynı rotada hiçbir oyun
/// diğerinden cömert değil.
///
/// Ölçek **beceriyi ezmez**: oyunun kendi içindeki iyi-kötü farkı (combo,
/// seri, seviye) ham puanda kalır, ölçek yalnızca oyunlar arasındaki tempo
/// farkını kapatır.
@immutable
class GameScoreProfile {
  const GameScoreProfile({
    required this.measuredPerMinute,
    required this.scale,
    required this.note,
  });

  /// Orta seviye botun ölçülen medyan puan/dk'sı — **ölçek uygulanmış**
  /// hâli. Hedeften uzaklaşıyorsa ölçek eskimiş demektir.
  final int measuredPerMinute;

  /// Ham puanın çarpanı.
  final double scale;

  /// Ölçeğin gerekçesi — sayıyı değiştiren, önce bunu okusun.
  final String note;
}

/// Oyun başına ölçek tablosu.
class GameScoreProfiles {
  const GameScoreProfiles._();

  /// Her oyunun orta seviye oyuncuya dakikada vermesi hedeflenen puan.
  ///
  /// Blok Metro'nun ölçülen temposu (117); çıpa oradan alınınca hedef de
  /// oradan gelir, yuvarlak bir sayıya oturtuldu.
  static const int targetPointsPerMinute = 120;

  /// Parite testinin kabul bandı: hedefin ±%25'i.
  static const double parityTolerance = 0.25;

  /// Usta seviyenin tavanı: hedefin bu katından fazlasını veren oyun,
  /// rota rekorunun kestirme yolu olur.
  ///
  /// Rekoru kuran orta seviye oyuncu değil, iyi oynayan oyuncudur; bu
  /// yüzden ölçek ortalamaya bakarken tavan ustaya bakar.
  static const double expertCeiling = 1.7;

  static const Map<String, GameScoreProfile> profiles =
      <String, GameScoreProfile>{
        'blocks': GameScoreProfile(
          measuredPerMinute: 117,
          scale: 1.0,
          note:
              'Çıpa. Devralınan rota rekorlarının çoğu bu oyundan geliyor; '
              'ölçeği 1 kalmalı ki eski rekorlar anlamını korusun.',
        ),
        'metro_merge': GameScoreProfile(
          measuredPerMinute: 120,
          scale: 0.37,
          note:
              '2048 puanlaması (birleşen karonun değeri) bilinçli olarak '
              'korundu — oyun "birebir 2048" olsun diye istenmişti. Ölçülen '
              'dağılımda piyango kuyruğu yok (p10 240, p90 338), yani üstel '
              'değer pratikte şişme yapmıyor; yalnız tempo farkı kapatılıyor.',
        ),
        'rail_flight': GameScoreProfile(
          measuredPerMinute: 121,
          scale: 1.42,
          note:
              'Oyunların en yavaşı: kapı ~2 saniyede bir geliyor, bu yüzden '
              'yukarı çekilen tek oyun. Ham puan kapı başına sabit 1\'den '
              'hat seviyesine çevrildi (beceri puana yansısın diye) ve '
              'zorluk artık rota uzunluğuna değil geçilen kapıya bağlı — '
              'uzun rotada oyun en zor ayarla başlıyor, dakikada 43 puanda '
              'kalıyordu.',
        ),
        'merge_drop': GameScoreProfile(
          measuredPerMinute: 122,
          scale: 0.052,
          note:
              'Açık ara en cömert oyun: saniyede birkaç birleşme ve seviye '
              'çarpanı birleşince dakikada 2000 puanı aşıyor.',
        ),
        'lane_runner': GameScoreProfile(
          measuredPerMinute: 120,
          scale: 0.22,
          note:
              'Engeller oyuncu hayatta kaldıkça hızlanıyor; hem tempo hem '
              'hat seviyesi yükseldiği için ham puan hızla büyüyor.',
        ),
        'train_snake': GameScoreProfile(
          // Oyun yeniden kuruldu: hat başına 5 yolcu (3'tü), seviye başına
          // +2 bonus vagon ve 11x15 tahta. Ham puan düştüğü için ölçek
          // yeniden ölçüldü — eski 0.096 dakikada 82 puan veriyordu.
          measuredPerMinute: 82,
          scale: 0.140,
          note: 'Yolcu başına seviye × 10; tempo hızlı.',
        ),
        'metro_quiz': GameScoreProfile(
          measuredPerMinute: 97,
          scale: 1.38,
          note:
              'Tek oyun burada **ustaya göre** ayarlandı. Sebebi: soru '
              'havuzu sonlu, tekrar oynayan oyuncu havuzu tanıyor ve '
              'neredeyse hiç yanlış yapmıyor — yani "usta" bu oyunda '
              'erişilebilir bir hedef, rekor da orada kuruluyor. Orta '
              'seviye bu yüzden hedefin biraz altında (97), usta ise '
              'diğer oyunların ustalarıyla aynı bantta (~180).',
        ),
      };

  /// Verilen oyunun ölçeği; tanımsız oyun ham puanıyla geçer.
  static double scaleFor(String gameId) => profiles[gameId]?.scale ?? 1.0;
}
