import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge_codec.dart';

/// Karekod yükü: kodlama, çözme ve **düşmanca girdi**.
///
/// Karekod kullanıcı denetimindeki veri. Testlerin çoğu geçerli yükü değil,
/// geçersiz yükün reddedildiğini sınıyor: çözücü hiçbir girdide çökmemeli
/// ve hiçbir sınır dışı değeri oyuna geçirmemeli.
void main() {
  Challenge sample({
    String id = 'c7f3a1b20de4',
    String gameId = 'blocks',
    String lineId = 'm2',
    String originId = 'taksim',
    String destinationId = 'haciosman',
    int seconds = 1380,
    int target = 8420,
    int seed = 839251,
    String code = 'ABCD1234',
    String name = 'Hızlı Kadıköylü',
  }) => Challenge(
    id: id,
    gameId: gameId,
    lineId: lineId,
    originId: originId,
    destinationId: destinationId,
    estimatedSeconds: seconds,
    targetScore: target,
    seed: seed,
    creatorCode: code,
    creatorName: name,
    createdOnEpochDay: 20719,
  );

  group('gidip gelme', () {
    test('bütün alanlar korunuyor', () {
      final original = sample();
      final decoded = ChallengeCodec.decode(ChallengeCodec.encode(original));

      expect(decoded.isValid, isTrue);
      final result = decoded.challenge!;
      expect(result.id, original.id);
      expect(result.gameId, original.gameId);
      expect(result.lineId, original.lineId);
      expect(result.originId, original.originId);
      expect(result.destinationId, original.destinationId);
      expect(result.estimatedSeconds, original.estimatedSeconds);
      expect(result.targetScore, original.targetScore);
      expect(result.seed, original.seed);
      expect(result.creatorCode, original.creatorCode);
      expect(result.creatorName, original.creatorName);
      expect(result.createdOnEpochDay, original.createdOnEpochDay);
    });

    test('Türkçe karakterli ad bozulmuyor', () {
      final decoded = ChallengeCodec.decode(
        ChallengeCodec.encode(sample(name: 'Şişli Gece Kuşu İğneada')),
      );
      expect(decoded.challenge!.creatorName, 'Şişli Gece Kuşu İğneada');
    });

    test('ayraç içeren ad yükü bozmuyor', () {
      // Ad base64url ile kodlanıyor; `|` içeren bir ad alan sayısını
      // değiştirmemeli.
      final decoded = ChallengeCodec.decode(
        ChallengeCodec.encode(sample(name: 'A|B|C')),
      );
      expect(decoded.isValid, isTrue);
      expect(decoded.challenge!.creatorName, 'A|B|C');
    });

    test('yük karekod için makul boyutta', () {
      final payload = ChallengeCodec.encode(sample());
      // Karekodun okunabilir kalması için yük kısa tutuluyor.
      expect(payload.length, lessThan(160));
    });
  });

  group('reddedilen girdiler', () {
    test('oyuna ait olmayan kare', () {
      for (final raw in <String?>[
        null,
        '',
        'https://ornek.com',
        'WIFI:S:Metro;T:WPA;P:1234;;',
        '8690123456789',
        'IMG2|1|a|b',
      ]) {
        final result = ChallengeCodec.decode(raw);
        expect(result.isValid, isFalse, reason: '$raw');
        expect(result.error, ChallengeError.notAChallenge, reason: '$raw');
      }
    });

    test('desteklenmeyen sürüm açıkça söyleniyor', () {
      final payload = ChallengeCodec.encode(sample());
      final parts = payload.split('|')..[1] = '99';
      final result = ChallengeCodec.decode(parts.join('|'));
      expect(result.error, ChallengeError.unsupportedVersion);
    });

    test('eksik alan', () {
      final payload = ChallengeCodec.encode(sample());
      final parts = payload.split('|')..removeLast();
      expect(
        ChallengeCodec.decode(parts.join('|')).error,
        ChallengeError.corrupted,
      );
    });

    test('bozulmuş sağlama', () {
      final payload = ChallengeCodec.encode(sample());
      // Hedef skoru elle yükseltmek sağlamayı tutturmaz.
      final parts = payload.split('|')..[8] = '999999';
      expect(
        ChallengeCodec.decode(parts.join('|')).error,
        ChallengeError.corrupted,
      );
    });

    test('tek karakter değişimi yakalanıyor', () {
      final payload = ChallengeCodec.encode(sample());
      final broken = payload.replaceRange(20, 21, 'x');
      expect(ChallengeCodec.decode(broken).isValid, isFalse);
    });

    test('sınır dışı sayılar', () {
      // Sağlama yeniden hesaplanarak "geçerli" bir bozuk yük kuruluyor:
      // bütünlük denetimi geçse bile sınır denetimi durduruyor.
      for (final (int index, String value) in <(int, String)>[
        (7, '0'), // süre sıfır
        (7, '999999'), // süre çok uzun
        (8, '-5'), // eksi skor
        (8, '99999999999'), // devasa skor
        (9, '-1'), // eksi tohum
      ]) {
        final parts = ChallengeCodec.encode(sample()).split('|');
        parts[index] = value;
        final body = parts.sublist(0, parts.length - 1).join('|');
        final rebuilt = '$body|${_checksum(body)}';
        final result = ChallengeCodec.decode(rebuilt);
        expect(result.isValid, isFalse, reason: 'alan $index = $value');
      }
    });

    test('boş ad reddediliyor', () {
      final parts = ChallengeCodec.encode(sample()).split('|');
      parts[11] = base64Url.encode(utf8.encode('   '));
      final body = parts.sublist(0, parts.length - 1).join('|');
      expect(
        ChallengeCodec.decode('$body|${_checksum(body)}').isValid,
        isFalse,
      );
    });

    test('geçersiz arkadaş kodu reddediliyor', () {
      final parts = ChallengeCodec.encode(sample()).split('|');
      parts[10] = 'KISA';
      final body = parts.sublist(0, parts.length - 1).join('|');
      expect(
        ChallengeCodec.decode('$body|${_checksum(body)}').isValid,
        isFalse,
      );
    });
  });

  group('ad temizliği', () {
    test('denetim karakterleri atılıyor', () {
      final decoded = ChallengeCodec.decode(
        ChallengeCodec.encode(sample(name: 'Berke\nSatır\tSekme')),
      );
      expect(decoded.challenge!.creatorName, 'BerkeSatırSekme');
    });

    test('yön değiştirme karakteri atılıyor', () {
      // U+202E adın kalanını ters çizdirir; ekranda başka bir şeye
      // benzeyen bir ad üretmek için kullanılır.
      // Kaçış dizisi kod noktasıyla kuruluyor: kaynak dosyanın kendisi de
      // düz metinde ters görünmemeli.
      final name = 'Berke${String.fromCharCode(0x202E)}emzi';
      final decoded = ChallengeCodec.decode(
        ChallengeCodec.encode(sample(name: name)),
      );
      expect(decoded.challenge!.creatorName, 'Berkeemzi');
    });

    test('çok uzun ad kırpılıyor', () {
      final long = 'A' * 200;
      final decoded = ChallengeCodec.decode(
        ChallengeCodec.encode(sample(name: long)),
      );
      expect(decoded.challenge!.creatorName.length, Challenge.maxNameLength);
    });
  });

  test('aynı durak iki kez reddediliyor', () {
    final parts = ChallengeCodec.encode(sample()).split('|');
    parts[6] = parts[5];
    final body = parts.sublist(0, parts.length - 1).join('|');
    expect(ChallengeCodec.decode('$body|${_checksum(body)}').isValid, isFalse);
  });
}

/// Testin kendi FNV-1a sağlaması.
///
/// Kodlayıcının içindekiyle aynı algoritma; kasten yeniden yazıldı ki
/// "bozuk ama sağlaması tutan" yükler kurulabilsin ve sınır denetiminin
/// bütünlük denetiminden **ayrı** çalıştığı gösterilebilsin.
String _checksum(String body) {
  var hash = 0x811C9DC5;
  for (final unit in utf8.encode(body)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
