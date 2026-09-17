import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Aynı ekranda tek bir "rekor" sayısı olmalı.
///
/// Regresyon: rekorun iki kaynağı vardı. HUD controller'ın depodan okuduğu
/// taze rekoru, sonuç paneli ile ilerleme çubuğu ise kaydın içine yazılmış
/// eski rekoru gösteriyordu. Oyun seçim ekranı "BU ROTADA REKORUN 500"
/// derken oyunun içi 100 gösteriyordu.
///
/// Motor birleştikten sonra tek kaynak kaldı; testler kaydın taşıdığı
/// rekorun da doğru hesaba katıldığını koruyor.
void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);

  Future<LocalStore> storeWithRecord(int score) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore();
    await store.init();
    if (score > 0) {
      await store.submitRouteScore(
        originId: 'm2_taksim',
        destinationId: 'm2_levent',
        score: score,
      );
    }
    return store;
  }

  GameController controllerFor(
    LocalStore store, {
    required int recordToBeat,
    SavedGame? resumeFrom,
  }) {
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;
    return GameController(
      journey: journey,
      store: store,
      generator: PieceGenerator(random: Random(1)),
      recordToBeat: recordToBeat,
      resumeFrom: resumeFrom?.session,
      resumeProgress: resumeFrom?.progress,
      tick: const Duration(days: 1),
    );
  }

  test('yeni oyunda iki kaynak aynı', () async {
    final store = await storeWithRecord(250);
    final controller = controllerFor(store, recordToBeat: 250);
    addTearDown(controller.dispose);

    expect(controller.recordToBeat, 250);
    expect(controller.isFirstRun, isFalse);
  });

  test('kayıttan dönen oyun tazelenmiş rekoru kullanır', () async {
    final store = await storeWithRecord(100);
    final first = controllerFor(store, recordToBeat: 100)..start();
    final snapshot = GameSnapshot.encode(first);
    first.dispose();

    // Oyun yarım beklerken aynı rotada daha yüksek bir rekor kuruldu.
    await store.submitRouteScore(
      originId: 'm2_taksim',
      destinationId: 'm2_levent',
      score: 500,
    );

    final resumed = GameSnapshot.decode(snapshot, routes)!;
    final controller = controllerFor(
      store,
      recordToBeat: store.bestScoreForRoute('m2_taksim', 'm2_levent'),
      resumeFrom: resumed,
    );
    addTearDown(controller.dispose);

    expect(
      controller.recordToBeat,
      500,
      reason: 'sonuç paneli ve ilerleme çubuğu da aynı sayıyı görmeli',
    );
  });

  test('seçim ekranı ile oyun aynı sayıyı gösterir', () async {
    final store = await storeWithRecord(100);
    final first = controllerFor(store, recordToBeat: 100)..start();
    final snapshot = GameSnapshot.encode(first);
    first.dispose();

    await store.submitRouteScore(
      originId: 'm2_taksim',
      destinationId: 'm2_levent',
      score: 500,
    );

    // Oyun seçim ekranının okuduğu değer.
    final shownOnCard = store.bestScoreForGameRoute(
      gameId: GameController.id,
      originId: 'm2_taksim',
      destinationId: 'm2_levent',
    );

    final controller = controllerFor(
      store,
      recordToBeat: store.bestScoreForRoute('m2_taksim', 'm2_levent'),
      resumeFrom: GameSnapshot.decode(snapshot, routes)!,
    );
    addTearDown(controller.dispose);

    expect(controller.recordToBeat, shownOnCard);
  });

  test('kayıt daha yüksek rekor taşıyorsa o korunur', () async {
    // Depo silinmiş ama kayıt duruyor: kaydın rekoru kaybolmamalı.
    final store = await storeWithRecord(0);
    final base = controllerFor(store, recordToBeat: 0);
    addTearDown(base.dispose);

    final resumed = controllerFor(
      store,
      recordToBeat: 0,
      resumeFrom: SavedGame(
        session: base.session,
        progress: const ResumedProgress(
          score: 0,
          elapsedSeconds: 0,
          stationsPassed: 0,
          recordToBeat: 300,
          recordBeaten: false,
        ),
      ),
    );
    addTearDown(resumed.dispose);

    expect(resumed.recordToBeat, 300);
    expect(resumed.isFirstRun, isFalse);
  });

  test('rekoru olmayan rotada iki kaynak da sıfır', () async {
    final store = await storeWithRecord(0);
    final controller = controllerFor(store, recordToBeat: 0);
    addTearDown(controller.dispose);

    expect(controller.recordToBeat, 0);
    expect(controller.isFirstRun, isTrue);
  });
}
