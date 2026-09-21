import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_generator.dart';
import 'package:istanbul_metro_game/features/daily/domain/daily_mission.dart';
import 'package:istanbul_metro_game/features/daily/domain/day_stamp.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

/// Günün planı **takvim gününden** türüyor.
///
/// Sınanan söz: aynı gün her zaman aynı yolculuğu verir, ertesi gün
/// başkasını, ve üretilen her rota gerçekten oynanabilir.
void main() {
  final metro = MetroFixture.load();
  final generator = DailyGenerator(metro: metro, routes: RouteService(metro));

  test('aynı gün her çağrıda aynı planı verir', () {
    const day = DayStamp(2026, 9, 20);
    final first = generator.planFor(day)!;
    final second = generator.planFor(day)!;

    expect(first.journey.origin.id, second.journey.origin.id);
    expect(first.journey.destination.id, second.journey.destination.id);
    expect(first.gameId, second.gameId);
    expect(first.missions, second.missions);
  });

  test('yeni gün yeni plan getirir', () {
    // Otuz ardışık günün hepsi aynı rotaya düşerse üretim rastgele değil.
    final routes = <String>{
      for (var i = 0; i < 30; i++)
        () {
          final plan = generator.planFor(
            DayStamp.fromEpochDay(const DayStamp(2026, 9, 20).epochDay + i),
          )!;
          return '${plan.journey.origin.id}>${plan.journey.destination.id}';
        }(),
    };
    expect(routes.length, greaterThan(5));
  });

  test('üretilen rota oynanabilir', () {
    for (var i = 0; i < 60; i++) {
      final day = DayStamp.fromEpochDay(
        const DayStamp(2026, 1, 1).epochDay + i,
      );
      final plan = generator.planFor(day);
      expect(plan, isNotNull, reason: '$day');

      final journey = plan!.journey;
      expect(journey.origin.id, isNot(journey.destination.id));
      expect(journey.origin.lineId, journey.destination.lineId);
      expect(journey.estimatedSeconds, greaterThan(0));
      // Patolojik uzunluk yok: günlük alışkanlık kısa bir oturuma sığmalı.
      expect(journey.stopCount, greaterThanOrEqualTo(DailyGenerator.minStops));
      expect(journey.stopCount, lessThanOrEqualTo(DailyGenerator.maxStops));
    }
  });

  test('günün oyunu katalogdan ve oynanabilir', () {
    for (var i = 0; i < 30; i++) {
      final day = DayStamp.fromEpochDay(
        const DayStamp(2026, 5, 1).epochDay + i,
      );
      final game = MiniGames.byId(generator.gameIdFor(day));
      expect(game, isNotNull, reason: '$day');
      expect(game!.isAvailable, isTrue);
    }
  });

  test('arka arkaya iki gün aynı oyun düşmez', () {
    for (var i = 0; i < 40; i++) {
      final day = DayStamp.fromEpochDay(
        const DayStamp(2026, 5, 1).epochDay + i,
      );
      expect(
        generator.gameIdFor(day),
        isNot(generator.gameIdFor(day.previous)),
        reason: '$day',
      );
    }
  });

  test('oyunlar sırayla dolaşılıyor', () {
    final seen = <String>{
      for (var i = 0; i < MiniGames.playable.length; i++)
        generator.gameIdFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 5, 1).epochDay + i),
        ),
    };
    expect(seen.length, MiniGames.playable.length);
  });

  group('görevler', () {
    test('üç görev, ilki günün yolculuğu', () {
      for (var i = 0; i < 20; i++) {
        final missions = generator.missionsFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 2, 1).epochDay + i),
        );
        expect(missions, hasLength(3));
        expect(missions.first.type, DailyMissionType.dailyJourney);
        expect(missions.first.target, 1);
      }
    });

    test('aynı tür iki kez verilmez', () {
      for (var i = 0; i < 20; i++) {
        final missions = generator.missionsFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 2, 1).epochDay + i),
        );
        final types = missions.map((DailyMission m) => m.type).toSet();
        expect(types, hasLength(missions.length));
      }
    });

    test('hedefler kısa bir oturuma sığacak kadar küçük', () {
      for (var i = 0; i < 60; i++) {
        final missions = generator.missionsFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 2, 1).epochDay + i),
        );
        for (final mission in missions) {
          expect(mission.target, greaterThan(0));
          expect(mission.target, lessThanOrEqualTo(5));
        }
      }
    });

    test('keşif bitince keşif görevi hiç üretilmez', () {
      // İstanbul'un tamamını gezmiş oyuncuya "4 yeni istasyon keşfet"
      // demek, 0/4'te sonsuza kadar duran bir görev üretiyordu.
      for (var i = 0; i < 40; i++) {
        final missions = generator.missionsFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 2, 1).epochDay + i),
          undiscoveredStations: 0,
        );
        expect(missions, hasLength(3));
        expect(
          missions.map((DailyMission m) => m.type),
          isNot(contains(DailyMissionType.discoverStations)),
        );
      }
    });

    test('kalan durak azsa hedef kırpılır', () {
      // Hedefi kalan durak sayısına indirmek yalnız kolaylaştırır;
      // tamamlanmış bir ilerlemeyi geçersizleştiremez.
      for (var i = 0; i < 40; i++) {
        final missions = generator.missionsFor(
          DayStamp.fromEpochDay(const DayStamp(2026, 2, 1).epochDay + i),
          undiscoveredStations: 2,
        );
        for (final mission in missions) {
          if (mission.type != DailyMissionType.discoverStations) continue;
          expect(mission.target, lessThanOrEqualTo(2));
        }
      }
    });

    test('keşif durumu bilinmiyorsa üretim saf kalır', () {
      const day = DayStamp(2026, 2, 1);
      expect(generator.missionsFor(day), generator.missionsFor(day));
    });

    test('görev metni hedefi içeriyor', () {
      const mission = DailyMission(
        type: DailyMissionType.discoverStations,
        target: 3,
      );
      expect(mission.title, contains('3'));
    });
  });
}
