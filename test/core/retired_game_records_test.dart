import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Emekliye ayrılan oyunların rekorları.
///
/// Durak Hafıza kaldırıldığında kayıtları cihazda kaldı. Kayıt biçimi
/// oyun kimliğini taşıyor; kimlik kataloğda yoksa o kayıt hiçbir ekranda
/// **görünmemeli**, çünkü ait olduğu oyun artık oynanamıyor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kataloğu terk etmiş oyunun kaydı ayrı bir kimlikte durur', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Anahtarda rota çifti **sıralı** tutulur (bkz. LocalStore.routeKey).
      'best_game_route_station_memory|m2_levent__m2_taksim': 500,
      'best_game_route_metro_quiz|m2_levent__m2_taksim': 120,
    });
    final store = LocalStore();
    await store.init();

    final records = store.allRecords();
    final known = <String>{for (final game in MiniGames.all) game.id};

    final retired = records.where((r) => !known.contains(r.gameId)).toList();
    final visible = records.where((r) => known.contains(r.gameId)).toList();

    expect(retired, hasLength(1), reason: 'eski kayıt silinmedi');
    expect(retired.single.gameId, 'station_memory');
    expect(visible.single.gameId, 'metro_quiz');
    expect(
      store.bestScoreForGameRoute(
        gameId: 'metro_quiz',
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
      ),
      120,
      reason: 'yeni oyunun rekoru eskisinden etkilenmemeli',
    );
  });
}
