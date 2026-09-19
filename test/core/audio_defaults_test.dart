import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ilk açılışta ses efektleri ve müzik açık gelir', () async {
    // Ürün kararı: oyun sessiz açılınca, ayarlara hiç girmeyen oyuncu sesin
    // var olduğunu fark etmiyordu. İstemeyen ayarlardan kapatır.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();

    expect(store.soundEnabled, isTrue);
    expect(store.musicEnabled, isTrue);
  });

  test('oyuncunun kapattığı ses açılışta kapalı kalır', () async {
    // Varsayılanın tercihi ezmemesi şart: kapatan oyuncu her açılışta
    // yeniden kapatmak zorunda kalmamalı.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sound_enabled': false,
      'music_enabled': false,
    });
    final store = LocalStore();
    await store.init();

    expect(store.soundEnabled, isFalse);
    expect(store.musicEnabled, isFalse);
  });
}
