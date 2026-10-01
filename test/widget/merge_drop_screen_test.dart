import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/merge_drop_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

/// Hat Düşür ekranı: depo fizik alanıyla birebir, sürükle-bırak, vazgeçme,
/// şimdi/sonra şeridi ve HUD.
void main() {
  late LocalStore store;
  final metro = MetroFixture.load();
  final board = find.byKey(const ValueKey<String>('merge-drop-board'));

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();
  });

  Future<MergeDropController> pumpGame(
    WidgetTester tester, {
    Size size = const Size(1179, 2556),
    double ratio = 3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final journey = RouteService(
      metro,
    ).estimate('m2_taksim', 'm2_levent').journey!;
    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MergeDropScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state(find.byType(MergeDropScreen)) as dynamic;
    return state.debugController as MergeDropController;
  }

  Future<void> disposeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('depo fizik oranında, HUD ve şimdi/sonra görünür', (
    tester,
  ) async {
    final controller = await pumpGame(tester);

    final rect = tester.getRect(board);
    expect(rect.height / rect.width, closeTo(mergeDropPoolAspect, 0.01));
    expect(controller.worldHeight, closeTo(mergeDropPoolAspect, 1e-6));
    expect(find.text('EN BÜYÜK'), findsOneWidget);
    expect(find.text('ŞİMDİ'), findsOneWidget);
    expect(find.text('SONRA'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeGame(tester);
  });

  testWidgets('sürükleyip bırakınca parmağın sütununa düşer', (tester) async {
    final controller = await pumpGame(tester);
    final rect = tester.getRect(board);

    final gesture = await tester.startGesture(
      rect.topLeft + Offset(rect.width * 0.2, rect.height * 0.5),
    );
    await tester.pump();
    await gesture.moveTo(
      rect.topLeft + Offset(rect.width * 0.7, rect.height * 0.5),
    );
    await tester.pump();
    expect(controller.balls, isEmpty, reason: 'nişan alırken düşmez');
    expect(controller.aimX, closeTo(0.7, 0.02));

    await gesture.up();
    await tester.pump();
    expect(controller.balls, hasLength(1));
    expect(controller.balls.single.x, closeTo(0.7, 0.02));

    await disposeGame(tester);
  });

  testWidgets('tahtanın üstüne çekip bırakmak vazgeçmektir', (tester) async {
    final controller = await pumpGame(tester);
    final rect = tester.getRect(board);

    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture.moveTo(rect.topCenter - const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.balls, isEmpty);

    await disposeGame(tester);
  });

  testWidgets('bırakınca sonraki parça şimdiye geçer', (tester) async {
    final controller = await pumpGame(tester);
    final next = controller.nextLevel;

    await tester.tapAt(tester.getRect(board).center);
    await tester.pump();

    expect(controller.currentLevel, next);

    await disposeGame(tester);
  });

  testWidgets('sonuç paneli Hat Düşür ölçülerini gösterir', (tester) async {
    final controller = await pumpGame(tester);
    controller.debugSetBalls(const <DropBall>[
      DropBall(id: 1, level: 3, x: 0.5, y: 0.9),
      DropBall(id: 2, level: 3, x: 0.55, y: 0.9),
    ]);
    controller.debugStep(1 / 60);
    // Taşma: zemindeki M11'in üstünde M10 — tepe tehlike çizgisini aşar,
    // bekleme payı dolunca depo dolar.
    final h = controller.worldHeight;
    final bottom = mergeDropRadiusForLevel(11);
    final top = mergeDropRadiusForLevel(10);
    controller.debugSetBalls(<DropBall>[
      ...controller.balls,
      DropBall(id: 90, level: 11, x: 0.5, y: h - bottom),
      DropBall(id: 91, level: 10, x: 0.5, y: h - 2 * bottom - top),
    ]);
    for (var i = 0; i < 40 && controller.status == GameStatus.playing; i++) {
      controller.debugStep(1 / 60);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.status, GameStatus.gameOver);
    expect(find.text('Depo doldu'), findsOneWidget);
    expect(find.text('En büyük hat'), findsOneWidget);
    expect(find.text('M4'), findsWidgets);
    expect(find.text('En uzun zincir'), findsOneWidget);

    await disposeGame(tester);
  });

  for (final (name, size, ratio) in <(String, Size, double)>[
    ('iPhone SE', const Size(750, 1334), 2.0),
    ('iPhone 15 Pro Max', const Size(1290, 2796), 3.0),
    ('Android 20:9', const Size(1080, 2400), 2.625),
  ]) {
    testWidgets('$name: taşma yok, depo oranı sabit', (tester) async {
      await pumpGame(tester, size: size, ratio: ratio);
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(board);
      expect(rect.height / rect.width, closeTo(mergeDropPoolAspect, 0.01));
      expect(rect.width, greaterThan(240), reason: name);
      await disposeGame(tester);
    });
  }
}
