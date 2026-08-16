import 'dart:math';

import '../../../../core/constants/app_constants.dart';
import '../../../journey/models/difficulty_profile.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/piece_shapes.dart';

/// Tepsiye gelen parçaları üretir.
///
/// Tam random kullanılmaz:
/// - zorluk profiline göre kolay/orta/zor havuzları ağırlıklandırılır,
/// - her havuz bir **torbadır**: çekilen şekil torbadan çıkar, torba bitince
///   karıştırılıp yenilenir,
/// - aynı tepside aynı şekil tekrar etmemeye çalışılır,
/// - üretilen tepside **en az bir** legal hamle olması garanti edilmeye
///   çalışılır (fairness kuralı).
///
/// Torba olmadan ölçüm şuydu: kısa yolculuklarda beş küçük şekil tüm
/// parçaların %41'ini kaplıyor, tepsilerin %17'sinde aynı şekil tekrar
/// ediyordu. Torba, havuzdaki her şeklin görünmesini garanti eder.
class PieceGenerator {
  PieceGenerator({
    Random? random,
    this.colorCount = AppConstants.blockColorCount,
  }) : _random = random ?? Random();

  final Random _random;

  /// Blok renk paletindeki renk sayısı.
  final int colorCount;

  /// Zorluk havuzu başına karıştırılmış torba.
  final Map<PieceDifficulty, List<BlockPiece>> _bags =
      <PieceDifficulty, List<BlockPiece>>{};

  /// Torbadan bir şekil çeker; torba boşsa karıştırıp yeniler.
  BlockPiece _drawShape(PieceDifficulty tier) {
    final bag = _bags[tier] ??= _refill(tier);
    if (bag.isEmpty) bag.addAll(_refill(tier));
    return bag.removeLast();
  }

  List<BlockPiece> _refill(PieceDifficulty tier) =>
      List<BlockPiece>.of(PieceShapes.pool(tier))..shuffle(_random);

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
  BlockPiece nextPiece(DifficultyProfile profile) =>
      _drawShape(_rollDifficulty(profile)).withColor(_randomColor());

  int _randomColor() => 1 + _random.nextInt(colorCount);

  /// Tepsi için parça çeker; mümkünse tepsideki şekilleri tekrarlamaz.
  BlockPiece _nextDistinct(DifficultyProfile profile, Set<String> used) {
    for (var attempt = 0; attempt < 6; attempt++) {
      final piece = nextPiece(profile);
      if (used.add(piece.id)) return piece;
    }
    return nextPiece(profile);
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
      final used = <String>{};
      tray = <BlockPiece>[
        for (var i = 0; i < AppConstants.traySize; i++)
          _nextDistinct(profile, used),
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
          _drawShape(PieceDifficulty.easy).withColor(_randomColor()),
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
      // En üst satır boş bırakılır: oyun açılışında tahtanın tepesi kilitli
      // görünmesin, uzun parçalar için her zaman temiz bir sıra kalsın.
      if (r == 0) continue;
      grid[r][c] = kBlockerCell;
      placed++;
    }
    return Board.fromGrid(grid);
  }
}
