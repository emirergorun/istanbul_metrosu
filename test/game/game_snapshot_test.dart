import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final routeService = RouteService(MetroFixture.load());

  /// Kaydı üretecek controller. Kayıt hem tahtayı hem motoru taşır.
  GameController sampleController() {
    final journey = routeService.estimate('m2_taksim', 'm2_levent').journey!;
    return GameController(
      journey: journey,
      generator: PieceGenerator(random: Random(1)),
      tick: const Duration(days: 1),
      resumeFrom: GameSession.initial(
        journey: journey,
        board: Board.empty(),
        tray: <BlockPiece?>[
          PieceShapes.dot.withColor(1),
          PieceShapes.h3.withColor(2),
          PieceShapes.square2.withColor(3),
        ],
      ),
    );
  }

  String sampleSnapshot() {
    final controller = sampleController();
    addTearDown(controller.dispose);
    return GameSnapshot.encode(controller);
  }

  group('GameSnapshot', () {
    test('kaydedilen oturum geri yüklenir', () {
      final restored = GameSnapshot.decode(sampleSnapshot(), routeService);

      expect(restored, isNotNull);
      expect(restored!.session.tray.whereType<BlockPiece>().length, 3);
      expect(restored.progress.score, 0);
      expect(restored.progress.elapsedSeconds, 0);
    });

    test('bilinmeyen şekil id’si tüm kaydı geçersiz kılar', () {
      // Regresyon: `byId` null dönünce bu null sessizce tepsiye giriyordu.
      // Oyuncu eksik tepsiyle devam ediyor, tepsi tamamen boşalırsa oyun
      // kilitleniyordu — yeni tepsi yalnızca hamle yapılınca geliyor, ama
      // yapacak parça yok.
      final json = jsonDecode(sampleSnapshot()) as Map<String, dynamic>;
      (json['tray'] as List<dynamic>)[1] = <String, dynamic>{
        'id': 'artik_olmayan_sekil',
        'color': 2,
      };

      expect(GameSnapshot.decode(jsonEncode(json), routeService), isNull);
    });

    test('bozuk JSON çökmez, null döner', () {
      expect(GameSnapshot.decode('{bu json degil', routeService), isNull);
    });

    test('kayıt motorun durumunu da taşır', () {
      final controller = sampleController();
      addTearDown(controller.dispose);
      controller.start();
      controller.debugAdvanceSeconds(30);

      final restored = GameSnapshot.decode(
        GameSnapshot.encode(controller),
        routeService,
      )!;

      expect(
        restored.progress.elapsedSeconds,
        controller.elapsedSeconds.floor(),
      );
      expect(restored.progress.score, controller.score);
      expect(restored.progress.stationsPassed, controller.stationsPassed);
    });

    test('eski sürüm kaydı atılır', () {
      final json = jsonDecode(sampleSnapshot()) as Map<String, dynamic>;
      json['v'] = GameSnapshot.version - 1;

      expect(GameSnapshot.decode(jsonEncode(json), routeService), isNull);
    });
  });
}
