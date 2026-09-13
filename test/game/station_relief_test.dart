import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

/// Durak rahatlaması: "kalabalık vagon boşalır".
///
/// Bu kural ölçümle kondu — 9 dakikanın üstündeki yolculuklarda varış oranı
/// %0-3'tü, yani varış sahnesi gerçek bir yolculukta hiç oynamıyordu.
/// Testler kuralın üç sınırını koruyor: neyin boşaldığı, neyin boşalmadığı
/// ve skora dokunulmadığı.
void main() {
  final routeService = RouteService(MetroFixture.load());

  group('crowdedRows', () {
    test('yarısı dolu satırlar seçilir, seyrek satırlar kalır', () {
      final board = Board.fromGrid(<List<int>>[
        <int>[1, 1, 1, 1, 0, 0, 0, 0], // 4 dolu → boşalır
        <int>[1, 0, 0, 0, 0, 0, 0, 0], // 1 dolu → kalır
        <int>[1, 1, 1, 1, 1, 1, 1, 0], // 7 dolu → boşalır
        <int>[0, 0, 0, 0, 0, 0, 0, 0],
        <int>[1, 1, 1, 0, 0, 0, 0, 0], // 3 dolu → kalır
        <int>[0, 0, 0, 0, 0, 0, 0, 0],
        <int>[0, 0, 0, 0, 0, 0, 0, 0],
        <int>[9, 9, 9, 9, 0, 0, 0, 0], // engel de dolu sayılır
      ]);

      expect(crowdedRows(board), <int>[0, 2, 7]);
    });

    test('boş tahtada hiçbir satır boşalmaz', () {
      expect(crowdedRows(Board.empty()), isEmpty);
    });
  });

  group('durak geçişi', () {
    test('kalabalık satırlar boşalır ama skor değişmez', () {
      final journey = routeService.estimate('m2_taksim', 'm2_levent').journey!;
      final controller = GameController(
        journey: journey,
        generator: PieceGenerator(random: Random(7)),
        tick: const Duration(days: 1),
      )..start();
      addTearDown(controller.dispose);

      // Tahtayı elle kalabalıklaştırmak yerine gerçek akış: birkaç parça
      // yerleştirip ilk durağa kadar ilerlet.
      var placed = 0;
      for (var i = 0; i < 3 && placed < 3; i++) {
        final piece = controller.tray[i];
        if (piece == null) continue;
        final spot = findFirstLegalPosition(controller.session.board, piece);
        if (spot == null) continue;
        controller.place(i, spot.row, spot.col);
        placed++;
      }

      final scoreBefore = controller.session.score;
      final crowdedBefore = crowdedRows(controller.session.board);

      // İlk durağı geçecek kadar ilerlet.
      final perStop = journey.estimatedSeconds ~/ journey.stopCount;
      controller.debugAdvanceSeconds(perStop + 1);

      expect(
        controller.session.stationsPassed,
        greaterThan(0),
        reason: 'durak geçilmeliydi',
      );
      expect(
        crowdedRows(controller.session.board),
        isEmpty,
        reason: 'kalabalık satır kalmamalı',
      );
      if (crowdedBefore.isNotEmpty) {
        expect(
          controller.stationClearPulse,
          greaterThan(0),
          reason: 'UI bildirimi tetiklenmeli',
        );
      }
      // Skor yalnız durak bonusu kadar değişebilir; boşalan satır puan vermez.
      expect(controller.session.score - scoreBefore, anyOf(0, 25));
    });

    test('boşalma olduysa durak öncesine geri alınamaz', () {
      final journey = routeService.estimate('m2_taksim', 'm2_levent').journey!;
      final controller = GameController(
        journey: journey,
        generator: PieceGenerator(random: Random(3)),
        tick: const Duration(days: 1),
      )..start();
      addTearDown(controller.dispose);

      // Kalabalık bir satır oluşana kadar oyna.
      for (var move = 0; move < 12; move++) {
        if (crowdedRows(controller.session.board).isNotEmpty) break;
        var placedThisTurn = false;
        for (var i = 0; i < controller.tray.length; i++) {
          final piece = controller.tray[i];
          if (piece == null) continue;
          final spot = findFirstLegalPosition(controller.session.board, piece);
          if (spot == null) continue;
          controller.place(i, spot.row, spot.col);
          placedThisTurn = true;
          break;
        }
        if (!placedThisTurn) break;
      }

      expect(
        crowdedRows(controller.session.board),
        isNotEmpty,
        reason: 'test kurulumu: kalabalık satır oluşmalıydı',
      );
      expect(controller.canUndo, isTrue);

      final perStop = journey.estimatedSeconds ~/ journey.stopCount;
      controller.debugAdvanceSeconds(perStop + 1);

      // Boşalma gerçekleştiyse geri alma kapanır: aksi hâlde oyuncu geri
      // alıp boşalan satırları geri yükleyebilirdi.
      expect(controller.stationClearPulse, greaterThan(0));
      expect(controller.canUndo, isFalse);
    });
  });
}
