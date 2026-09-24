import 'dart:collection';
import 'dart:math';

import 'escape_board.dart';
import 'escape_heuristics.dart';
import 'escape_level.dart';
import 'escape_solver.dart';

/// Bir bölümün yapısal zorluk ölçüleri — dengeleme raporu için.
///
/// "Daha büyük numara = daha zor" varsayılmıyor. Hamle sayısı da tek başına
/// yetmiyor: her adımı göze apaçık görünen 12 hamlelik bir bölüm, iki kez
/// "geri" gitmeyi gerektiren 8 hamlelik bir bölümden kolaydır. Ölçüler:
///
/// * **en kısa çözüm**: kaç sürükleyiş gerektiği,
/// * **zincir** ([EscapeHeuristics.dependencyDepth]): başta kimin kimi
///   tuttuğu, C → B → A → kırmızı,
/// * **zorunlu geri hamle** ([detours]): en kısa çözümlerin **hepsinde**
///   tahtayı göze daha tıkalı gösteren kaç hamle var — "aha" anları,
/// * **açgözlü oyuncu** ([greedySolveRate]): yalnız göze iyi gelen hamleyi
///   yapan biri bölümü bitirebiliyor mu,
/// * **durum sayısı** ve **dallanma**: kaybolunabilecek uzayın büyüklüğü ve
///   her adımda kaç yasal hamle olduğu.
final class EscapeLevelStats {
  const EscapeLevelStats({
    required this.optimal,
    required this.blockers,
    required this.movedPieces,
    required this.states,
    required this.branching,
    required this.dependencyDepth,
    required this.detours,
    required this.greedySolveRate,
  });

  factory EscapeLevelStats.of(EscapeLevel level) =>
      EscapeLevelStats.measure(level.layout, level.start);

  factory EscapeLevelStats.measure(EscapeLayout layout, List<int> start) {
    final solver = EscapeSolver(layout);
    final solution = solver.solve(start);
    if (solution == null) {
      throw StateError('Tahta çözülemiyor');
    }
    final component = solver.explore(start);
    var branchingSum = 0;
    var key = layout.keyOf(start);
    for (final move in solution.path) {
      branchingSum += solver.branching(key);
      key = layout.keyWith(key, move.piece, move.to);
    }
    final heuristics = EscapeHeuristics(layout);
    final runs = heuristics.greedyRuns(start);
    // Açgözlü oyuncu en kısa çözümün üç katı içinde bitirebildi mi?
    final limit = max(12, solution.moves * 3);
    final solved = runs.where((int? r) => r != null && r <= limit).length;
    return EscapeLevelStats(
      optimal: solution.moves,
      blockers: layout.pieceCount - 1,
      movedPieces: <int>{for (final m in solution.path) m.piece}.length,
      states: component.size,
      branching: solution.moves == 0 ? 0 : branchingSum / solution.moves,
      dependencyDepth: heuristics.dependencyDepth(start),
      detours: minimumDetours(layout, start, solver, component, heuristics),
      greedySolveRate: solved / runs.length,
    );
  }

  final int optimal;
  final int blockers;
  final int movedPieces;
  final int states;
  final double branching;

  /// Başlangıçtaki bağımlılık zinciri: 2 = önündeki metro doğrudan çekilir.
  final int dependencyDepth;

  /// Bütün en kısa çözümlerde kaçınılmaz "geri" hamle sayısı.
  final int detours;

  /// Açgözlü oyuncunun bölümü makul sürede bitirme oranı (0-1). Yüksekse
  /// bölüm "gözle çözülüyor" demektir.
  final double greedySolveRate;

  /// Tek sayıya indirilmiş zorluk — yalnız sıralama ve eğilim için.
  ///
  /// Ağırlıklar kaba: en kısa çözüm baskın; her zorunlu geri hamle iki
  /// hamle değerinde (oyuncunun takıldığı yer orası); göze çözülen bölüm
  /// cezalı; durum uzayı logaritmik (on kat büyük uzay iki kat zor değil).
  double get difficulty =>
      optimal +
      detours * 2.0 +
      (dependencyDepth - 2).clamp(0, 6) * 1.2 +
      (1 - greedySolveRate) * 4 +
      log(max(states, 1)) / ln2 * 0.4 +
      branching * 0.1;

  /// En kısa çözümlerin hepsinde geçilmesi gereken en az "geri" hamle.
  ///
  /// Geri hamle: tahtayı göze **daha tıkalı** gösteren hamle
  /// ([EscapeHeuristics.blocking] artıyor) ya da kırmızının tünelden
  /// uzaklaşması. Çözücünün seçtiği tek çözüme değil, bütün en kısa
  /// çözümlere bakılıyor: en az geri hamleli yol bile bunu gerektiriyorsa
  /// bölüm gerçekten "önce uzaklaş" diyor demektir.
  static int minimumDetours(
    EscapeLayout layout,
    List<int> start,
    EscapeSolver solver,
    EscapeComponent component,
    EscapeHeuristics heuristics,
  ) {
    final distance = component.distance;
    final startKey = layout.keyOf(start);
    if (!distance.containsKey(startKey)) return 0;

    final score = HashMap<int, int>();
    int blockingOf(int key) => score.putIfAbsent(
      key,
      () => heuristics.blocking(layout.positionsOf(key)),
    );

    // En kısa çözümlerin ağı: her adımda uzaklığı bir azaltan hamleler.
    // Uzaklığa göre katman katman, hedeften geriye doğru en ucuz yol.
    final best = HashMap<int, int>();
    int solve(int key) {
      final cached = best[key];
      if (cached != null) return cached;
      final d = distance[key]!;
      if (d == 0) return best[key] = 0;
      var cheapest = 1 << 20;
      solver.expand(key, (int child) {
        if (distance[child] != d - 1) return;
        final retreat =
            layout.positionIn(child, layout.targetIndex) <
            layout.positionIn(key, layout.targetIndex);
        final cost =
            (retreat || blockingOf(child) > blockingOf(key) ? 1 : 0) +
            solve(child);
        if (cost < cheapest) cheapest = cost;
      });
      return best[key] = cheapest;
    }

    return solve(startKey);
  }
}
