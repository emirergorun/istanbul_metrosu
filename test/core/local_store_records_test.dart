import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
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

  test('Blok Metro rekoru oyun seçim ekranındaki sorguda da görünür', () async {
    // Regresyon: Blok Metro rekoru eski rota anahtarına yazıyor, oyun seçim
    // ekranı ise oyun bazlı anahtarı okuyordu. Kart, rekor varken bile
    // "BU ROTADA İLK KEZ" gösteriyordu.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();

    await store.submitRouteScore(
      originId: 'm1a_emniyet_fatih',
      destinationId: 'm1a_topkapi_ulubatli',
      score: 120,
    );

    expect(LocalStore.legacyRouteGameId, MiniGames.blocks.id);
    expect(
      store.bestScoreForGameRoute(
        gameId: MiniGames.blocks.id,
        originId: 'm1a_topkapi_ulubatli',
        destinationId: 'm1a_emniyet_fatih',
      ),
      120,
    );
    // Diğer oyunlar Blok Metro rekorunu devralmaz.
    expect(
      store.bestScoreForGameRoute(
        gameId: MiniGames.all.firstWhere((g) => g.id != 'blocks').id,
        originId: 'm1a_emniyet_fatih',
        destinationId: 'm1a_topkapi_ulubatli',
      ),
      0,
    );
  });
}
