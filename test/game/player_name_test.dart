import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/player/domain/player_name.dart';
import 'package:istanbul_metro_game/features/player/domain/share_card.dart';

/// Oyuncu adı ve paylaşım metni.
///
/// Serbest metin kullanıcı adı bilinçli olarak reddedildi; bu testler o
/// kararın kodda gerçekten uygulandığını doğruluyor.
void main() {
  group('oyuncu adı', () {
    test('havuz yeterince büyük', () {
      // Aynı adı iki oyuncunun alması sorun değil (rekorlar cihazda),
      // ama seçim ekranı birkaç yenilemede tekrara düşmemeli.
      expect(PlayerName.combinationCount, greaterThanOrEqualTo(3000));
    });

    test('üretilen her ad sözlükten geçer', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final name = PlayerName.random(random);
        expect(PlayerName.isValid(name), isTrue, reason: name);
      }
    });

    test('sözlük dışı ad kabul edilmez', () {
      for (final bad in <String>[
        'ahmet1234',
        'Hızlı',
        '',
        'Küfür Kelimesi',
        'Hızlı Kelime',
        'Rastgele Yolcu',
      ]) {
        expect(PlayerName.isValid(bad), isFalse, reason: bad);
      }
    });

    test('sözlükte tekrar eden kelime yok', () {
      expect(
        PlayerName.adjectives.toSet(),
        hasLength(PlayerName.adjectives.length),
      );
      expect(PlayerName.nouns.toSet(), hasLength(PlayerName.nouns.length));
    });

    test('sonek okunması kolay karakterlerden oluşur', () {
      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        final tag = PlayerName.discriminator(random);
        expect(tag, hasLength(4));
        // 0/O ve 1/I karışmasın diye bu karakterler havuzda yok.
        expect(tag.contains('0'), isFalse);
        expect(tag.contains('O'), isFalse);
        expect(tag.contains('1'), isFalse);
        expect(tag.contains('I'), isFalse);
      }
    });
  });

  group('paylaşım metni', () {
    test('rota deseni geçilen durakları dolu gösterir', () {
      final pattern = ShareCard.route(stops: 5, passedStops: 2);
      expect(pattern.split(ShareCard.link), hasLength(5));
      expect(ShareCard.passed.allMatches(pattern), hasLength(2));
      expect(ShareCard.remaining.allMatches(pattern), hasLength(3));
    });

    test('uzun rotada desen örneklenir, oran korunur', () {
      final pattern = ShareCard.route(stops: 32, passedStops: 16);
      expect(pattern.split(ShareCard.link), hasLength(ShareCard.maxDots));
      expect(
        ShareCard.passed.allMatches(pattern),
        hasLength(ShareCard.maxDots ~/ 2),
      );
    });

    test('metin rotayı, oyunu, skoru ve adı taşır', () {
      final text = ShareCard.build(
        lineId: 'M1A',
        originName: 'Yenikapı',
        destinationName: 'Otogar',
        gameName: 'Blok Metro',
        score: 6180,
        stops: 7,
        passedStops: 4,
        playerName: 'Hızlı Kadıköylü',
        arrived: false,
      );
      expect(text, contains('M1A'));
      expect(text, contains('Yenikapı → Otogar'));
      expect(text, contains('Blok Metro'));
      expect(text, contains('6.180'));
      expect(text, contains('Hızlı Kadıköylü'));
      expect(text, contains(ShareCard.passed));
    });

    test('varışta sonuç cümlesi değişir', () {
      String textFor({required bool arrived}) => ShareCard.build(
        lineId: 'M2',
        originName: 'Taksim',
        destinationName: 'Levent',
        gameName: 'Metro Bilgi',
        score: 900,
        stops: 4,
        passedStops: 4,
        playerName: 'Gece Baykuş',
        arrived: arrived,
      );
      expect(textFor(arrived: true), contains('Durağıma vardım'));
      expect(textFor(arrived: false), isNot(contains('Durağıma vardım')));
    });

    test('durak yoksa desen boş kalır ve metin çökmez', () {
      expect(ShareCard.route(stops: 0, passedStops: 0), isEmpty);
    });
  });
}
