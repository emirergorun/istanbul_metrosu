import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../journey/models/difficulty_profile.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/piece_shapes.dart';

/// Tepsiye gelen parçaları üretir.
///
/// Tam random kullanılmaz:
/// - zorluk profiline göre kolay/orta/zor havuzları ağırlıklandırılır,
/// - üretilen tepside **en az bir** legal hamle olması garanti edilmeye
///   çalışılır (fairness kuralı).
class PieceGenerator {
  PieceGenerator({Random? random, this.colorCount = 6})
    : _random = random ?? Random();

  final Random _random;

  /// Blok renk paletindeki renk sayısı.
  final int colorCount;

  /// Zorluk havuzu seçimi.
  ///
  /// `hardPieceWeight` doğrudan zor havuzunun olasılığıdır. Kalan olasılık
  /// kolay/orta arasında 55/45 bölünür.
  PieceDifficulty _rollDifficulty(DifficultyProfile profile) {
    final hard = profile.hardPieceWeight.clamp(0.0, 1.0);
    final rest = 1.0 - hard;
    final easyChance = rest * 0.55;

    final roll = _random.nextDouble();
    if (roll < easyChance) return PieceDifficulty.easy;
    if (roll < easyChance + rest * 0.45) return PieceDifficulty.medium;
    return PieceDifficulty.hard;
  }

  /// Tek parça üretir (renk atanmış olarak).
  BlockPiece nextPiece(DifficultyProfile profile) {
    final pool = PieceShapes.pool(_rollDifficulty(profile));
    final shape = pool[_random.nextInt(pool.length)];
    return shape.withColor(1 + _random.nextInt(colorCount));
  }

  /// 3'lü tepsi üretir.
  ///
  /// Fairness: tepside en az bir parça board'a konabilmeli. En fazla
  /// [AppConstants.maxTrayGenerationAttempts] deneme yapılır; hiçbiri
  /// tutmazsa son deneme yine de döner (board gerçekten doluysa oyun
  /// zaten game-over olacaktır).
  List<BlockPiece> generateTray(Board board, DifficultyProfile profile) {
    List<BlockPiece> tray = const <BlockPiece>[];

    for (
      var attempt = 0;
      attempt < AppConstants.maxTrayGenerationAttempts;
      attempt++
    ) {
      tray = <BlockPiece>[
        for (var i = 0; i < AppConstants.traySize; i++) nextPiece(profile),
      ];
      if (hasAnyLegalMove(board, tray)) return tray;
    }

    // Son çare: sadece kolay havuzdan dene — dar board'larda kurtarır.
    for (
      var attempt = 0;
      attempt < AppConstants.maxTrayGenerationAttempts;
      attempt++
    ) {
      tray = <BlockPiece>[
        for (var i = 0; i < AppConstants.traySize; i++)
          PieceShapes.easy[_random.nextInt(PieceShapes.easy.length)].withColor(
            1 + _random.nextInt(colorCount),
          ),
      ];
      if (hasAnyLegalMove(board, tray)) return tray;
    }

    return tray;
  }

  /// Oyun başında zorluk profiline göre engel hücreleri serpiştirir.
  ///
  /// Engeller normal dolu hücre gibi davranır; satır/sütun temizliğinde
  /// silinebilirler (kalıcı ölü hücre bırakmamak için).
  Board applyInitialBlockers(Board board, DifficultyProfile profile) {
    final ratio = profile.initialBlockerRatio.clamp(0.0, 0.5);
    if (ratio <= 0) return board;

    final target = (board.cellCount * ratio).round();
    if (target <= 0) return board;

    final grid = board.toGrid();
    var placed = 0;
    var guard = 0;
    while (placed < target && guard < board.cellCount * 10) {
      guard++;
      final r = _random.nextInt(board.rows);
      final c = _random.nextInt(board.cols);
      if (grid[r][c] != kEmptyCell) continue;
      // Kenarlarda tam satır/sütunu kilitlememek için üst iki satırı boş bırak.
      if (r < 1) continue;
      grid[r][c] = kBlockerCell;
      placed++;
    }
    return Board.fromGrid(grid);
  }
}
