import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/player/domain/player_name.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oyuncu kimliğinin kalıcılığı.
void main() {
  Future<LocalStore> storeWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final store = LocalStore();
    await store.init();
    return store;
  }

  test('ilk açılışta ad ve sonek kendiliğinden atanır', () async {
    final store = await storeWith(<String, Object>{});

    expect(store.playerName, isNotEmpty);
    expect(PlayerName.isValid(store.playerName), isTrue);
    expect(store.playerTag, hasLength(4));
  });

  test('kayıtlı ad korunur', () async {
    final name = '${PlayerName.adjectives.first} ${PlayerName.nouns.first}';
    final store = await storeWith(<String, Object>{'player_name': name});

    expect(store.playerName, name);
  });

  test('sözlük dışı kayıt atılır ve yerine geçerli ad verilir', () async {
    // Elle düzenlenmiş bir tercih dosyası uygulamaya rastgele metin
    // sokamamalı: skor tablosunda görünecek olan bu ad.
    final store = await storeWith(<String, Object>{
      'player_name': 'uygunsuz kelime',
    });

    expect(store.playerName, isNot('uygunsuz kelime'));
    expect(PlayerName.isValid(store.playerName), isTrue);
  });

  test('ad bir kez onaylanır ve kilitlenir', () async {
    final store = await storeWith(<String, Object>{});
    final first = '${PlayerName.adjectives[3]} ${PlayerName.nouns[5]}';
    final second = '${PlayerName.adjectives[8]} ${PlayerName.nouns[9]}';

    expect(store.isPlayerNameLocked, isFalse);
    expect(await store.confirmPlayerName(first), isTrue);
    expect(store.playerName, first);
    expect(store.isPlayerNameLocked, isTrue);

    // İkinci onay reddedilir: ad bir imza, takma ad değil.
    expect(await store.confirmPlayerName(second), isFalse);
    expect(store.playerName, first);
  });

  test('sözlük dışı ad onaylanamaz ve kilit inmez', () async {
    final store = await storeWith(<String, Object>{});

    expect(await store.confirmPlayerName('kendi yazdığım ad'), isFalse);
    expect(store.isPlayerNameLocked, isFalse, reason: 'kilit boşa inmemeli');
  });

  test('kilit kayıttan geri yüklenir', () async {
    final name = '${PlayerName.adjectives[2]} ${PlayerName.nouns[4]}';
    final store = await storeWith(<String, Object>{
      'player_name': name,
      'player_name_locked': true,
    });

    expect(store.isPlayerNameLocked, isTrue);
    expect(
      await store.confirmPlayerName(
        '${PlayerName.adjectives[0]} ${PlayerName.nouns[1]}',
      ),
      isFalse,
    );
    expect(store.playerName, name);
  });

  test('sonek ad onaylanınca değişmez', () async {
    final store = await storeWith(<String, Object>{});
    final tag = store.playerTag;

    await store.confirmPlayerName(
      '${PlayerName.adjectives[1]} ${PlayerName.nouns[2]}',
    );

    expect(store.playerTag, tag);
  });
}
