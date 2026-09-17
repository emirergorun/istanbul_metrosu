import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/widgets/board_view.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

class _SilentAudio extends AudioService {
  @override
  void play(GameSound sound) {}
}

/// Oyun her telefonda oynanabilir olmalı.
///
/// Metroda kullanılan cihaz yelpazesi geniş: beş yıllık küçük bir telefon
/// da, geniş bir Pro Max de aynı tahtayı göstermeli. Taşan bir satır ya da
/// tıklanamayacak kadar küçük bir tahta oyunu oynanmaz yapar.
void main() {
  final metro = MetroFixture.load();

  /// Desteklenen uçlar ve arası.
  const sizes = <String, Size>{
    'küçük telefon (SE)': Size(320, 568),
    'standart telefon': Size(390, 844),
    'geniş telefon (Pro Max)': Size(430, 932),
    'tablet': Size(768, 1024),
  };

  Future<void> pumpGame(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();
  }

  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: oyun ekranı taşmaz', (tester) async {
      await pumpGame(tester, entry.value);

      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key} boyutunda taşma var',
      );
    });

    testWidgets('${entry.key}: tahta ekrana sığar ve oynanabilir', (
      tester,
    ) async {
      await pumpGame(tester, entry.value);

      final board = tester.getRect(find.byType(BoardView));

      expect(board.width, greaterThan(0));
      expect(
        board.width,
        lessThanOrEqualTo(entry.value.width),
        reason: 'tahta ekrandan geniş olamaz',
      );
      expect(
        board.height,
        lessThanOrEqualTo(entry.value.height),
        reason: 'tahta ekrandan uzun olamaz',
      );

      // Sekiz hücrelik tahtada tek hücre parmakla vurulabilecek kadar
      // büyük olmalı; 24 pt altı dokunma hedefi güvenilir değil.
      expect(
        board.width / 8,
        greaterThanOrEqualTo(24),
        reason: '${entry.key} boyutunda hücreler çok küçük',
      );
    });
  }

  testWidgets('tahta ekran büyüdükçe büyür', (tester) async {
    await pumpGame(tester, const Size(320, 568));
    final small = tester.getRect(find.byType(BoardView)).width;

    await pumpGame(tester, const Size(430, 932));
    final large = tester.getRect(find.byType(BoardView)).width;

    expect(large, greaterThan(small));
  });

  testWidgets('tahta her zaman kare', (tester) async {
    for (final size in sizes.values) {
      await pumpGame(tester, size);
      final board = tester.getRect(find.byType(BoardView));
      expect(board.width, closeTo(board.height, 1));
    }
  });

  testWidgets('çok kısa ekranda tahta küçülür ama taşmaz', (tester) async {
    // Bölünmüş ekran gibi alışılmadık bir yükseklik. Uygulama dikey
    // kilitli, yani bu normal bir kullanım değil — ama taşan bir tahta
    // hem çizim hatası basar hem alt satırı erişilemez yapar.
    await pumpGame(tester, const Size(700, 380));

    expect(tester.takeException(), isNull);
    final board = tester.getRect(find.byType(BoardView));
    expect(board.height, lessThanOrEqualTo(380));
    expect(board.width, greaterThan(0));
  });

  testWidgets('tek duraklık yolculukta ekran çizilir', (tester) async {
    // Uç durum: aradaki durak sayısı 1. İlerleme çubuğunda ara istasyon
    // noktası olmaz, sıfıra bölme de olmamalı.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);
    final stations = metro.stationsOfLine('M2');
    final journey = routes.estimate(stations[0].id, stations[1].id).journey!;

    expect(journey.stopCount, 1);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final controller = GameController(
      journey: journey,
      generator: PieceGenerator(random: Random(1)),
      tick: const Duration(days: 1),
    )..start();
    addTearDown(controller.dispose);

    controller.debugAdvanceSeconds(journey.estimatedSeconds + 1);
    expect(controller.status, GameStatus.arrived);
    expect(controller.stationsPassed, lessThanOrEqualTo(journey.stopCount));
  });
}
