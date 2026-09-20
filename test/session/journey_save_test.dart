import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_host.dart';
import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Yarım kalan yolculuğun diske yazılması ve geri gelmesi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final routes = RouteService(MetroFixture.load());

  JourneySave sample() => JourneySave(
    originId: 'm2_taksim',
    destinationId: 'm2_levent',
    elapsedSeconds: 143.5,
    score: 820,
    scoreByGame: const <String, int>{'blocks': 500, 'journey': 320},
    secondsByGame: const <String, double>{'blocks': 120},
    stationsPassed: 2,
    recordToBeat: 900,
    recordBeaten: false,
    activeGameId: 'blocks',
    gamePayload: '{"v":4}',
    savedAt: DateTime.utc(2026, 9, 20, 12),
  );

  Future<LocalStore> storeWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = LocalStore();
    await store.init();
    return store;
  }

  group('yolculuk zarfı', () {
    test('gidiş-dönüş bütün alanları korur', () {
      final restored = JourneySave.decode(sample().encode())!;

      expect(restored.originId, 'm2_taksim');
      expect(restored.destinationId, 'm2_levent');
      expect(restored.elapsedSeconds, 143.5);
      expect(restored.score, 820);
      expect(restored.scoreByGame, <String, int>{
        'blocks': 500,
        'journey': 320,
      });
      expect(restored.stationsPassed, 2);
      expect(restored.recordToBeat, 900);
      expect(restored.recordBeaten, isFalse);
      expect(restored.activeGameId, 'blocks');
      expect(restored.gamePayload, '{"v":4}');
    });

    test('bozuk JSON çökmez', () {
      expect(JourneySave.decode('{bu json degil'), isNull);
    });

    test('bilinmeyen sürüm atılır', () {
      final json = jsonDecode(sample().encode()) as Map<String, dynamic>;
      json['v'] = JourneySave.version + 1;

      expect(JourneySave.decode(jsonEncode(json)), isNull);
    });

    test('eski Blok Metro kaydı zarfa çevrilir', () {
      // Ortak yolculuktan önceki biçim: tahta ve yolculuk aynı kayıtta.
      final legacy = jsonEncode(<String, dynamic>{
        'v': 3,
        'origin': 'm2_taksim',
        'destination': 'm2_levent',
        'board': <List<int>>[],
        'score': 240,
        'elapsed': 90,
        'stationsPassed': 1,
        'record': 300,
        'recordBeaten': false,
      });

      final save = JourneySave.fromLegacyGameSave(legacy, gameId: 'blocks')!;

      expect(save.score, 240);
      expect(save.elapsedSeconds, 90);
      expect(save.stationsPassed, 1);
      expect(save.recordToBeat, 300);
      expect(save.scoreByGame['blocks'], 240);
      // Tahta olduğu gibi taşınır: zarf içine bakmaz.
      expect(save.gamePayload, legacy);
    });
  });

  group('açılışta geri gelen yolculuk', () {
    test('puan, süre ve durak korunur', () async {
      final store = await storeWith(<String, Object>{
        'journey_save': sample().encode(),
      });
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);

      final session = host.restore()!;

      expect(session.score, 820);
      expect(session.elapsedSeconds, 143.5);
      expect(session.stationsPassed, 2);
      expect(session.scoreOf('blocks'), 500);
      expect(session.status, GameStatus.playing);
      expect(host.payloadFor('blocks'), '{"v":4}');
    });

    test('kapalı geçen süre yolculuğa eklenmez', () async {
      // Kayıt bir yıl önce yazılmış olsa da tren o kadar yol almadı.
      final old = JourneySave(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        elapsedSeconds: 60,
        score: 100,
        scoreByGame: const <String, int>{'blocks': 100},
        secondsByGame: const <String, double>{'blocks': 40},
        stationsPassed: 0,
        recordToBeat: 0,
        recordBeaten: false,
        savedAt: DateTime.utc(2020),
      );
      final store = await storeWith(<String, Object>{
        'journey_save': old.encode(),
      });
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);

      final session = host.restore()!;

      expect(session.elapsedSeconds, 60);
    });

    test('eski biçimdeki kayıt da diriltilir', () async {
      final legacy = jsonEncode(<String, dynamic>{
        'v': 3,
        'origin': 'm2_taksim',
        'destination': 'm2_levent',
        'score': 240,
        'elapsed': 90,
        'stationsPassed': 1,
        'record': 300,
        'recordBeaten': false,
      });
      final store = await storeWith(<String, Object>{'saved_game': legacy});
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);

      final session = host.restore()!;

      expect(session.score, 240);
      expect(session.elapsedSeconds, 90);
      expect(host.payloadFor('blocks'), legacy);
    });

    test('rotası okunamayan kayıt sessizce atılır', () async {
      final broken = jsonEncode(<String, dynamic>{
        'v': JourneySave.version,
        'origin': 'artik_olmayan_durak',
        'destination': 'm2_levent',
        'elapsed': 10.0,
        'score': 10,
        'scoreByGame': <String, int>{},
        'secondsByGame': <String, double>{},
        'stations': 0,
        'record': 0,
        'recordBeaten': false,
        'activeGame': null,
        'gamePayload': null,
        'savedAt': DateTime.utc(2026).toIso8601String(),
      });
      final store = await storeWith(<String, Object>{'journey_save': broken});
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);

      expect(host.restore(), isNull);
    });

    test('yolculuk kapanınca kayıt silinir', () async {
      final store = await storeWith(<String, Object>{
        'journey_save': sample().encode(),
      });
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);
      host.restore();

      host.close();
      await Future<void>.delayed(Duration.zero);

      expect(store.savedJourney, isNull);
      expect(store.savedGame, isNull);
      expect(store.bestJourneyScore('m2_taksim', 'm2_levent'), 820);
    });

    test('bozuk oyun yükü yolculuğu düşürmez', () async {
      final save = JourneySave(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        elapsedSeconds: 30,
        score: 70,
        scoreByGame: const <String, int>{'blocks': 70},
        secondsByGame: const <String, double>{'blocks': 20},
        stationsPassed: 0,
        recordToBeat: 0,
        recordBeaten: false,
        activeGameId: 'blocks',
        gamePayload: 'bu json degil',
        savedAt: DateTime.utc(2026),
      );
      final store = await storeWith(<String, Object>{
        'journey_save': save.encode(),
      });
      final host = JourneyController(store: store, routes: routes);
      addTearDown(host.dispose);

      final session = host.restore()!;

      expect(session.score, 70);
      // Yük ekranda çözülür; çözülemezse oyun sıfırdan başlar, yolculuk sürer.
      expect(host.payloadFor('blocks'), 'bu json degil');
    });
  });
}
