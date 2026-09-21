import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'day_stamp.dart';

/// Bir günde olup bitenin **tamamı**.
///
/// Günlük sistemin sakladığı tek kayıt budur. Görev ilerlemeleri, günün
/// tamamlanması ve seri kuralı hep buradan türer; hiçbir görev kendi
/// sayacını tutmaz.
///
/// Sayaçlar yalnızca **artar**. Gün değiştiğinde kayıt bir bütün olarak
/// atılır ve sıfırdan başlar — geri alma, düzeltme ya da eksiltme yok.
@immutable
class DailyCounters {
  const DailyCounters({
    required this.day,
    this.finishedRuns = 0,
    this.arrivals = 0,
    this.newStations = 0,
    this.playedGameIds = const <String>{},
    this.dailyDone = false,
  });

  /// Bu sayaçların ait olduğu takvim günü.
  final DayStamp day;

  /// Sonuna kadar oynanmış koşu sayısı — varış ya da oyun sonu.
  ///
  /// Yarıda bırakılan oyun sayılmaz: "oyun bitir" görevi oyunu açıp geri
  /// dönmekle tamamlanabilseydi görev olmazdı.
  final int finishedRuns;

  /// Sonuna kadar götürülen yolculuk sayısı.
  final int arrivals;

  /// Bugün **ilk kez** keşfedilen fiziksel durak sayısı.
  final int newStations;

  /// Bugün bitirilen oyunların kimlikleri.
  final Set<String> playedGameIds;

  /// Bugünün yolculuğu, bugünün oyunuyla tamamlandı mı?
  final bool dailyDone;

  DailyCounters copyWith({
    int? finishedRuns,
    int? arrivals,
    int? newStations,
    Set<String>? playedGameIds,
    bool? dailyDone,
  }) => DailyCounters(
    day: day,
    finishedRuns: finishedRuns ?? this.finishedRuns,
    arrivals: arrivals ?? this.arrivals,
    newStations: newStations ?? this.newStations,
    playedGameIds: playedGameIds ?? this.playedGameIds,
    dailyDone: dailyDone ?? this.dailyDone,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'day': day.toString(),
    'runs': finishedRuns,
    'arrivals': arrivals,
    'stations': newStations,
    'games': playedGameIds.toList()..sort(),
    'done': dailyDone,
  };

  String encode() => jsonEncode(toJson());

  /// Kaydı çözer. Bozuk ya da eksikse `null` — o gün sıfırdan başlar.
  static DailyCounters? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final day = DayStamp.tryParse(map['day'] as String?);
      if (day == null) return null;
      final games = map['games'];
      return DailyCounters(
        day: day,
        finishedRuns: _positiveInt(map['runs']),
        arrivals: _positiveInt(map['arrivals']),
        newStations: _positiveInt(map['stations']),
        playedGameIds: <String>{
          if (games is List)
            for (final id in games)
              if (id is String && id.isNotEmpty) id,
        },
        dailyDone: map['done'] == true,
      );
    } catch (error) {
      debugPrint('Günlük kaydı okunamadı: $error');
      return null;
    }
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value < 0) return 0;
    return value;
  }
}
