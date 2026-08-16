@Tags(<String>['balance'])
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import 'helpers/metro_fixture.dart';

/// Denge ölçüm koşumu — ürün kodu değil, rapor üreten bir araçtır.
///
/// Oyun kurallarının kendisi (`calculateScore`, `ScoreRules`, board
/// fonksiyonları, `PieceGenerator`) gerçek koddan gelir; yalnızca zaman
/// döngüsü ve oyuncu davranışı burada modellenir.
///
/// Çalıştırmak için:  flutter test test/balance_report_test.dart
void main() {
  final metro = MetroFixture.load();
  final routeService = RouteService(metro);

  test('denge raporu', () {
    final routes = <String, List<String>>{
      'Mini      (M2 Taksim→Osmanbey)': <String>['m2_taksim', 'm2_osmanbey'],
      'Kısa      (M2 Taksim→Levent)': <String>['m2_taksim', 'm2_levent'],
      'Standart  (M4 Kadıköy→Kozyatağı)': <String>[
        'm4_kadikoy',
        'm4_kozyatagi',
      ],
      'Uzun      (M2 uçtan uca)': <String>['m2_yenikapi', 'm2_haciosman'],
      'Maraton   (M4 uçtan uca)': <String>[
        'm4_kadikoy',
        'm4_sabiha_gokcen_havalimani',
      ],
    };

    for (final secondsPerMove in <int>[4, 7]) {
      // ignore: avoid_print
      print(
        '\n═══ Hamle aralığı: $secondsPerMove sn '
        '(${(60 / secondsPerMove).round()} parça/dk)',
      );
      // ignore: avoid_print
      print(
        'Profil                            '
        'Medyan  Varış%  Durak%  Sprint%  Engelsiz',
      );

      for (final entry in routes.entries) {
        final journey = routeService
            .estimate(entry.value[0], entry.value[1])
            .journey!;
        final profile = journey.difficulty;

        final withBlockers = _run(
          seconds: journey.estimatedSeconds,
          stops: journey.stopCount,
          profile: profile,
          secondsPerMove: secondsPerMove,
        );
        final noBlockers = _run(
          seconds: journey.estimatedSeconds,
          stops: journey.stopCount,
          profile: _withoutBlockers(profile),
          secondsPerMove: secondsPerMove,
        );

        // ignore: avoid_print
        print(
          '${entry.key.padRight(34)}'
          '${withBlockers.medianScore.toString().padLeft(6)}'
          '${'%${withBlockers.arrivalRate.round()}'.padLeft(8)}'
          '${'%${withBlockers.stationShare.round()}'.padLeft(8)}'
          '${'%${withBlockers.sprintShare.round()}'.padLeft(9)}'
          '${noBlockers.medianScore.toString().padLeft(10)}',
        );
      }
    }

    // ignore: avoid_print
    print(
      '\nVarış% = yolculuğu tamamlama oranı (kalanı hamlesiz kaldı)\n'
      'Durak% = skorun durak bonusundan gelen payı\n'
      'Sprint% = skorun son %15 diliminde kazanılan payı\n'
      'Engelsiz = başlangıç engeli kaldırılınca medyan skor',
    );
  });
}

DifficultyProfile _withoutBlockers(DifficultyProfile profile) =>
    DifficultyProfile(
      id: profile.id,
      label: profile.label,
      minMinutes: profile.minMinutes,
      maxMinutes: profile.maxMinutes,
      initialBlockerRatio: 0,
      hardPieceWeight: profile.hardPieceWeight,
      undoCount: profile.undoCount,
    );

class _Result {
  const _Result({
    required this.medianScore,
    required this.arrivalRate,
    required this.stationShare,
    required this.sprintShare,
  });

  final int medianScore;
  final double arrivalRate;
  final double stationShare;
  final double sprintShare;
}

_Result _run({
  required int seconds,
  required int stops,
  required DifficultyProfile profile,
  required int secondsPerMove,
  int games = 150,
}) {
  final scores = <int>[];
  var arrived = 0;
  var stationTotal = 0;
  var sprintTotal = 0;
  var grandTotal = 0;

  for (var game = 0; game < games; game++) {
    final random = Random(game);
    final generator = PieceGenerator(random: random);
    var board = generator.applyInitialBlockers(Board.empty(), profile);
    var tray = List<BlockPiece?>.of(generator.generateTray(board, profile));

    var score = 0;
    var combo = 0;
    var stationsPassed = 0;
    var clearedSinceStation = false;
    var alive = true;

    for (var t = 1; t <= seconds && alive; t++) {
      final progress = t / seconds;
      final isSprint = progress >= ScoreRules.sprintStartsAt;

      if (t % secondsPerMove == 0) {
        final move = _bestMove(board, tray);
        if (move == null) {
          alive = false;
          break;
        }

        final piece = tray[move.index]!;
        var next = placePiece(board, piece, move.row, move.col);
        final rows = findCompletedRows(next);
        final columns = findCompletedColumns(next);
        final result = calculateScore(
          placedCells: piece.size,
          clearedRows: rows.length,
          clearedColumns: columns.length,
          currentCombo: combo,
          isSprint: isSprint,
        );
        next = clearLines(next, rows: rows, columns: columns);

        board = next;
        combo = result.combo;
        score += result.points;
        grandTotal += result.points;
        if (isSprint) sprintTotal += result.points;
        if (result.linesCleared > 0) clearedSinceStation = true;

        tray[move.index] = null;
        if (tray.every((p) => p == null)) {
          tray = List<BlockPiece?>.of(generator.generateTray(board, profile));
        }
        if (!hasAnyLegalMove(board, tray)) alive = false;
      }

      // Durak geçişi
      if (stops > 0) {
        final passed = (progress * stops).floor();
        if (passed > stationsPassed) {
          stationsPassed = passed;
          if (clearedSinceStation) {
            score += ScoreRules.stationBonus;
            stationTotal += ScoreRules.stationBonus;
            grandTotal += ScoreRules.stationBonus;
            if (isSprint) sprintTotal += ScoreRules.stationBonus;
          }
          clearedSinceStation = false;
        }
      }
    }

    if (alive) arrived++;
    scores.add(score);
  }

  scores.sort();
  return _Result(
    medianScore: scores[scores.length ~/ 2],
    arrivalRate: arrived / games * 100,
    stationShare: grandTotal == 0 ? 0 : stationTotal / grandTotal * 100,
    sprintShare: grandTotal == 0 ? 0 : sprintTotal / grandTotal * 100,
  );
}

/// Makul bir oyuncu: önce hat temizleyen, sonra en az delik bırakan hamle.
({int index, int row, int col})? _bestMove(
  Board board,
  List<BlockPiece?> tray,
) {
  ({int index, int row, int col})? best;
  var bestScore = -1 << 30;

  for (var i = 0; i < tray.length; i++) {
    final piece = tray[i];
    if (piece == null) continue;

    for (var r = 0; r <= board.rows - piece.height; r++) {
      for (var c = 0; c <= board.cols - piece.width; c++) {
        if (!canPlace(board, piece, r, c)) continue;

        final placed = placePiece(board, piece, r, c);
        final lines =
            findCompletedRows(placed).length +
            findCompletedColumns(placed).length;
        final cleared = clearLines(
          placed,
          rows: findCompletedRows(placed),
          columns: findCompletedColumns(placed),
        );
        final value = lines * 100 - _holes(cleared);

        if (value > bestScore) {
          bestScore = value;
          best = (index: i, row: r, col: c);
        }
      }
    }
  }
  return best;
}

/// Komşusuz boş hücre sayısı — parçalanmış tahtanın ölçüsü.
int _holes(Board board) {
  var holes = 0;
  for (var r = 0; r < board.rows; r++) {
    for (var c = 0; c < board.cols; c++) {
      if (!board.isEmptyAt(r, c)) continue;
      var open = 0;
      if (r > 0 && board.isEmptyAt(r - 1, c)) open++;
      if (r < board.rows - 1 && board.isEmptyAt(r + 1, c)) open++;
      if (c > 0 && board.isEmptyAt(r, c - 1)) open++;
      if (c < board.cols - 1 && board.isEmptyAt(r, c + 1)) open++;
      if (open == 0) holes++;
    }
  }
  return holes;
}
