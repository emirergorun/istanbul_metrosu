import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Yarım kalan **yolculuğun** diske yazılabilir hâli.
///
/// Metroda uygulama sürekli arka plana atılır, kapatılır, unutulur. Kayıt
/// artık tek bir oyunun değil yolculuğun: puan, kalan süre, geçilen durak
/// ve puanın oyunlara dağılımı yolculuğa ait. Oyunun kendi durumu (Blok
/// Metro'nun tahtası gibi) [gamePayload] içinde, olduğu gibi taşınan bir
/// metin olarak durur — zarf onu okumaz, yalnızca saklar.
///
/// Rota iki durak id'siyle saklanır ve açılışta yeniden hesaplanır; metro
/// verisi güncellenirse eski kayıt sessizce geçersiz olur.
///
/// [savedAt] **yalnızca gösterim içindir; asla süreye eklenmez.** Uygulama
/// kapalıyken tren yol almaz: oyuncunun bir gün sonra dönüp yolculuğu
/// bitmiş bulması, kaydın anlamını yok ederdi.
@immutable
class JourneySave {
  const JourneySave({
    required this.originId,
    required this.destinationId,
    required this.elapsedSeconds,
    required this.score,
    required this.scoreByGame,
    required this.secondsByGame,
    required this.stationsPassed,
    required this.recordToBeat,
    required this.recordBeaten,
    required this.savedAt,
    this.activeGameId,
    this.gamePayload,
  });

  /// Kayıt biçimi değişirse eski kayıtlar atılır.
  static const int version = 1;

  final String originId;
  final String destinationId;
  final double elapsedSeconds;
  final int score;
  final Map<String, int> scoreByGame;

  /// Hangi oyunda kaç saniye oynandı.
  final Map<String, double> secondsByGame;
  final int stationsPassed;
  final int recordToBeat;
  final bool recordBeaten;

  /// Son oynanan oyun — kart bunu yazar, kayıt buna göre sürdürülür.
  final String? activeGameId;

  /// [activeGameId] oyununun kendi kaydı; zarf içeriğini bilmez.
  final String? gamePayload;

  final DateTime savedAt;

  String encode() => jsonEncode(<String, dynamic>{
    'v': version,
    'origin': originId,
    'destination': destinationId,
    'elapsed': elapsedSeconds,
    'score': score,
    'scoreByGame': scoreByGame,
    'secondsByGame': secondsByGame,
    'stations': stationsPassed,
    'record': recordToBeat,
    'recordBeaten': recordBeaten,
    'activeGame': activeGameId,
    'gamePayload': gamePayload,
    'savedAt': savedAt.toIso8601String(),
  });

  /// Bozuk ya da eski sürüm kayıtta `null` döner.
  static JourneySave? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != version) return null;
      return JourneySave(
        originId: json['origin'] as String,
        destinationId: json['destination'] as String,
        elapsedSeconds: (json['elapsed'] as num).toDouble(),
        score: json['score'] as int,
        scoreByGame: <String, int>{
          for (final entry
              in (json['scoreByGame'] as Map<dynamic, dynamic>).entries)
            entry.key as String: entry.value as int,
        },
        // Süre dağılımı sonradan eklendi: eski zarfta yoksa boş geçilir.
        secondsByGame: <String, double>{
          for (final entry
              in ((json['secondsByGame'] as Map<dynamic, dynamic>?) ??
                      const <dynamic, dynamic>{})
                  .entries)
            entry.key as String: (entry.value as num).toDouble(),
        },
        stationsPassed: json['stations'] as int,
        recordToBeat: json['record'] as int,
        recordBeaten: json['recordBeaten'] as bool,
        activeGameId: json['activeGame'] as String?,
        gamePayload: json['gamePayload'] as String?,
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (error, stack) {
      debugPrint('Yolculuk kaydı okunamadı: $error\n$stack');
      return null;
    }
  }

  /// Ortak yolculuktan önceki (Blok Metro'ya ait) kaydı zarfa çevirir.
  ///
  /// Eski kayıt hem tahtayı hem yolculuğu taşıyordu. Yolculuk alanları
  /// buraya alınır, kaydın tamamı oyunun yükü olarak olduğu gibi saklanır:
  /// Blok Metro onu kendi çözücüsüyle okumayı sürdürüyor.
  ///
  /// Kaydın içine bakmaz sayılır — yalnızca yolculuğa ait alanları okur,
  /// tahtaya dokunmaz.
  static JourneySave? fromLegacyGameSave(String raw, {required String gameId}) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final origin = json['origin'] as String?;
      final destination = json['destination'] as String?;
      if (origin == null || destination == null) return null;
      return JourneySave(
        originId: origin,
        destinationId: destination,
        elapsedSeconds: (json['elapsed'] as num?)?.toDouble() ?? 0,
        score: json['score'] as int? ?? 0,
        scoreByGame: <String, int>{
          if ((json['score'] as int? ?? 0) > 0) gameId: json['score'] as int,
        },
        // Eski kayıt süreyi oyun bazında tutmuyordu; yolculuğun tamamı o
        // oyunda geçmiş sayılır.
        secondsByGame: <String, double>{
          gameId: (json['elapsed'] as num?)?.toDouble() ?? 0,
        },
        stationsPassed: json['stationsPassed'] as int? ?? 0,
        recordToBeat: json['record'] as int? ?? 0,
        recordBeaten: json['recordBeaten'] as bool? ?? false,
        activeGameId: gameId,
        gamePayload: raw,
        savedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (error, stack) {
      debugPrint('Eski oyun kaydı çevrilemedi: $error\n$stack');
      return null;
    }
  }
}
