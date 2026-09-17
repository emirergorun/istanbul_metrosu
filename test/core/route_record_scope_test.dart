import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rekor **rotaya** bağlı, yöne değil.
///
/// Osmanbey → 4. Levent ile 4. Levent → Osmanbey aynı yolculuktur: aynı
/// duraklar, aynı süre, aynı zorluk. İkisini ayrı rekor tutmak oyuncuya
/// aynı rotayı iki kez "ilk yolculuk" olarak gösterirdi.
void main() {
  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    return store;
  }

  const forward = <String>['m2_osmanbey', 'm2_4levent'];
  final backward = forward.reversed.toList();

  test('rota anahtarı yönden bağımsız', () {
    expect(
      LocalStore.routeKey(forward[0], forward[1]),
      LocalStore.routeKey(backward[0], backward[1]),
    );
  });

  test('ileri yönde kurulan skor rekoru geri yönde de görünür', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: forward[0],
      destinationId: forward[1],
      score: 4200,
    );

    expect(store.bestScoreForRoute(backward[0], backward[1]), 4200);
    expect(
      store.bestScoreForGameRoute(
        gameId: 'blocks',
        originId: backward[0],
        destinationId: backward[1],
      ),
      4200,
    );
  });

  test('geri yönde kurulan daha iyi skor ileri yönü de günceller', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: forward[0],
      destinationId: forward[1],
      score: 100,
    );
    await store.submitRouteScore(
      originId: backward[0],
      destinationId: backward[1],
      score: 900,
    );

    expect(store.bestScoreForRoute(forward[0], forward[1]), 900);
  });

  test('combo, seri ve durak rekorları da yönden bağımsız', () async {
    final store = await freshStore();
    await store.submitRunRecords(
      gameId: 'blocks',
      originId: forward[0],
      destinationId: forward[1],
      bestCombo: 9,
      bestStreak: 7,
      stationsPassed: 5,
    );

    expect(
      store.bestComboForRoute(
        gameId: 'blocks',
        originId: backward[0],
        destinationId: backward[1],
      ),
      9,
    );
    expect(
      store.bestStreakForRoute(
        gameId: 'blocks',
        originId: backward[0],
        destinationId: backward[1],
      ),
      7,
    );
    expect(
      store.maxStationsForRoute(
        gameId: 'blocks',
        originId: backward[0],
        destinationId: backward[1],
      ),
      5,
    );
  });

  test('rota rekoru başka rotaya sızmaz', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: forward[0],
      destinationId: forward[1],
      score: 4200,
    );

    // Aynı hat, farklı iki durak.
    expect(store.bestScoreForRoute('m2_taksim', 'm2_levent'), 0);
  });

  test('rotanın en iyi kaydı yönden bağımsız çözülür', () async {
    final store = await freshStore();
    await store.submitRouteScore(
      originId: forward[0],
      destinationId: forward[1],
      score: 4200,
    );

    final record = store.bestRecordForRoute(backward[0], backward[1]);
    expect(record, isNotNull);
    expect(record!.score, 4200);
  });
}
