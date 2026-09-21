import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Ömür boyu biriken oyunculuk kaydı.
///
/// Yalnızca **türetilemeyen** iki şey var burada: kaç yolculuk tamamlandı ve
/// hangi oyunlar bitirildi. Keşfedilen durak sayısı, tamamlanan hat sayısı ve
/// seri burada tutulmaz — onların tek doğru kaynağı kendi kayıtları.
@immutable
class PlayerStats {
  const PlayerStats({
    this.journeysCompleted = 0,
    this.playedGameIds = const <String>{},
  });

  static const PlayerStats empty = PlayerStats();

  /// Sonuna kadar götürülen yolculuk sayısı.
  final int journeysCompleted;

  /// Bitirilen oyunların kimlikleri — varış ya da oyun sonu.
  final Set<String> playedGameIds;

  PlayerStats copyWith({int? journeysCompleted, Set<String>? playedGameIds}) =>
      PlayerStats(
        journeysCompleted: journeysCompleted ?? this.journeysCompleted,
        playedGameIds: playedGameIds ?? this.playedGameIds,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'journeys': journeysCompleted,
    'games': playedGameIds.toList()..sort(),
  };

  String encode() => jsonEncode(toJson());

  /// Kaydı çözer. Bozuksa [empty] — başarım ilerlemesi kaybolur ama
  /// uygulama açılır ve keşif kaydına hiçbir şey olmaz.
  static PlayerStats decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return empty;
      final journeys = map['journeys'];
      final games = map['games'];
      return PlayerStats(
        journeysCompleted: journeys is int && journeys > 0 ? journeys : 0,
        playedGameIds: <String>{
          if (games is List)
            for (final id in games)
              if (id is String && id.isNotEmpty) id,
        },
      );
    } catch (error) {
      debugPrint('Oyuncu kaydı okunamadı: $error');
      return empty;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayerStats &&
          other.journeysCompleted == journeysCompleted &&
          setEquals(other.playedGameIds, playedGameIds));

  @override
  int get hashCode =>
      Object.hash(journeysCompleted, Object.hashAllUnordered(playedGameIds));
}
