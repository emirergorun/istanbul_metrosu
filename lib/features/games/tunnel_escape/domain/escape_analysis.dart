import 'dart:math';

import 'escape_level.dart';
import 'escape_solver.dart';

/// Bir bölümün yapısal zorluk ölçüleri — dengeleme raporu için.
///
/// "Daha büyük numara = daha zor" varsayılmıyor; zorluk birkaç ölçünün
/// birleşimi:
///
/// * **en kısa çözüm**: kaç sürükleyiş gerektiği,
/// * **çözüme katılan metro**: bağımlılık zincirinin genişliği,
/// * **durum sayısı**: oyuncunun kaybolabileceği uzayın büyüklüğü,
/// * **dallanma**: çözüm yolunda her adımda kaç yasal hamle olduğu —
///   yanıltıcı seçeneklerin bolluğu.
final class EscapeLevelStats {
  const EscapeLevelStats({
    required this.optimal,
    required this.blockers,
    required this.movedPieces,
    required this.states,
    required this.branching,
  });

  factory EscapeLevelStats.of(EscapeLevel level) {
    final solver = EscapeSolver(level.layout);
    final solution = solver.solve(level.start);
    if (solution == null) {
      throw StateError('Bölüm ${level.number} çözülemiyor');
    }
    final component = solver.explore(level.start);
    var branchingSum = 0;
    var key = level.layout.keyOf(level.start);
    for (final move in solution.path) {
      branchingSum += solver.branching(key);
      key = level.layout.keyWith(key, move.piece, move.to);
    }
    return EscapeLevelStats(
      optimal: solution.moves,
      blockers: level.pieces.length - 1,
      movedPieces: <int>{for (final m in solution.path) m.piece}.length,
      states: component.size,
      branching: solution.moves == 0 ? 0 : branchingSum / solution.moves,
    );
  }

  final int optimal;
  final int blockers;
  final int movedPieces;
  final int states;
  final double branching;

  /// Tek sayıya indirilmiş zorluk — yalnız sıralama ve eğilim için.
  ///
  /// Ağırlıklar kaba: en kısa çözüm baskın, durum uzayı logaritmik (on kat
  /// büyük uzay iki kat zor değil), çözüme katılan metro ve dallanma
  /// ince ayar.
  double get difficulty =>
      optimal +
      log(max(states, 1)) / ln2 * 0.6 +
      movedPieces * 0.4 +
      branching * 0.15;
}
