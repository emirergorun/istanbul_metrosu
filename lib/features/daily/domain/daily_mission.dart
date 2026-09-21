import 'package:flutter/foundation.dart';

import 'daily_counters.dart';

/// Günlük görevin ölçtüğü davranış.
///
/// Kimlik **tür**, metin değil: görev adı bir gün değişirse ya da başka bir
/// dile çevrilirse kayıtlı ilerleme bozulmamalı. [id] kalıcıdır, elle
/// değiştirilmemeli.
///
/// Her tür, o gün tutulan sayaçlardan **türetilebilir** olmak zorunda.
/// Ölçülemeyen bir görev (ör. "gece yarısı oyna") buraya girmez: sayaç
/// yoksa ilerleme de yoktur.
enum DailyMissionType {
  /// Bugünün yolculuğunu, bugünün oyunuyla tamamla.
  dailyJourney('daily_journey'),

  /// Herhangi bir rotada yolculuğu sonuna kadar götür.
  completeJourney('complete_journey'),

  /// Oyun bitir — vararak ya da kaybederek. Yarıda bırakmak sayılmaz.
  playGames('play_games'),

  /// Farklı oyunlar oyna.
  playDistinctGames('play_distinct_games'),

  /// Daha önce hiç görülmemiş durak keşfet.
  discoverStations('discover_stations');

  const DailyMissionType(this.id);

  /// Kayıtta ve ölçümde kullanılan kalıcı kimlik.
  final String id;

  static DailyMissionType? byId(String id) {
    for (final type in values) {
      if (type.id == id) return type;
    }
    return null;
  }
}

/// Bir günlük görev: tür, hedef ve o günün sayaçlarından türeyen ilerleme.
///
/// İlerleme burada **tutulmaz**, hesaplanır. Görev başına ayrı bir sayaç
/// saklansaydı iki kayıt (görev ilerlemesi ve gün sayaçları) zamanla
/// birbirinden ayrı düşerdi — klasik "sayaç kayması" hatası.
@immutable
class DailyMission {
  const DailyMission({required this.type, required this.target});

  final DailyMissionType type;

  /// Görevin tamamlanması için gereken sayı. En az 1.
  final int target;

  /// Kısa görev metni. Hedef sayı metne gömülür: "3 yeni istasyon keşfet".
  String get title => switch (type) {
    DailyMissionType.dailyJourney => 'Bugünün yolculuğunu tamamla',
    DailyMissionType.completeJourney => target == 1
        ? 'Bir yolculuğu sonuna kadar götür'
        : '$target yolculuk tamamla',
    DailyMissionType.playGames => '$target oyun bitir',
    DailyMissionType.playDistinctGames => '$target farklı oyun oyna',
    DailyMissionType.discoverStations => '$target yeni istasyon keşfet',
  };

  /// Sayaçlara bakarak bu görevin ilerlemesini verir; hedefi aşmaz.
  int progressFrom(DailyCounters counters) {
    final raw = switch (type) {
      DailyMissionType.dailyJourney => counters.dailyDone ? 1 : 0,
      DailyMissionType.completeJourney => counters.arrivals,
      DailyMissionType.playGames => counters.finishedRuns,
      DailyMissionType.playDistinctGames => counters.playedGameIds.length,
      DailyMissionType.discoverStations => counters.newStations,
    };
    return raw > target ? target : raw;
  }

  bool isCompleteFor(DailyCounters counters) =>
      progressFrom(counters) >= target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyMission && other.type == type && other.target == target);

  @override
  int get hashCode => Object.hash(type, target);

  @override
  String toString() => 'DailyMission(${type.id}, $target)';
}
