import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/social/application/game_center_service.dart';
import 'package:istanbul_metro_game/features/social/application/platform_gaming_service.dart';
import 'package:istanbul_metro_game/features/social/application/social_controller.dart';
import 'package:istanbul_metro_game/features/social/domain/social_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Game Center kimliği.
///
/// Sınanan iki söz: dışarı **yalnızca takma ad** çıkıyor, ve platform
/// kimliği hiçbir durumda oyunun ön şartı değil.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> freshStore([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(<String, Object>{...seed});
    final store = LocalStore();
    await store.init();
    return store;
  }

  /// Köprüyü sahteleyip verilen cevabı döndürür.
  void mockBridge(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          GameCenterService.defaultChannel,
          (MethodCall call) async => handler(call),
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(GameCenterService.defaultChannel, null);
    });
  }

  group('köprü', () {
    // Köprü yalnız Apple platformlarında çalışıyor; testte hedef platform
    // varsayılan olarak Android ve `signIn` daha köprüye ulaşmadan `null`
    // dönüyor. Bu doğru davranış, bu yüzden test onu **atlamıyor**, hedefi
    // iOS'a çeviriyor.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Apple dışı platformda hiç denenmiyor', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockBridge((_) => <String, Object?>{'alias': 'Kaptan'});
      expect(const GameCenterService().isAvailable, isFalse);
      expect(await const GameCenterService().signIn(), isNull);
    });
    test('takma ad okunuyor', () async {
      mockBridge((_) => <String, Object?>{'alias': 'MetroKaptani'});
      final player = await const GameCenterService().signIn();
      expect(player?.displayName, 'MetroKaptani');
    });

    test('oturum açılamazsa null, hata yok', () async {
      mockBridge((_) => null);
      expect(await const GameCenterService().signIn(), isNull);
    });

    test('platform hatası yutuluyor', () async {
      mockBridge((_) => throw PlatformException(code: 'GKError'));
      expect(await const GameCenterService().signIn(), isNull);
    });

    test('köprü kayıtlı değilse null', () async {
      // Sahte yok: kanal hiç cevap vermiyor.
      expect(await const GameCenterService().signIn(), isNull);
    });

    test('boş takma ad kabul edilmiyor', () async {
      mockBridge((_) => <String, Object?>{'alias': '   '});
      expect(await const GameCenterService().signIn(), isNull);
    });

    test('takma ad temizleniyor', () async {
      // Ad platformdan geliyor, yani denetimimiz dışında. Yön değiştirme
      // karakteri adı ekranda ters çizdirir; karekod çözücüsüyle aynı
      // süzgeçten geçiyor.
      mockBridge(
        (_) => <String, Object?>{
          'alias': 'Berke${String.fromCharCode(0x202E)}emzi\nX',
        },
      );
      final player = await const GameCenterService().signIn();
      expect(player?.displayName, 'BerkeemziX');
    });

    test('cevap gelmezse zaman aşımıyla vazgeçiliyor', () async {
      // GameKit askıda kalabiliyor; arayüz sonsuza kadar dönen bir çarkta
      // bırakılamaz.
      mockBridge((_) => throw TimeoutException('yanıt yok'));
      expect(await const GameCenterService().signIn(), isNull);
      expect(
        GameCenterService.signInTimeout,
        lessThanOrEqualTo(const Duration(seconds: 15)),
      );
    });

    test('çok uzun takma ad kırpılıyor', () async {
      mockBridge((_) => <String, Object?>{'alias': 'A' * 200});
      final player = await const GameCenterService().signIn();
      expect(player!.displayName.length, GameCenterService.maxNameLength);
    });
  });

  group('kimlik bağlama', () {
    /// Her zaman başarılı olan sahte platform.
    SocialController build(
      LocalStore store, {
      PlatformGamingService platform = const UnavailableGamingService(),
    }) {
      final social = SocialController(store: store, platform: platform);
      addTearDown(social.dispose);
      return social;
    }

    test('platform yoksa yerel ad kullanılıyor', () async {
      final store = await freshStore();
      final social = build(store);

      expect(social.canLinkPlatform, isFalse);
      expect(social.isPlatformLinked, isFalse);
      expect(social.me.displayName, store.playerName);
      expect(social.me.source, PlayerIdentitySource.local);
      // Bağlanma denemesi sessizce başarısız; hiçbir şey değişmiyor.
      expect(await social.linkPlatformIdentity(), isFalse);
      expect(social.me.displayName, store.playerName);
    });

    test('bağlanınca görünen ad platformdan geliyor', () async {
      final store = await freshStore();
      final social = build(store, platform: const _FakePlatform('Kaptan'));

      expect(await social.linkPlatformIdentity(), isTrue);
      expect(social.me.displayName, 'Kaptan');
      expect(social.me.source, PlayerIdentitySource.gameCenter);
      expect(social.isPlatformLinked, isTrue);
    });

    test('arkadaş kodu bağlanınca değişmiyor', () async {
      final store = await freshStore();
      final social = build(store, platform: const _FakePlatform('Kaptan'));
      final before = social.me.code;

      await social.linkPlatformIdentity();
      // Kod paylaşıldıktan sonra değişirse karşı tarafın kaydı sahipsiz
      // kalırdı.
      expect(social.me.code, before);
    });

    test('ad kalıcı: çevrimdışı açılışta da duruyor', () async {
      final store = await freshStore();
      final first = build(store, platform: const _FakePlatform('Kaptan'));
      await first.linkPlatformIdentity();

      // İkinci açılışta platform hiç çağrılmıyor; ad kayıttan geliyor.
      final second = build(store);
      expect(second.me.displayName, 'Kaptan');
      expect(second.isPlatformLinked, isTrue);
    });

    test('bağlantı kaldırılınca yerel ada dönülüyor', () async {
      final store = await freshStore();
      final social = build(store, platform: const _FakePlatform('Kaptan'));
      await social.linkPlatformIdentity();

      await social.unlinkPlatformIdentity();
      expect(social.me.displayName, store.playerName);
      expect(social.isPlatformLinked, isFalse);
      // Kayıt da silinmiş olmalı.
      expect(build(store).isPlatformLinked, isFalse);
    });

    test('oturum açılamazsa hiçbir şey değişmiyor', () async {
      final store = await freshStore();
      final social = build(store, platform: const _FakePlatform(null));

      expect(await social.linkPlatformIdentity(), isFalse);
      expect(social.me.displayName, store.playerName);
      expect(social.isPlatformLinked, isFalse);
    });

    test('meydan okumaya platform adı giriyor', () async {
      final store = await freshStore();
      final social = build(store, platform: const _FakePlatform('Kaptan'));
      await social.linkPlatformIdentity();

      // Karekoda giren ad görünen ad; ham platform kimliği hiçbir yerde yok.
      expect(social.me.displayName, 'Kaptan');
    });
  });
}

/// Verilen adı döndüren sahte platform; `null` ise oturum açılamıyor.
class _FakePlatform implements PlatformGamingService {
  const _FakePlatform(this._alias);

  final String? _alias;

  @override
  bool get isAvailable => true;

  @override
  Future<PlatformPlayer?> signIn() async =>
      _alias == null ? null : PlatformPlayer(displayName: _alias);
}
