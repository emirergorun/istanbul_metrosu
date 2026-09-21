import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../daily/domain/day_stamp.dart';
import 'challenge.dart';

/// Meydan okumanın sonucu.
enum ChallengeOutcome {
  won('KAZANDIN'),
  lost('AZ FARKLA'),
  tied('BERABERE');

  const ChallengeOutcome(this.label);

  /// Tabela dilinde tek kelime.
  ///
  /// Kaybeden için "KAYBETTIN" yazmıyor: bu bir arkadaş maçı, aşağılayıcı
  /// dil oyuncuyu rövanştan uzaklaştırır. Sayı zaten farkı söylüyor.
  final String label;

  /// Skorları karşılaştırır. Eşitlikte kimse kazanmaz.
  static ChallengeOutcome compare({required int mine, required int target}) {
    if (mine > target) return ChallengeOutcome.won;
    if (mine < target) return ChallengeOutcome.lost;
    return ChallengeOutcome.tied;
  }
}

/// Tamamlanmış bir meydan okumanın **yerel** kaydı.
///
/// Dikkat: bu kayıt yalnızca bu cihazda oynanmış meydan okumaları bilir.
/// "Berke 8 - Emir 4" gibi bir karşılaşma tablosu **gösterilemez**, çünkü
/// iki cihazın geçmişi birbirini doğrulayamıyor. Arayüz bu yüzden tek
/// taraflı bir liste sunuyor: "senin oynadığın meydan okumalar".
@immutable
class ChallengeRecord {
  const ChallengeRecord({
    required this.challengeId,
    required this.opponentName,
    required this.opponentCode,
    required this.gameId,
    required this.lineId,
    required this.originName,
    required this.destinationName,
    required this.myScore,
    required this.targetScore,
    required this.playedOn,
    required this.seed,
    required this.originId,
    required this.destinationId,
    required this.estimatedSeconds,
  });

  final String challengeId;
  final String opponentName;
  final String opponentCode;
  final String gameId;
  final String lineId;
  final String originName;
  final String destinationName;
  final int myScore;
  final int targetScore;
  final DayStamp playedOn;

  /// Rövanşın aynı rotayı yeniden kurabilmesi için taşınan alanlar.
  final int seed;
  final String originId;
  final String destinationId;
  final int estimatedSeconds;

  ChallengeOutcome get outcome =>
      ChallengeOutcome.compare(mine: myScore, target: targetScore);

  /// Aradaki fark; işaretli.
  int get difference => myScore - targetScore;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': challengeId,
    'name': opponentName,
    'code': opponentCode,
    'game': gameId,
    'line': lineId,
    'from': originName,
    'to': destinationName,
    'fromId': originId,
    'toId': destinationId,
    'mine': myScore,
    'target': targetScore,
    'seed': seed,
    'secs': estimatedSeconds,
    'day': playedOn.toString(),
  };

  static ChallengeRecord? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      final day = DayStamp.tryParse(raw['day'] as String?);
      if (day == null) return null;
      return ChallengeRecord(
        challengeId: raw['id'] as String? ?? '',
        opponentName: raw['name'] as String? ?? '',
        opponentCode: raw['code'] as String? ?? '',
        gameId: raw['game'] as String? ?? '',
        lineId: raw['line'] as String? ?? '',
        originName: raw['from'] as String? ?? '',
        destinationName: raw['to'] as String? ?? '',
        originId: raw['fromId'] as String? ?? '',
        destinationId: raw['toId'] as String? ?? '',
        myScore: raw['mine'] as int? ?? 0,
        targetScore: raw['target'] as int? ?? 0,
        seed: raw['seed'] as int? ?? 0,
        estimatedSeconds: raw['secs'] as int? ?? 0,
        playedOn: day,
      );
    } catch (error) {
      debugPrint('Meydan okuma kaydı okunamadı: $error');
      return null;
    }
  }

  static String encodeList(List<ChallengeRecord> records) =>
      jsonEncode(<Object?>[for (final record in records) record.toJson()]);

  static List<ChallengeRecord> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <ChallengeRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ChallengeRecord>[];
      return <ChallengeRecord>[
        for (final entry in decoded)
          if (ChallengeRecord.fromJson(entry) case final ChallengeRecord r) r,
      ];
    } catch (error) {
      debugPrint('Meydan okuma geçmişi okunamadı: $error');
      return const <ChallengeRecord>[];
    }
  }

  /// Bu kayıttan rövanş için yeni bir meydan okuma kurar.
  ///
  /// Rota, oyun ve süre aynı; **tohum yeni**. Aynı tohumla oynamak ikinci
  /// turda ezbere avantaj verirdi: aynı parça dizisi, aynı engel sırası,
  /// aynı soru sırası. Rövanşın adil olması için rastgelelik tazelenir,
  /// koşullar sabit kalır.
  Challenge rematch({
    required String id,
    required int seed,
    required String myCode,
    required String myName,
    required int today,
  }) => Challenge(
    id: id,
    gameId: gameId,
    lineId: lineId,
    originId: originId,
    destinationId: destinationId,
    estimatedSeconds: estimatedSeconds,
    targetScore: myScore,
    seed: seed,
    creatorCode: myCode,
    creatorName: myName,
    createdOnEpochDay: today,
  );
}
