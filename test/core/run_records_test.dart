import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Koşu rekorları: combo, seri, geçilen durak.
///
/// Skordan ayrı tutulurlar çünkü ayrı şeyler ölçerler. Düşük skorlu bir
/// koşuda en iyi seri kurulmuş olabilir; oyuncu bunu görmeli.
void main() {
  const gameId = 'blocks';
  const origin = 'm2_taksim';
  const destination = 'm2_levent';

  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    return store;
  }

  Future<RunRecordResult> submit(
    LocalStore store, {
    int combo = 0,
    int streak = 0,
    int stations = 0,
  }) => store.submitRunRecords(
    gameId: gameId,
    originId: origin,
    destinationId: destination,
    bestCombo: combo,
    bestStreak: streak,
    stationsPassed: stations,
  );

  test('ilk koşu üç rekoru da kurar', () async {
    final store = await freshStore();
    final result = await submit(store, combo: 5, streak: 3, stations: 4);

    expect(result.combo, isTrue);
    expect(result.streak, isTrue);
    expect(result.stations, isTrue);
    expect(result.any, isTrue);

    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      5,
    );
    expect(
      store.bestStreakForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      3,
    );
    expect(
      store.maxStationsForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      4,
    );
  });

  test('daha düşük değerler rekoru düşürmez', () async {
    final store = await freshStore();
    await submit(store, combo: 9, streak: 9, stations: 9);
    final result = await submit(store, combo: 2, streak: 2, stations: 2);

    expect(result.any, isFalse);
    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      9,
    );
  });

  test('rekorlar birbirinden bağımsız kırılır', () async {
    final store = await freshStore();
    await submit(store, combo: 9, streak: 2, stations: 5);

    // Yalnızca seri geliştirildi.
    final result = await submit(store, combo: 3, streak: 7, stations: 1);

    expect(result.combo, isFalse);
    expect(result.streak, isTrue);
    expect(result.stations, isFalse);
  });

  test('yön rekoru bölmez', () async {
    final store = await freshStore();
    await submit(store, combo: 6);

    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: destination,
        destinationId: origin,
      ),
      6,
      reason: 'Taksim→Levent ile Levent→Taksim aynı rota',
    );
  });

  test('sıfır değer rekor sayılmaz', () async {
    final store = await freshStore();
    final result = await submit(store, combo: 0, streak: 0, stations: 0);

    expect(result.any, isFalse);
  });

  test('koşu rekorları rota skor listesine sızmaz', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: origin,
      destinationId: destination,
      score: 500,
    );
    await submit(store, combo: 9, streak: 9, stations: 9);

    final records = store.allRecords();
    expect(records, hasLength(1));
    expect(records.single.score, 500);
  });

  test('rekor sıfırlama koşu rekorlarını da siler', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: origin,
      destinationId: destination,
      score: 500,
    );
    await submit(store, combo: 9, streak: 9, stations: 9);

    await store.clearRecords();

    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      0,
    );
    expect(
      store.bestStreakForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      0,
    );
    expect(
      store.maxStationsForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      0,
    );
    expect(store.allRecords(), isEmpty);
  });

  test('farklı rotalar birbirinin rekorunu ezmez', () async {
    final store = await freshStore();
    await submit(store, combo: 9);
    await store.submitRunRecords(
      gameId: gameId,
      originId: 'm4_kadikoy',
      destinationId: 'm4_kozyatagi',
      bestCombo: 2,
      bestStreak: 0,
      stationsPassed: 0,
    );

    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: origin,
        destinationId: destination,
      ),
      9,
    );
    expect(
      store.bestComboForRoute(
        gameId: gameId,
        originId: 'm4_kadikoy',
        destinationId: 'm4_kozyatagi',
      ),
      2,
    );
  });
}
