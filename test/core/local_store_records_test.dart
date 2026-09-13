import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rekor listesi sayı olmayan anahtarlarda çökmemeli', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'best_route_m1a_aksaray__m1a_otogar': 120,
      'haptics_enabled': true,
      'saved_game': '{"v":1}',
    });
    final store = LocalStore();
    await store.init();

    final records = store.allRecords();

    expect(records, hasLength(1));
    expect(records.single.score, 120);
  });
}
