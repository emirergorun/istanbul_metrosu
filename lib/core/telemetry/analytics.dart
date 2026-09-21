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
  resultShared('result_shared'),

  /// İlk kez bir durağa ulaşıldı.
  ///
  /// Durağın kendisi taşınmaz, hattı taşınır: 143 durak adı panoyu
  /// sayılamaz hâle getirir, oysa "hangi oyun hangi hattı keşfettiriyor"
  /// on satırda okunur.
  stationDiscovered('station_discovered'),

  /// Bir hattın tüm durakları keşfedildi.
  lineCompleted('line_completed'),

  /// Keşif ekranı açıldı.
  discoveryScreenViewed('discovery_screen_viewed'),

  /// Günün yolculuğu ekranda görüldü.
  dailyJourneyViewed('daily_journey_viewed'),

  /// Günün yolculuğu başlatıldı.
  dailyJourneyStarted('daily_journey_started'),

  /// Günün yolculuğu tamamlandı.
  dailyJourneyCompleted('daily_journey_completed'),

  /// Bir günlük görev tamamlandı.
  dailyMissionCompleted('daily_mission_completed'),

  /// Seri ilerledi ya da baştan başladı.
  streakAdvanced('streak_advanced'),

  /// Bir başarım açıldı.
  achievementUnlocked('achievement_unlocked'),

  /// Arkadaşlar ekranı açıldı.
  friendsOpened('friends_opened'),

  /// Arkadaş eklendi.
  ///
  /// Kimlik taşınmaz: ne kod ne ad. Sayılabilir olan tek şey olayın
  /// kendisi; kimin kimi eklediği ölçümün işi değil.
  friendAdded('friend_added'),

  /// Meydan okuma üretildi.
  challengeCreated('challenge_created'),

  /// Meydan okuma karesi okundu.
  challengeScanned('challenge_scanned'),

  /// Meydan okuma kabul edildi.
  challengeAccepted('challenge_accepted'),

  /// Meydan okuma tamamlandı.
  challengeCompleted('challenge_completed'),

  /// Rövanş üretildi.
  rematchCreated('rematch_created');

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
