import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/piece_shapes.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final routeService = RouteService(MetroFixture.load());

  GameSession sampleSession() {
    final journey = routeService.estimate('m2_taksim', 'm2_levent').journey!;
    return GameSession.initial(
      journey: journey,
      board: Board.empty(),
      tray: <BlockPiece?>[
        PieceShapes.dot.withColor(1),
        PieceShapes.h3.withColor(2),
        PieceShapes.square2.withColor(3),
      ],
    );
  }

  group('GameSnapshot', () {
    test('kaydedilen oturum geri yüklenir', () {
      final restored = GameSnapshot.decode(
        GameSnapshot.encode(sampleSession()),
        routeService,
      );

      expect(restored, isNotNull);
      expect(restored!.tray.whereType<BlockPiece>().length, 3);
      expect(restored.status, GameStatus.paused);
    });

    test('bilinmeyen şekil id’si tüm kaydı geçersiz kılar', () {
      // Regresyon: `byId` null dönünce bu null sessizce tepsiye giriyordu.
      // Oyuncu eksik tepsiyle devam ediyor, tepsi tamamen boşalırsa oyun
      // kilitleniyordu — yeni tepsi yalnızca hamle yapılınca geliyor, ama
      // yapacak parça yok.
      final json =
          jsonDecode(GameSnapshot.encode(sampleSession()))
              as Map<String, dynamic>;
      (json['tray'] as List<dynamic>)[1] = <String, dynamic>{
        'id': 'artik_olmayan_sekil',
        'color': 2,
      };

      expect(GameSnapshot.decode(jsonEncode(json), routeService), isNull);
    });

    test('bozuk JSON çökmez, null döner', () {
      expect(GameSnapshot.decode('{bu json degil', routeService), isNull);
    });

    test('eski sürüm kaydı atılır', () {
      final json =
          jsonDecode(GameSnapshot.encode(sampleSession()))
              as Map<String, dynamic>;
      json['v'] = GameSnapshot.version - 1;

      expect(GameSnapshot.decode(jsonEncode(json), routeService), isNull);
    });
  });
}
