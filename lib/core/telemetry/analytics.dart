import 'package:flutter/foundation.dart';

/// Ölçülen olay.
///
/// Olay adları **sabit ve az**: serbest metin olay adı, üç sürüm sonra
/// aynı şeyin dört farklı adla sayıldığı bir panoya dönüşüyor.
enum AnalyticsEvent {
  /// Uygulama açıldı.
  appOpened('app_opened'),

  /// Rota seçildi.
  routeChosen('route_chosen'),

  /// Bir oyun başladı.
  gameStarted('game_started'),

  /// Yolculuk tamamlandı — varış sahnesi oynadı.
  journeyArrived('journey_arrived'),

  /// Oyun kendi kurallarıyla bitti (hamle kalmadı, canlar bitti).
  gameOver('game_over'),

  /// Oyuncu yolculuğu yarıda bıraktı.
  gameAbandoned('game_abandoned'),

  /// Sonuç paylaşıldı.
  resultShared('result_shared');

  const AnalyticsEvent(this.id);

  final String id;
}

/// Ölçüm arayüzü.
///
/// Uygulama kodu **yalnızca bunu tanır**. Bugünkü gerçeklemesi veriyi
/// cihazda tutuyor ve hiçbir yere göndermiyor; yarın bir sağlayıcı
/// (Firebase, PostHog, kendi ucumuz) eklenirse değişen tek şey bu
/// arayüzün arkası olur.
///
/// Sıralama önemli: analitik **uzağa gönderilmeye başladığı gün** App
/// Store gizlilik beyanı değişir. Bugünkü hâli beyanı "veri toplanmıyor"
/// olarak bırakıyor.
abstract class Analytics {
  /// Bir olayı kaydeder.
  ///
  /// [params] yalnızca **kategorik** değer taşımalı: oyun kimliği, rota
  /// profili, sonuç. Durak adı, skor gibi serbest değerler burada
  /// birikmez — sayılamaz hâle gelir ve kişiselleşme riski taşır.
  void log(AnalyticsEvent event, {Map<String, String> params = const {}});
}

/// Hiçbir şey yapmayan ölçüm — testlerin ve kapalı ayarın karşılığı.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  void log(AnalyticsEvent event, {Map<String, String> params = const {}}) {}
}

/// Ölçümü hata ayıklama günlüğüne basar; yalnızca debug derlemede konuşur.
class DebugAnalytics implements Analytics {
  const DebugAnalytics();

  @override
  void log(AnalyticsEvent event, {Map<String, String> params = const {}}) {
    if (!kDebugMode) return;
    final detail = params.isEmpty
        ? ''
        : ' ${params.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('ÖLÇÜM ${event.id}$detail');
  }
}
