import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_gaming_service.dart';

/// Game Center kimliği — **yalnızca görünen adı** zenginleştirir.
///
/// Köprü Dart tarafına tek bir alan veriyor: `alias`. Gerekçesi Apple'ın
/// kendi davranışında: `GKPlayer.displayName`, bakan kişi oyuncunun
/// arkadaşıysa **gerçek adı** döndürüyor. Bu üründe ad bir karekoda giriyor
/// ve o kareyi tanımadığı biri okuyabiliyor; gerçek adın oraya girmesi kabul
/// edilemez. `alias` Game Center'ın herkese açık takma adı.
///
/// `gamePlayerID` / `teamPlayerID` hiç istenmiyor: geliştirici ekibine
/// kapsamlı teknik kimlikler, arayüzde de yükte de işleri yok.
///
/// **Oyunun ön şartı değil.** Oturum açılamazsa, oyuncu reddederse, cihaz
/// çevrimdışıysa ya da uygulama Game Center'da tanımlı değilse sessizce
/// `null` dönüyor ve oyun yerel kimliğiyle devam ediyor. Bu oyun tünelde
/// oynanıyor; kimliği ağa bağlamak baştan yanlış olurdu.
class GameCenterService implements PlatformGamingService {
  // Alan private, parametre public kalmalı; `this._channel` dışarıdan
  // kullanılamayacak bir ad üretirdi.
  // ignore_for_file: prefer_initializing_formals
  const GameCenterService({
    @visibleForTesting MethodChannel channel = defaultChannel,
  }) : _channel = channel;

  /// Native köprünün kanal adı — Swift tarafıyla birebir aynı.
  static const MethodChannel defaultChannel = MethodChannel(
    'istanbul_metro/game_center',
  );

  final MethodChannel _channel;

  /// Game Center yalnız Apple platformlarında var.
  ///
  /// Android tarafı bilinçli olarak boş: Play Games v2 bir Play Console
  /// uygulama kimliği ve manifest girdisi istiyor; kimlik olmadan SDK
  /// açılışta çöküyor. O yapılandırma hazır olmadan bağlamak, çalışmayan
  /// bir özellik değil **açılmayan bir uygulama** demek.
  @override
  bool get isAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Oturum açma denemesinin en fazla süresi.
  ///
  /// GameKit'in `authenticateHandler`'ı **hiç geri dönmeyebiliyor**: cihaz
  /// çevrimdışıysa, Game Center sunucusu yanıt vermiyorsa ya da uygulama
  /// App Store Connect'te tanımlı değilse çağrı askıda kalıyor. Zaman aşımı
  /// olmadan arayüz sonsuza kadar dönen bir çarkta kalırdı — hem de tam
  /// olarak bu oyunun oynandığı yerde, tünelde.
  static const Duration signInTimeout = Duration(seconds: 12);

  @override
  Future<PlatformPlayer?> signIn() async {
    if (!isAvailable) return null;
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('signIn')
          .timeout(signInTimeout, onTimeout: () => null);
      final alias = result?['alias'];
      if (alias is! String) return null;
      final cleaned = _sanitize(alias);
      return cleaned == null ? null : PlatformPlayer(displayName: cleaned);
    } on MissingPluginException {
      // Köprü kayıtlı değil (ör. testte, ya da eski bir yapı).
      return null;
    } on PlatformException catch (error) {
      debugPrint('Game Center oturumu açılamadı: ${error.message}');
      return null;
    }
  }

  /// Takma adı arayüze ve karekoda girmeden önce temizler.
  ///
  /// Ad Game Center'dan geliyor, yani bizim denetimimiz dışında. Denetim ve
  /// yön değiştirme karakterleri atılıyor (`U+202E` adı ekranda ters
  /// çizdirir), uzunluk kırpılıyor. Karekod çözücüsündeki kuralın aynısı;
  /// ad hangi kapıdan girerse girsin aynı süzgeçten geçiyor.
  static String? _sanitize(String raw) {
    final cleaned = String.fromCharCodes(
      raw.runes.where((int rune) {
        if (rune <= 0x001F || rune == 0x007F) return false;
        if (rune >= 0x200B && rune <= 0x200F) return false;
        if (rune >= 0x2028 && rune <= 0x202E) return false;
        return true;
      }),
    ).trim();
    if (cleaned.isEmpty) return null;
    return cleaned.length > maxNameLength
        ? cleaned.substring(0, maxNameLength)
        : cleaned;
  }

  /// Görünen adın en fazla uzunluğu — karekod yükündekiyle aynı sınır.
  static const int maxNameLength = 40;
}
