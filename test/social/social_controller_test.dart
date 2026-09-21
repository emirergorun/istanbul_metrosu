import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/discovery/application/discovery_controller.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/social/application/social_controller.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge_record.dart';
import 'package:istanbul_metro_game/features/social/domain/friend.dart';
import 'package:istanbul_metro_game/features/social/domain/friend_code.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Kimlik, arkadaş listesi ve meydan okuma geçmişi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final routes = RouteService(metro);

  Future<LocalStore> freshStore([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{...seed});
    final store = LocalStore();
    await store.init();
    return store;
  }

  SocialController build(LocalStore store, {int randomSeed = 1}) {
    final discovery = DiscoveryController(catalog: catalog, store: store);
    addTearDown(discovery.dispose);
    final social = SocialController(
      store: store,
      discovery: discovery,
      random: Random(randomSeed),
    );
    addTearDown(social.dispose);
    return social;
  }

  Journey journey() => routes.estimate('m2_taksim', 'm2_levent').journey!;

  group('kimlik', () {
    test('arkadaş kodu ilk açılışta üretilir', () async {
      final store = await freshStore();
      final social = build(store);

      expect(FriendCode.isValid(social.me.code), isTrue);
      expect(social.me.formattedCode, contains('-'));
    });

    test('kod yeniden açılışta değişmez', () async {
      final store = await freshStore();
      final first = build(store).me.code;
      // Kod paylaşıldıktan sonra değişirse karşı tarafın kaydı sahipsiz
      // kalır.
      expect(build(store, randomSeed: 99).me.code, first);
    });

    test('ad yerel kimlikten geliyor', () async {
      final store = await freshStore();
      final social = build(store);
      expect(social.me.displayName, store.playerName);
      expect(social.me.displayName, isNotEmpty);
    });

    test('unvan keşiften türüyor, uydurulmuyor', () async {
      final store = await freshStore(<String, Object>{
        'discovered_stations': catalog.stations
            .take(30)
            .map((CanonicalStation s) => s.id)
            .toList(),
      });
      final social = build(store);
      expect(social.me.stationsDiscovered, 30);
      expect(social.me.title, 'Hat Gezgini');
    });
  });

  group('arkadaş ekleme', () {
    test('geçerli kod ekleniyor', () async {
      final social = build(await freshStore());
      expect(
        social.addFriend(rawCode: 'ABCD-1234', displayName: 'Berke'),
        FriendAddResult.added,
      );
      expect(social.friends, hasLength(1));
      expect(social.friends.first.displayName, 'Berke');
    });

    test('kendini ekleyemezsin', () async {
      final social = build(await freshStore());
      expect(
        social.addFriend(rawCode: social.me.code, displayName: 'Ben'),
        FriendAddResult.self,
      );
      expect(social.friends, isEmpty);
    });

    test('aynı kişi iki kez eklenmiyor', () async {
      final social = build(await freshStore());
      social.addFriend(rawCode: 'ABCD-1234', displayName: 'Berke');
      expect(
        social.addFriend(rawCode: 'abcd1234', displayName: 'Berke tekrar'),
        FriendAddResult.alreadyAdded,
      );
      expect(social.friends, hasLength(1));
    });

    test('aynı kare tekrar okunsa da tek kayıt', () async {
      final social = build(await freshStore());
      for (var i = 0; i < 5; i++) {
        social.addFriend(rawCode: 'ABCD-1234', displayName: 'Berke');
      }
      expect(social.friends, hasLength(1));
    });

    test('geçersiz kod reddediliyor', () async {
      final social = build(await freshStore());
      for (final bad in <String?>[null, '', 'KISA', 'ABCD!234']) {
        expect(
          social.addFriend(rawCode: bad, displayName: 'X'),
          FriendAddResult.invalid,
        );
      }
      expect(social.friends, isEmpty);
    });

    test('boş ad reddediliyor', () async {
      final social = build(await freshStore());
      expect(
        social.addFriend(rawCode: 'ABCD-1234', displayName: '   '),
        FriendAddResult.invalid,
      );
    });

    test('liste ada göre sıralı', () async {
      final social = build(await freshStore());
      social.addFriend(rawCode: 'ABCD1234', displayName: 'Zeynep');
      social.addFriend(rawCode: 'BBCD1234', displayName: 'Ahmet');
      expect(
        social.friends.map((Friend f) => f.displayName),
        <String>['Ahmet', 'Zeynep'],
      );
    });

    test('çıkarma çalışıyor', () async {
      final social = build(await freshStore());
      social.addFriend(rawCode: 'ABCD1234', displayName: 'Berke');
      social.removeFriend('abcd-1234');
      expect(social.friends, isEmpty);
    });

    test('liste yeniden açılışta geri geliyor', () async {
      final store = await freshStore();
      final first = build(store);
      first.addFriend(rawCode: 'ABCD1234', displayName: 'Berke');
      await first.flush();

      final second = build(store);
      expect(second.friends, hasLength(1));
      expect(second.friends.first.code, 'ABCD1234');
    });

    test('bozuk kayıt listeyi boşaltır ama çökmez', () async {
      final store = await freshStore(<String, Object>{'friends_v1': '{bozuk'});
      expect(build(store).friends, isEmpty);
    });
  });

  group('meydan okuma', () {
    test('koşudan meydan okuma üretiliyor', () async {
      final social = build(await freshStore());
      final challenge = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 8420,
      );

      expect(challenge.targetScore, 8420);
      expect(challenge.gameId, 'blocks');
      expect(challenge.creatorCode, social.me.code);
      expect(challenge.hasSaneFields, isTrue);
      // Rota kanonik kimliklerle taşınıyor, hat kapsamlı olanlarla değil.
      expect(challenge.originId, 'taksim');
    });

    test('her meydan okuma yeni kimlik ve tohum alıyor', () async {
      final social = build(await freshStore());
      final a = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 10,
      );
      final b = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 10,
      );
      expect(a.id, isNot(b.id));
      expect(a.seed, isNot(b.seed));
    });
  });

  group('sonuç ve geçmiş', () {
    test('kazanma, kaybetme ve beraberlik', () {
      expect(
        ChallengeOutcome.compare(mine: 100, target: 90),
        ChallengeOutcome.won,
      );
      expect(
        ChallengeOutcome.compare(mine: 80, target: 90),
        ChallengeOutcome.lost,
      );
      expect(
        ChallengeOutcome.compare(mine: 90, target: 90),
        ChallengeOutcome.tied,
      );
    });

    test('sonuç kaydediliyor', () async {
      final social = build(await freshStore());
      final challenge = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 5000,
      );

      final record = social.recordResult(
        challenge: challenge,
        journey: journey(),
        myScore: 6200,
      );

      expect(record, isNotNull);
      expect(record!.outcome, ChallengeOutcome.won);
      expect(record.difference, 1200);
      expect(social.history, hasLength(1));
    });

    test('aynı meydan okuma iki kez kaydedilmiyor', () async {
      final social = build(await freshStore());
      final challenge = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 5000,
      );

      social.recordResult(
        challenge: challenge,
        journey: journey(),
        myScore: 6200,
      );
      final second = social.recordResult(
        challenge: challenge,
        journey: journey(),
        myScore: 9999,
      );

      expect(second, isNull);
      expect(social.history, hasLength(1));
      expect(social.history.first.myScore, 6200);
    });

    test('geçmiş yeniden açılışta duruyor', () async {
      final store = await freshStore();
      await withClock(Clock.fixed(DateTime(2026, 9, 20)), () async {
        final first = build(store);
        final challenge = first.createChallenge(
          journey: journey(),
          gameId: 'blocks',
          score: 100,
        );
        first.recordResult(
          challenge: challenge,
          journey: journey(),
          myScore: 200,
        );
        await first.flush();
      });

      final second = build(store);
      expect(second.history, hasLength(1));
      expect(second.history.first.myScore, 200);
      expect(second.history.first.outcome, ChallengeOutcome.won);
    });

    test('geçmiş sınırlı kalıyor', () async {
      final social = build(await freshStore());
      for (var i = 0; i < SocialController.maxHistory + 10; i++) {
        final challenge = social.createChallenge(
          journey: journey(),
          gameId: 'blocks',
          score: i,
        );
        social.recordResult(
          challenge: challenge,
          journey: journey(),
          myScore: i + 1,
        );
      }
      expect(social.history, hasLength(SocialController.maxHistory));
    });
  });

  group('rövanş', () {
    test('rota ve oyun aynı, tohum yeni', () async {
      final social = build(await freshStore());
      final challenge = social.createChallenge(
        journey: journey(),
        gameId: 'blocks',
        score: 5000,
      );
      final record = social.recordResult(
        challenge: challenge,
        journey: journey(),
        myScore: 6200,
      )!;

      final rematch = social.rematchFrom(record);

      expect(rematch.gameId, challenge.gameId);
      expect(rematch.originId, challenge.originId);
      expect(rematch.destinationId, challenge.destinationId);
      expect(rematch.estimatedSeconds, challenge.estimatedSeconds);
      // Hedef artık **senin** skorun: sıra karşı tarafta.
      expect(rematch.targetScore, 6200);
      // Tohum tazeleniyor: aynı tohum ikinci turda ezbere avantaj verirdi.
      expect(rematch.seed, isNot(challenge.seed));
      expect(rematch.id, isNot(challenge.id));
      expect(rematch.creatorCode, social.me.code);
    });
  });
}
