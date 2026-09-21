import 'package:flutter/foundation.dart';

import 'friend_code.dart';

/// Bir meydan okumanın taşınabilir tanımı.
///
/// Ürünün sosyal çekirdeği: **aynı rota, aynı oyun, aynı koşullar.** Karşı
/// tarafa giden tek şey bu kayıt; oyunun kendisi iki cihazda da yerelde
/// çalışıyor, hiçbir sunucu araya girmiyor.
///
/// Alanlar bilinçli olarak az: QR'a giren her alan hem karekodu büyütüyor
/// hem de doğrulanması gereken bir yüzey açıyor. Rota, durak **kanonik
/// kimlikleriyle** taşınıyor; süre ve durak sayısı karşı tarafta metro
/// verisinden yeniden hesaplanabilir ama süre yine de yazılıyor, çünkü iki
/// cihazın veri dosyası farklı sürümde olabilir ve yolculuğun uzunluğu
/// adaletin parçası.
@immutable
class Challenge {
  const Challenge({
    required this.id,
    required this.gameId,
    required this.lineId,
    required this.originId,
    required this.destinationId,
    required this.estimatedSeconds,
    required this.targetScore,
    required this.seed,
    required this.creatorCode,
    required this.creatorName,
    required this.createdOnEpochDay,
    this.contentVersion = currentContentVersion,
  });

  /// Yük biçiminin sürümü.
  ///
  /// Karekodun ilk alanı. Okuyan taraf tanımadığı sürümü **reddeder**;
  /// tahmin etmeye çalışmaz. Böylece ileride alan eklemek, eski sürümlerde
  /// sessiz yanlış davranış üretmez.
  static const int payloadVersion = 1;

  /// Oyun içeriğinin sürümü.
  ///
  /// Metro Bilgi'nin soru havuzu gibi, tohumdan türeyen ama **veriye bağlı**
  /// diziler için. İki cihazın içeriği farklıysa aynı tohum aynı soruları
  /// vermez; bu alan farkı görünür kılar. Soru veritabanı değiştiğinde
  /// artırılmalı.
  static const int currentContentVersion = 1;

  // --- Sınırlar ---
  //
  // QR kullanıcı denetimindeki veridir. Her sayısal alanın üst ve alt
  // sınırı var; sınır dışı bir değer yükü geçersiz kılar. Amaç
  // kriptografik güvence değil, **saçma girdinin oyunu bozmasını
  // engellemek**: eksi süre, milyarlık hedef, taşan tohum.

  /// En kısa oynanabilir yolculuk (saniye).
  static const int minSeconds = 30;

  /// En uzun yolculuk (saniye) — uçtan uca bir hattın epey üstünde.
  static const int maxSeconds = 7200;

  /// En yüksek kabul edilebilir hedef skor.
  static const int maxTargetScore = 10000000;

  /// Tohumun üst sınırı (32 bit).
  static const int maxSeed = 0xFFFFFFFF;

  /// Görünen adın en fazla uzunluğu.
  static const int maxNameLength = 40;

  /// Bu meydan okumanın kimliği — tekrar kaydı ve rövanş soyağacı için.
  final String id;

  /// Oynanacak oyunun kalıcı kimliği.
  final String gameId;

  final String lineId;

  /// Biniş ve iniş durağının **kanonik** kimlikleri.
  final String originId;
  final String destinationId;

  /// Yolculuğun süresi. Aynı süre, aynı koşul.
  final int estimatedSeconds;

  /// Geçilmesi gereken skor.
  final int targetScore;

  /// Rastgeleliği eşitleyen tohum.
  final int seed;

  /// Meydan okuyanın arkadaş kodu ve görünen adı.
  final String creatorCode;
  final String creatorName;

  /// Oluşturulduğu gün (epoch günü) — saat taşınmıyor, gerek yok.
  final int createdOnEpochDay;

  final int contentVersion;

  String get creatorFormattedCode => FriendCode.format(creatorCode);

  /// Bu yük kendi içinde tutarlı mı?
  ///
  /// Metro verisine bakmaz — o denetim [ChallengeValidator] işi. Burada
  /// yalnızca alanların kendi sınırları var.
  bool get hasSaneFields =>
      id.isNotEmpty &&
      gameId.isNotEmpty &&
      lineId.isNotEmpty &&
      originId.isNotEmpty &&
      destinationId.isNotEmpty &&
      originId != destinationId &&
      estimatedSeconds >= minSeconds &&
      estimatedSeconds <= maxSeconds &&
      targetScore >= 0 &&
      targetScore <= maxTargetScore &&
      seed >= 0 &&
      seed <= maxSeed &&
      creatorName.isNotEmpty &&
      creatorName.length <= maxNameLength &&
      FriendCode.isValid(creatorCode);

  Challenge copyWith({String? id, int? seed, int? targetScore}) => Challenge(
    id: id ?? this.id,
    gameId: gameId,
    lineId: lineId,
    originId: originId,
    destinationId: destinationId,
    estimatedSeconds: estimatedSeconds,
    targetScore: targetScore ?? this.targetScore,
    seed: seed ?? this.seed,
    creatorCode: creatorCode,
    creatorName: creatorName,
    createdOnEpochDay: createdOnEpochDay,
    contentVersion: contentVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Challenge && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Challenge($id, $gameId, $lineId $originId→$destinationId, '
      'hedef $targetScore, tohum $seed)';
}

/// Karekod okunurken çıkabilecek hatalar.
///
/// Her biri oyuncuya **Türkçe ve suçlayıcı olmayan** bir cümleyle
/// karşılık geliyor: karekodun bozuk olması oyuncunun hatası değil.
enum ChallengeError {
  notAChallenge(
    'Bu kare bir meydan okuma değil',
    'Arkadaşının oyundaki meydan okuma karesini okut.',
  ),
  unsupportedVersion(
    'Bu meydan okuma daha yeni bir sürümden',
    'Uygulamayı güncelleyince okunabilecek.',
  ),
  corrupted(
    'Kare okunamadı',
    'Kare eksik ya da bozuk görünüyor. Yeniden okutmayı dene.',
  ),
  unknownGame(
    'Bu oyun burada yok',
    'Meydan okuma tanımadığımız bir oyuna ait.',
  ),
  unknownRoute(
    'Bu rota bulunamadı',
    'Meydan okumadaki duraklar bu sürümün metro verisinde yok.',
  ),
  outOfBounds(
    'Meydan okuma geçersiz',
    'Karedeki değerler tutarsız; oyun bu meydan okumayı kabul etmiyor.',
  ),
  ownChallenge(
    'Bu senin meydan okuman',
    'Kendi karene meydan okuyamazsın; arkadaşına okut.',
  );

  const ChallengeError(this.title, this.detail);

  final String title;
  final String detail;
}

/// Çözümleme sonucu: ya bir meydan okuma, ya bir hata.
@immutable
class ChallengeDecodeResult {
  const ChallengeDecodeResult.success(this.challenge) : error = null;
  const ChallengeDecodeResult.failure(this.error) : challenge = null;

  final Challenge? challenge;
  final ChallengeError? error;

  bool get isValid => challenge != null;
}
