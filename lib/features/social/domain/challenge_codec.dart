import 'dart:convert';

import 'challenge.dart';
import 'friend_code.dart';

/// Meydan okumayı karekoda giren metne çevirir ve geri okur.
///
/// Biçim **JSON değil**, alan ayraçlı düz metin. Gerekçe karekodun kendisi:
/// aynı veri JSON'da yaklaşık üç katı yer tutuyor ve karekodun sürümü
/// büyüdükçe modüller küçülüyor — metroda, titreyen bir elde, kirli bir
/// ekrandan okunması zorlaşıyor. Alan ayraçlı biçimde yük ~110 karakter ve
/// karekod rahat okunan bir boyutta kalıyor.
///
/// Okunabilirlikten vazgeçilmedi: biçim satır satır incelenebilir, sürüm
/// numarası başta, alanlar sabit sırada.
///
/// ```text
/// IMG1|1|c7f3a1|blocks|m2|taksim|haciosman|1380|8420|839251|ABCD1234|<ad>|20719|3f2a1b4c
/// ```
class ChallengeCodec {
  const ChallengeCodec._();

  /// Yükün başındaki imza.
  ///
  /// Okuyucunun ilk kararı bu: imza tutmuyorsa kare bu oyuna ait değil ve
  /// tek bir karşılaştırmayla elenir. Kamera her saniye onlarca kare
  /// görüyor; bunların çoğu Wi-Fi şifresi, bağlantı adresi ya da market
  /// barkodu oluyor.
  static const String magic = 'IMG1';

  /// Yükteki toplam parça sayısı: imza, sürüm, 12 alan ve sağlama.
  static const int _fieldCount = 15;

  /// Alan ayracı.
  ///
  /// `|` seçildi çünkü kanonik durak kimliklerinde, hat kimliklerinde ve
  /// oyun kimliklerinde geçmiyor. Görünen ad geçirebilir — o yüzden ad
  /// base64url ile kodlanıyor.
  static const String separator = '|';

  /// Meydan okumayı karekod metnine çevirir.
  static String encode(Challenge challenge) {
    final body = _body(challenge);
    return '$body$separator${_checksum(body)}';
  }

  static String _body(Challenge challenge) => <String>[
    magic,
    '${Challenge.payloadVersion}',
    challenge.id,
    challenge.gameId,
    challenge.lineId,
    challenge.originId,
    challenge.destinationId,
    '${challenge.estimatedSeconds}',
    '${challenge.targetScore}',
    '${challenge.seed}',
    challenge.creatorCode,
    base64Url.encode(utf8.encode(challenge.creatorName)),
    '${challenge.createdOnEpochDay}',
    '${challenge.contentVersion}',
  ].join(separator);

  /// Karekod metnini çözer.
  ///
  /// Metro verisine bakmaz: burada yalnızca **biçim ve sınır** denetimi
  /// var. Rotanın gerçekten var olup olmadığına [ChallengeValidator] bakar.
  /// İkisi ayrı çünkü biri saf metin işi, diğeri veri işi ve saf olan
  /// testte veri yüklemeden çalışabilmeli.
  static ChallengeDecodeResult decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const ChallengeDecodeResult.failure(ChallengeError.notAChallenge);
    }
    final text = raw.trim();
    if (!text.startsWith('$magic$separator')) {
      return const ChallengeDecodeResult.failure(ChallengeError.notAChallenge);
    }

    final parts = text.split(separator);
    // İmza + sürüm + 12 alan + sağlama = 15.
    //
    // Sabit alan sayısı bilinçli: ileride alan eklenirse sürüm numarası da
    // artar ve eski sürümler yükü **reddeder**, sessizce yanlış okumaz.
    if (parts.length != _fieldCount) {
      return const ChallengeDecodeResult.failure(ChallengeError.corrupted);
    }

    final version = int.tryParse(parts[1]);
    if (version == null) {
      return const ChallengeDecodeResult.failure(ChallengeError.corrupted);
    }
    if (version != Challenge.payloadVersion) {
      // İleri sürüm: tahmin etmeye çalışma, açıkça söyle.
      return const ChallengeDecodeResult.failure(
        ChallengeError.unsupportedVersion,
      );
    }

    // Sağlama **çözmeden önce**: bozuk bir yükü ayrıştırmaya çalışmanın
    // anlamı yok ve ayrıştırma ne kadar erken durursa yüzey o kadar küçük.
    final body = parts.sublist(0, parts.length - 1).join(separator);
    if (parts.last != _checksum(body)) {
      return const ChallengeDecodeResult.failure(ChallengeError.corrupted);
    }

    final seconds = int.tryParse(parts[7]);
    final target = int.tryParse(parts[8]);
    final seed = int.tryParse(parts[9]);
    final createdOn = int.tryParse(parts[12]);
    final contentVersion = int.tryParse(parts[13]);
    final code = FriendCode.normalize(parts[10]);
    final name = _decodeName(parts[11]);

    if (seconds == null ||
        target == null ||
        seed == null ||
        createdOn == null ||
        contentVersion == null ||
        code == null ||
        name == null) {
      return const ChallengeDecodeResult.failure(ChallengeError.corrupted);
    }

    final challenge = Challenge(
      id: parts[2],
      gameId: parts[3],
      lineId: parts[4],
      originId: parts[5],
      destinationId: parts[6],
      estimatedSeconds: seconds,
      targetScore: target,
      seed: seed,
      creatorCode: code,
      creatorName: name,
      createdOnEpochDay: createdOn,
      contentVersion: contentVersion,
    );

    if (!challenge.hasSaneFields) {
      return const ChallengeDecodeResult.failure(ChallengeError.outOfBounds);
    }
    return ChallengeDecodeResult.success(challenge);
  }

  /// Görünen adı çözer ve **temizler**.
  ///
  /// Ad karşı cihazdan geliyor, yani denetimimiz dışında. Üç şey yapılıyor:
  /// denetim karakterleri atılıyor (satır sonu ve yönlendirme işaretleri
  /// arayüzü bozabilir), uzunluk kırpılıyor, boş kalırsa reddediliyor.
  /// Ad hiçbir yerde bir kimlik olarak kullanılmıyor — yalnızca çiziliyor.
  static String? _decodeName(String encoded) {
    try {
      final decoded = utf8.decode(base64Url.decode(encoded));
      // Denetim ve yön karakterleri atılıyor: satır sonu arayüzü bozar,
      // `U+202E` (sağdan sola geçersiz kılma) adın ekranda ters
      // görünmesine yol açar. Aralıklar kod noktası olarak yazılıyor ki
      // bu dosyanın kendisi de düz metinde okunabilir kalsın.
      final cleaned = String.fromCharCodes(
        decoded.runes.where(_isDisplaySafe),
      ).trim();
      if (cleaned.isEmpty) return null;
      return cleaned.length > Challenge.maxNameLength
          ? cleaned.substring(0, Challenge.maxNameLength)
          : cleaned;
    } catch (_) {
      return null;
    }
  }

  /// Bu kod noktası ekrana çizilmesi güvenli mi?
  ///
  /// Elenen üç öbek: C0 denetim karakterleri, DEL, ve sıfır genişlikli /
  /// yön değiştirme işaretleri (`U+200B`–`U+200F`, `U+2028`–`U+202E`).
  /// Sonuncusu ciddi: `U+202E` adın geri kalanını ters çizdirir ve
  /// karşındaki oyuncunun adını başka bir şeye benzetmek için kullanılır.
  static bool _isDisplaySafe(int rune) {
    if (rune <= 0x001F || rune == 0x007F) return false;
    if (rune >= 0x200B && rune <= 0x200F) return false;
    if (rune >= 0x2028 && rune <= 0x202E) return false;
    return true;
  }

  /// FNV-1a, 32 bit, sekiz haneli onaltılık.
  ///
  /// **Bütünlük sağlaması, imza değil.** Kırık bir karekodu, yarım okumayı
  /// ve elle düzenlenmiş bir metni yakalar. Kötü niyetli birinin yükü
  /// yeniden sağlamalamasını engellemez — engelleyemez de: gizli anahtar
  /// istemci içinde saklanamaz. Çevrimdışı skorun kriptografik güvencesi
  /// ancak güvenilen bir sunucuyla mümkün; bkz. hile modeli notu.
  static String _checksum(String body) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(body)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
