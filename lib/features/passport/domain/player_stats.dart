import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Ömür boyu biriken oyunculuk kaydı.
///
/// Yalnızca **türetilemeyen** şeyler var burada: kaç yolculuk tamamlandı,
/// hangi oyunlar bitirildi ve her oyunda kaç koşu bitirildi. Keşfedilen durak sayısı, tamamlanan hat sayısı ve
/// seri burada tutulmaz — onların tek doğru kaynağı kendi kayıtları.
@immutable
class PlayerStats {
  const PlayerStats({
    this.journeysCompleted = 0,
    this.playedGameIds = const <String>{},
    this.gameRuns = const <String, int>{},
  });

  static const PlayerStats empty = PlayerStats();

  /// Sonuna kadar götürülen yolculuk sayısı.
  final int journeysCompleted;

  /// Bitirilen oyunların kimlikleri — varış ya da oyun sonu.
  final Set<String> playedGameIds;

  /// Oyun başına sayılan (anlamlı) biten koşu sayısı — oyun ustalığı rozetleri.
  ///
  /// Skor yerine koşu sayılıyor: puan artık rotanın ortak havuzunda, tek bir
  /// oyunun payı ayrıştırılamıyor. Kayda sonradan eklendi; eski kayıtta alan
  /// yoksa boş harita okunur, hiçbir şey kaybolmaz.
  final Map<String, int> gameRuns;

  int runsOf(String gameId) => gameRuns[gameId] ?? 0;

  PlayerStats copyWith({
    int? journeysCompleted,
    Set<String>? playedGameIds,
    Map<String, int>? gameRuns,
  }) => PlayerStats(
    journeysCompleted: journeysCompleted ?? this.journeysCompleted,
    playedGameIds: playedGameIds ?? this.playedGameIds,
    gameRuns: gameRuns ?? this.gameRuns,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'journeys': journeysCompleted,
    'games': playedGameIds.toList()..sort(),
    'runs': gameRuns,
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
      final runs = map['runs'];
      return PlayerStats(
        journeysCompleted: journeys is int && journeys > 0 ? journeys : 0,
        playedGameIds: <String>{
          if (games is List)
            for (final id in games)
              if (id is String && id.isNotEmpty) id,
        },
        gameRuns: <String, int>{
          if (runs is Map)
            for (final entry in runs.entries)
              if (entry.key is String && entry.value is int && entry.value > 0)
                entry.key as String: entry.value as int,
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
          setEquals(other.playedGameIds, playedGameIds) &&
          mapEquals(other.gameRuns, gameRuns));

  @override
  int get hashCode => Object.hash(
    journeysCompleted,
    Object.hashAllUnordered(playedGameIds),
    Object.hashAllUnordered(
      gameRuns.entries.map(
        (MapEntry<String, int> e) => Object.hash(e.key, e.value),
      ),
    ),
  );
}
