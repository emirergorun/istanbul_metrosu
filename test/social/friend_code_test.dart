import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/social/domain/friend_code.dart';

/// Arkadaş kodu: üretim, okuma ve elle yazım.
///
/// Kodun asıl kullanım yeri metroda birinin telefonundan okuyup kendi
/// telefonuna yazmak. Testlerin çoğu bu yüzden **yanlış yazımı** sınıyor.
void main() {
  test('üretilen kod sekiz karakter ve alfabede', () {
    for (var i = 0; i < 200; i++) {
      final code = FriendCode.generate(random: Random(i));
      expect(code, hasLength(FriendCode.length));
      for (final char in code.split('')) {
        expect(FriendCode.alphabet, contains(char));
      }
    }
  });

  test('alfabede karışan harf yok', () {
    // Crockford Base32: I, L, O okunurken 1 ve 0 ile karışıyor; U kazara
    // küfür üretmemek için dışarıda.
    for (final banned in <String>['I', 'L', 'O', 'U']) {
      expect(FriendCode.alphabet, isNot(contains(banned)));
    }
    expect(FriendCode.alphabet, hasLength(32));
  });

  test('aynı tohum aynı kodu verir', () {
    expect(
      FriendCode.generate(random: Random(7)),
      FriendCode.generate(random: Random(7)),
    );
  });

  test('tohumsuz üretim çeşitli', () {
    final codes = <String>{for (var i = 0; i < 500; i++) FriendCode.generate()};
    // 32⁸ olasılıkta 500 çekimde çakışma beklenmiyor.
    expect(codes, hasLength(500));
  });

  group('elle yazım', () {
    test('tire ve boşluk serbest', () {
      expect(FriendCode.normalize('ABCD-1234'), 'ABCD1234');
      expect(FriendCode.normalize('abcd 1234'), 'ABCD1234');
      expect(FriendCode.normalize('  ABCD1234  '.trim()), 'ABCD1234');
    });

    test('karışan harfler düzeltiliyor', () {
      // Oyuncu gördüğünü yazıyor: I yerine 1, O yerine 0 yazmış olabilir
      // ya da tersi.
      expect(FriendCode.normalize('IBCD1234'), '1BCD1234');
      expect(FriendCode.normalize('LBCD1234'), '1BCD1234');
      expect(FriendCode.normalize('OBCD1234'), '0BCD1234');
      expect(FriendCode.normalize('UBCD1234'), 'VBCD1234');
    });

    test('yanlış uzunluk reddediliyor', () {
      expect(FriendCode.normalize('ABCD123'), isNull);
      expect(FriendCode.normalize('ABCD12345'), isNull);
      expect(FriendCode.normalize(''), isNull);
      expect(FriendCode.normalize(null), isNull);
    });

    test('alfabe dışı karakter reddediliyor', () {
      expect(FriendCode.normalize('ABCD123!'), isNull);
      expect(FriendCode.normalize('ABCDÇ234'), isNull);
    });

    test('gösterim biçimi tire ekliyor', () {
      expect(FriendCode.format('ABCD1234'), 'ABCD-1234');
      // Bozuk uzunluk olduğu gibi dönüyor; biçimlendirme veri kaybetmiyor.
      expect(FriendCode.format('ABC'), 'ABC');
    });

    test('gidip gelme kayıpsız', () {
      for (var i = 0; i < 100; i++) {
        final code = FriendCode.generate(random: Random(i));
        expect(FriendCode.normalize(FriendCode.format(code)), code);
      }
    });
  });
}
