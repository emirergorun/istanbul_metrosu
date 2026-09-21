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

  /// Kaydı üretecek controller. Kayıt **yalnızca tahtayı** taşır; puan ve
  /// süre yolculuğun zarfında (`JourneySave`).
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
      // Yolculuk alanları artık kayıtta değil.
      expect(restored.progress, isNull);
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

    test('kayıt yolculuk alanlarını taşımaz', () {
      final controller = sampleController();
      addTearDown(controller.dispose);
      controller.start();
      controller.debugAdvanceSeconds(30);

      final json =
          jsonDecode(GameSnapshot.encode(controller)) as Map<String, dynamic>;

      // Puan ve süre yolculuğun; iki yerde tutulursa biri eskir.
      expect(json.containsKey('score'), isFalse);
      expect(json.containsKey('elapsed'), isFalse);
      expect(json.containsKey('stationsPassed'), isFalse);
    });

    test('ortak yolculuktan önceki kayıt (v3) hâlâ okunur', () {
      // Sürüm yükseltmesinde oyuncunun yarım kalan tahtası kaybolmamalı.
      final json = jsonDecode(sampleSnapshot()) as Map<String, dynamic>;
      json['v'] = 3;
      json['score'] = 120;
      json['elapsed'] = 45;
      json['stationsPassed'] = 1;
      json['record'] = 300;
      json['recordBeaten'] = false;

      final restored = GameSnapshot.decode(jsonEncode(json), routeService);

      expect(restored, isNotNull);
      expect(restored!.session.tray.whereType<BlockPiece>().length, 3);
      expect(restored.progress?.score, 120);
      expect(restored.progress?.elapsedSeconds, 45);
    });

    test('okunamayan sürüm atılır', () {
      final json = jsonDecode(sampleSnapshot()) as Map<String, dynamic>;
      json['v'] = 2;

      expect(GameSnapshot.decode(jsonEncode(json), routeService), isNull);
    });
  });
}
