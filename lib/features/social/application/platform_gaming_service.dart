import 'package:flutter/foundation.dart';

/// Platform oyun servisinden gelen, **gösterime güvenli** kimlik.
///
/// Ham `gamePlayerID` / `teamPlayerID` ya da Play Games oyuncu kimliği
/// buraya girmez: bunlar geliştirici ekibine kapsamlı teknik kimliklerdir,
/// arayüzde gösterilmeleri ve karekoda yazılmaları yanlış olur.
@immutable
class PlatformPlayer {
  const PlatformPlayer({required this.displayName});

  final String displayName;
}

/// Game Center / Play Games köprüsü.
///
/// **Bugün hiçbir gerçeklemesi yok ve bu bilinçli bir karar.** Gerekçe iki
/// platformun da kendi kurallarında yazılı:
///
/// - **Game Center**: `GKLocalPlayer.loadFriends` yalnızca oyuncu açıkça
///   izin verirse ve yaş/ebeveyn kısıtları elverirse çalışır; salt okunur.
///   GameKit oyuna arkadaş **ekleme**, oyuncu **arama** ya da istek
///   **gönderme** yetkisi vermez.
/// - **Play Games v2**: arkadaş listesi onay kapılıdır
///   (`FriendsResolutionRequiredException`) ve yine salt okunurdur; oyun
///   programatik olarak arkadaş ekleyemez, ad ile oyuncu arayamaz, istek
///   gönderemez. Gerçek zamanlı ve sıra tabanlı çok oyuncu API'leri
///   kaldırılmıştır.
///
/// Yani V5a'nın istediği "oyun içinde arkadaş ekle" akışını **hiçbir
/// platform sağlamıyor**. Arkadaş katmanı uygulamanın kendisine ait olmak
/// zorunda; arka uç da olmadığı için cihazda yaşıyor.
///
/// Platform kimliğinin bu üründe yapabileceği tek şey **görünen adı
/// zenginleştirmek**. O da çekirdek oyunun ön şartı olamaz: oyun metroda,
/// tünelde, uçak modunda oynanıyor. Bu arayüz o günü hazırlıyor;
/// bağlandığında Arkadaşlar arayüzünün tek satırı değişmeyecek.
abstract class PlatformGamingService {
  /// Bu cihazda platform kimliği kullanılabilir mi?
  bool get isAvailable;

  /// Oturum açmayı dener. Kullanılamıyorsa ya da oyuncu reddederse `null`.
  Future<PlatformPlayer?> signIn();
}

/// Varsayılan gerçekleme: platform kimliği yok.
///
/// Sessizce `null` döner. Uygulama bunun üstüne bir hata durumu kurmaz —
/// platform kimliği bir **zenginleştirme**, eksikliği bir arıza değil.
class UnavailableGamingService implements PlatformGamingService {
  const UnavailableGamingService();

  @override
  bool get isAvailable => false;

  @override
  Future<PlatformPlayer?> signIn() async => null;
}
