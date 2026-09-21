import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/app/routes.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge_codec.dart';
import 'package:istanbul_metro_game/features/social/presentation/add_friend_screen.dart';
import 'package:istanbul_metro_game/features/social/presentation/challenge_preview_screen.dart';
import 'package:istanbul_metro_game/features/social/presentation/challenge_share_screen.dart';
import 'package:istanbul_metro_game/features/social/presentation/friends_screen.dart';
import 'package:istanbul_metro_game/features/social/presentation/widgets/challenge_qr_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// V5a'nın ekrandaki hâli.
///
/// Sınanan söz: sosyal katman **ağsız** çalışıyor. Bu testlerin hiçbiri ağ
/// kullanmıyor ve uygulama da kullanmıyor — kimlik, arkadaş listesi, meydan
/// okuma üretimi ve karekod tamamen cihazda.
void main() {
  final metro = MetroFixture.load();

  Future<LocalStore> storeWith([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
      ...seed,
    });
    final store = LocalStore();
    await store.init();
    return store;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    LocalStore store, {
    Size size = const Size(1170, 2532),
    double pixelRatio = 3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      MetroGameApp(store: store, audio: AudioService(), metro: metro),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFriends(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Arkadaşlar'));
    await tester.pumpAndSettle();
  }

  /// Kaydı hazır bir arkadaş listesi.
  String friendsJson(List<(String, String)> entries) =>
      '[${entries.map((e) => '{"code":"${e.$1}","name":"${e.$2}",'
          '"stations":12,"added":"2026-09-20"}').join(',')}]';

  group('Arkadaşlar', () {
    testWidgets('ana ekrandan açılıyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openFriends(tester);

      expect(find.byType(FriendsScreen), findsOneWidget);
      expect(find.text('ARKADAŞLAR'), findsOneWidget);
    });

    testWidgets('kimlik kartı ad ve kod gösteriyor', (tester) async {
      final store = await storeWith();
      await pumpApp(tester, store);
      await openFriends(tester);

      expect(find.text(store.playerName), findsOneWidget);
      // Kod tireli biçimde: ABCD-1234.
      expect(find.textContaining(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')),
          findsOneWidget);
    });

    testWidgets('boş durumda davet çıkıyor, ölü ekran yok', (tester) async {
      await pumpApp(tester, await storeWith());
      await openFriends(tester);

      expect(find.text('AYNI YOLCULUK. KİM DAHA İYİ?'), findsOneWidget);
      expect(find.textContaining('İnternet gerekmiyor'), findsOneWidget);
      expect(find.text('ARKADAŞLARIM'), findsNothing);
    });

    testWidgets('dolu liste arkadaşları gösteriyor', (tester) async {
      await pumpApp(
        tester,
        await storeWith(<String, Object>{
          'friends_v1': friendsJson(<(String, String)>[
            ('ABCD1234', 'Berke'),
            ('BBCD1234', 'Emir'),
          ]),
        }),
      );
      await openFriends(tester);

      expect(find.text('ARKADAŞLARIM'), findsOneWidget);
      expect(find.text('Berke'), findsOneWidget);
      expect(find.text('Emir'), findsOneWidget);
    });

    testWidgets('uzun ad taşırmıyor', (tester) async {
      await pumpApp(
        tester,
        await storeWith(<String, Object>{
          'friends_v1': friendsJson(<(String, String)>[
            ('ABCD1234', 'Sancaktepe Şehir Hastanesi Yolcusu Mehmet Ali'),
          ]),
        }),
        size: const Size(320, 568),
        pixelRatio: 1,
      );
      await openFriends(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('Arkadaş ekle', () {
    Future<void> openAdd(WidgetTester tester) async {
      await openFriends(tester);
      await tester.tap(find.text('ARKADAŞ EKLE'));
      await tester.pumpAndSettle();
    }

    testWidgets('kendi kodum ve karesi görünüyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openAdd(tester);

      expect(find.byType(AddFriendScreen), findsOneWidget);
      expect(find.text('METRO KODUN'), findsOneWidget);
      // Karekod cihazda üretiliyor; ağ yok.
      expect(find.byType(ChallengeQrView), findsOneWidget);
    });

    testWidgets('kod yazarak arkadaş eklenebiliyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openAdd(tester);

      await tester.enterText(find.byType(TextField).first, 'abcd-1234');
      await tester.enterText(find.byType(TextField).last, 'Berke');
      await tester.tap(find.text('EKLE'));
      await tester.pumpAndSettle();

      expect(find.text('Arkadaş eklendi'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Berke'), findsOneWidget);
    });

    testWidgets('kendi kodunu eklemek engelleniyor', (tester) async {
      final store = await storeWith();
      await pumpApp(tester, store);
      await openAdd(tester);

      final myCode = store.friendCode!;
      await tester.enterText(find.byType(TextField).first, myCode);
      await tester.tap(find.text('EKLE'));
      await tester.pumpAndSettle();

      expect(find.text('Bu senin kendi kodun'), findsOneWidget);
    });

    testWidgets('geçersiz kod açıkça söyleniyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openAdd(tester);

      await tester.enterText(find.byType(TextField).first, 'KISA');
      await tester.tap(find.text('EKLE'));
      await tester.pumpAndSettle();

      expect(find.text('Kod okunamadı'), findsOneWidget);
    });

    testWidgets('aynı kod iki kez eklenmiyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openAdd(tester);

      for (var i = 0; i < 2; i++) {
        await tester.enterText(find.byType(TextField).first, 'ABCD1234');
        await tester.tap(find.text('EKLE'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Bu oyuncu zaten listende'), findsOneWidget);
    });
  });

  group('Arkadaş karesi', () {
    test('yük çözülüyor', () {
      final invite = FriendInvite.decode('IMGF|1|ABCD1234|Berke');
      expect(invite, isNotNull);
      expect(invite!.code, 'ABCD1234');
      expect(invite.displayName, 'Berke');
    });

    test('meydan okuma karesi arkadaş kartı sayılmıyor', () {
      // İki yük ayrı imza taşıyor; tarayıcı yanlış ekrana götürmüyor.
      expect(FriendInvite.decode('IMG1|1|abc|blocks'), isNull);
      expect(FriendInvite.decode('https://ornek.com'), isNull);
      expect(FriendInvite.decode(null), isNull);
      expect(FriendInvite.decode('IMGF|9|ABCD1234|Berke'), isNull);
      expect(FriendInvite.decode('IMGF|1|KISA|Berke'), isNull);
    });
  });

  group('Meydan okuma önizleme', () {
    // Süre gerçek rotadan alınıyor: doğrulayıcı karekodtaki süreyi yerel
    // hesapla karşılaştırıyor ve uydurma bir süre reddedilirdi.
    final realSeconds = RouteService(metro)
        .estimate('m2_taksim', 'm2_levent')
        .journey!
        .estimatedSeconds;

    Challenge build({String gameId = 'blocks', String originId = 'taksim'}) =>
        Challenge(
          id: 'abc123def456',
          gameId: gameId,
          lineId: 'M2',
          originId: originId,
          destinationId: 'levent',
          estimatedSeconds: realSeconds,
          targetScore: 8420,
          seed: 839251,
          creatorCode: 'ABCD1234',
          creatorName: 'Berke',
          createdOnEpochDay: 20719,
        );

    testWidgets('geçerli kare hedefi ve rotayı gösteriyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openFriends(tester);
      final context = tester.element(find.byType(FriendsScreen));
      Navigator.of(
        context,
      ).pushNamed(AppRoutes.challengePreview, arguments: build());
      await tester.pumpAndSettle();

      expect(find.byType(ChallengePreviewScreen), findsOneWidget);
      expect(find.textContaining('Berke sana meydan okuyor'), findsOneWidget);
      expect(find.text('8.420'), findsOneWidget);
      expect(find.text('KABUL ET'), findsOneWidget);
      // Önizleme oyunu **başlatmıyor**.
      expect(find.text('AYNI ROTA · AYNI OYUN · AYNI SÜRE'), findsOneWidget);
    });

    testWidgets('tanınmayan rota nazik hata gösteriyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openFriends(tester);
      final context = tester.element(find.byType(FriendsScreen));
      Navigator.of(context).pushNamed(
        AppRoutes.challengePreview,
        arguments: build(originId: 'yok_boyle_durak'),
      );
      await tester.pumpAndSettle();

      expect(find.text(ChallengeError.unknownRoute.title), findsOneWidget);
      expect(find.text('KABUL ET'), findsNothing);
    });
  });

  group('Meydan okuma paylaşımı', () {
    testWidgets('kare ve hedef görünüyor', (tester) async {
      await pumpApp(tester, await storeWith());
      await openFriends(tester);
      final context = tester.element(find.byType(FriendsScreen));
      final challenge = Challenge(
        id: 'abc123def456',
        gameId: 'blocks',
        lineId: 'M2',
        originId: 'taksim',
        destinationId: 'levent',
        estimatedSeconds: 300,
        targetScore: 8420,
        seed: 839251,
        creatorCode: 'ABCD1234',
        creatorName: 'Berke',
        createdOnEpochDay: 20719,
      );
      Navigator.of(context).pushNamed(
        AppRoutes.challengeShare,
        arguments: ChallengeShareArgs(challenge: challenge),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChallengeShareScreen), findsOneWidget);
      expect(find.text('MEYDAN OKUMA HAZIR'), findsOneWidget);
      expect(find.byType(ChallengeQrView), findsOneWidget);
      // Karekodun içeriği gerçekten çözülebilir olmalı.
      final view = tester.widget<ChallengeQrView>(
        find.byType(ChallengeQrView),
      );
      expect(ChallengeCodec.decode(view.data).isValid, isTrue);
    });
  });
}
