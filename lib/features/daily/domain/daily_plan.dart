import 'package:flutter/foundation.dart';

import '../../journey/models/journey.dart';
import 'daily_mission.dart';
import 'day_stamp.dart';

/// Bir günün tamamı: yolculuk, oyun ve görevler.
///
/// Tamamen [DayStamp]'ten türer. Kayıttan okunmaz, kayda yazılmaz; oyuncunun
/// o gün ne yaptığı ayrı tutulur. Böylece metro verisi büyüdüğünde ya da
/// kayıt bozulduğunda planın kendisi sağlam kalır.
@immutable
class DailyPlan {
  const DailyPlan({
    required this.day,
    required this.journey,
    required this.gameId,
    required this.missions,
  });

  final DayStamp day;

  /// Günün rotası — gerçek metro verisinden, oynanabilir.
  final Journey journey;

  /// Günün önerdiği oyun. Katalogdaki kalıcı kimlik.
  final String gameId;

  /// Günün görevleri. İlki her zaman günün yolculuğudur.
  final List<DailyMission> missions;

  /// Bu rota, verilen yolculukla aynı mı? Yön fark etmez.
  ///
  /// Oyuncu günün rotasını ters yönde oynarsa da günü tamamlamış sayılır:
  /// aynı duraklar, aynı süre, aynı keşif.
  bool matchesRoute(Journey other) {
    final mine = <String>[journey.origin.id, journey.destination.id]..sort();
    final theirs = <String>[other.origin.id, other.destination.id]..sort();
    return mine[0] == theirs[0] && mine[1] == theirs[1];
  }

  @override
  String toString() =>
      'DailyPlan($day, ${journey.lineId} '
      '${journey.origin.name}→${journey.destination.name}, $gameId)';
}
