import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/constants/app_constants.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';

/// Sıkışık tahtada aday tepsi seçimi.
///
/// Oyuncuya kıyak değil, **haksız diziyi elemek** için var: dolu tahtada
/// rastgele üç parçanın hiçbirinin işe yaramaması sık oluyordu ve oyun
/// oyuncunun hatasından değil şanssızlıktan bitiyordu.
///
/// İki sınır korunuyor: tahta rahatken bu adım hiç çalışmamalı (rastgelelik
/// bozulmamalı), sıkışıkken seçilen tepsi ortalamadan daha fazla hamle
/// imkânı sunmalı.
void main() {
  /// Verilen doluluk oranına yakın, satır satır dolan tahta.
  Board boardFilledTo(double ratio) {
    final grid = List<List<int>>.generate(
      AppConstants.boardRows,
      (_) => List<int>.filled(AppConstants.boardCols, kEmptyCell),
    );
    final target = (AppConstants.boardRows * AppConstants.boardCols * ratio)
        .round();
    var placed = 0;
    // Satırları tam doldurmamak önemli: dolu satır temizlenir sayılmaz ama
    // "her satırda bir boşluk" tahtayı gerçekten sıkışık yapar.
    for (var r = 0; r < AppConstants.boardRows && placed < target; r++) {
      for (var c = 0; c < AppConstants.boardCols - 1 && placed < target; c++) {
        grid[r][c] = 1;
        placed++;
      }
    }
    return Board.fromGrid(grid);
  }

  int freedom(Board board, List<BlockPiece> tray) {
    var total = 0;
    for (final piece in tray) {
      for (var r = 0; r <= board.rows - piece.height; r++) {
        for (var c = 0; c <= board.cols - piece.width; c++) {
          if (canPlace(board, piece, r, c)) total++;
        }
      }
    }
    return total;
  }

  DifficultyProfile profileWith(int candidates) => DifficultyProfile(
    id: 'test',
    label: 'Test',
    minMinutes: 0,
    maxMinutes: null,
    initialBlockerRatio: 0,
    hardPieceWeight: 0.1,
    undoCount: 1,
    trayCandidates: candidates,
  );

  test('boş tahtada aday seçimi çalışmaz, rastgelelik korunur', () {
    // Aynı tohumla tek adaylı ve çok adaylı generator aynı tepsiyi vermeli:
    // tahta rahatken seçim adımı hiç devreye girmiyor demektir.
    final single = PieceGenerator(random: Random(5));
    final many = PieceGenerator(random: Random(5));

    final a = single.generateTray(Board.empty(), profileWith(1));
    final b = many.generateTray(Board.empty(), profileWith(8));

    expect(b.map((p) => p.id).toList(), a.map((p) => p.id).toList());
  });

  test('eşik altındaki doluluk da rastgeleliği bozmaz', () {
    final board = boardFilledTo(PieceGenerator.crowdedFillRatio - 0.1);
    final single = PieceGenerator(random: Random(9));
    final many = PieceGenerator(random: Random(9));

    expect(
      many.generateTray(board, profileWith(8)).map((p) => p.id).toList(),
      single.generateTray(board, profileWith(1)).map((p) => p.id).toList(),
    );
  });

  test('sıkışık tahtada seçilen tepsi ortalamadan daha özgür', () {
    final board = boardFilledTo(0.62);

    var pickedTotal = 0;
    var plainTotal = 0;
    const rounds = 60;

    for (var seed = 0; seed < rounds; seed++) {
      pickedTotal += freedom(
        board,
        PieceGenerator(
          random: Random(seed),
        ).generateTray(board, profileWith(6)),
      );
      plainTotal += freedom(
        board,
        PieceGenerator(
          random: Random(seed),
        ).generateTray(board, profileWith(1)),
      );
    }

    expect(
      pickedTotal,
      greaterThan(plainTotal),
      reason: 'aday seçimi daha çok hamle imkânı sunan tepsiyi seçmeli',
    );
  });

  test('aday sayısı arttıkça tepsi daha özgür olur', () {
    final board = boardFilledTo(0.62);

    int average(int candidates) {
      var total = 0;
      for (var seed = 0; seed < 40; seed++) {
        total += freedom(
          board,
          PieceGenerator(
            random: Random(seed),
          ).generateTray(board, profileWith(candidates)),
        );
      }
      return total;
    }

    expect(average(8), greaterThanOrEqualTo(average(2)));
  });

  test('seçim fairness kuralını bozmaz', () {
    final board = boardFilledTo(0.7);
    for (var seed = 0; seed < 40; seed++) {
      final tray = PieceGenerator(
        random: Random(seed),
      ).generateTray(board, profileWith(4));

      expect(tray, hasLength(AppConstants.traySize));
      expect(
        hasAnyLegalMove(board, tray),
        isTrue,
        reason: 'tepside en az bir parça konabilmeli',
      );
    }
  });

  test('zorluk profilleri yolculuk uzadıkça daha çok aday dener', () {
    final candidates = <int>[
      DifficultyProfiles.mini.trayCandidates,
      DifficultyProfiles.short.trayCandidates,
      DifficultyProfiles.standard.trayCandidates,
      DifficultyProfiles.long.trayCandidates,
      DifficultyProfiles.marathon.trayCandidates,
    ];

    for (var i = 1; i < candidates.length; i++) {
      expect(
        candidates[i],
        greaterThanOrEqualTo(candidates[i - 1]),
        reason:
            'uzun yolculuk daha çok hamle gerektirir, şanssızlığa daha '
            'çok maruz kalır',
      );
    }
  });
}
