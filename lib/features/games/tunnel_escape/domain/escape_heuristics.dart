import 'dart:math';

import 'escape_board.dart';
import 'escape_solver.dart';

/// Bir tahtanın oyuncu gözüyle okunuşu: ne kadar tıkalı **görünüyor**.
///
/// Çözücü (BFS) bir bölümün kaç hamle sürdüğünü kesin bilir ama oyuncunun
/// ne gördüğünü bilmez. Oyuncu tahtaya bakınca şunu sorar: kırmızının önünde
/// kim var, o kenara çekilebilir mi, çekilemiyorsa onu kim tutuyor? Bu sınıf
/// o soruyu sayıya çeviriyor. Zorluk ölçülerinin üçü buradan çıkıyor:
///
/// * [blocking]: tahtanın ne kadar tıkalı göründüğü. Bir hamle bu sayıyı
///   **artırıyorsa** oyuncuya hedeften uzaklaşmak gibi gelir.
/// * [dependencyDepth]: "A kırmızıyı tutuyor, B de A'yı, C de B'yi" zinciri.
/// * [greedyRuns]: yalnız göze iyi gelen hamleyi yapan bir oyuncunun bölümü
///   bitirip bitiremediği.
///
/// Saf Dart: bölüm üretim aracı da testler de aynı ölçüyü kullanıyor.
final class EscapeHeuristics {
  EscapeHeuristics(this.layout);

  final EscapeLayout layout;

  // --- Tıkanıklık ---

  /// Tahtanın göze görünen tıkanıklığı. Bölüm bittiyse 0.
  ///
  /// `1` (kırmızının kendi hamlesi) + önündeki metro sayısı + her birinin
  /// kenara çekilmesi için yerinden oynaması gereken metro sayısı (en kolay
  /// yöne göre). İki katman bilerek: oyuncu tek bakışta bu kadarını görür.
  int blocking(List<int> positions) {
    final target = layout.targetIndex;
    if (positions[target] == layout.exitPosition) return 0;
    final path = _pathMask(positions);
    var score = 1;
    for (var i = 0; i < layout.pieceCount; i++) {
      if (i == target) continue;
      if (layout.maskOf(i, positions[i]) & path == 0) continue;
      score += 1;
      var cheapest = _stuckPenalty;
      for (final option in _vacateOptions(i, path, positions)) {
        final count = _bitCount(option.blockers);
        if (count < cheapest) cheapest = count;
      }
      score += cheapest;
    }
    return score;
  }

  /// Hiçbir yöne çekilemeyen metronun cezası: tahta kenarı engeli.
  static const int _stuckPenalty = 3;

  // --- Bağımlılık zinciri ---

  /// Başlangıçtaki en uzun "önce o kımıldamalı" zinciri.
  ///
  /// 1: kırmızının önü boş. 2: önündeki metro doğrudan çekilebiliyor.
  /// 4: C → B → A → kırmızı. Her metro için **en kısa** zincirli yön seçilir
  /// (oyuncu da kolay yolu dener); döngüye giren yön sayılmaz.
  ///
  /// Kırmızı metro da zincirin halkası olabilir: bazen önce kendisi geri
  /// çekilmeli ki arkasındaki metro inebilsin. Hiçbir yöne çekilemeyen
  /// halka (tahta kenarı ya da döngü) [_maxDepth] sayılır.
  int dependencyDepth(List<int> positions) {
    final target = layout.targetIndex;
    if (positions[target] == layout.exitPosition) return 0;
    final path = _pathMask(positions);
    var deepest = 0;
    for (var i = 0; i < layout.pieceCount; i++) {
      if (i == target) continue;
      if (layout.maskOf(i, positions[i]) & path == 0) continue;
      final depth = _vacateDepth(i, path, positions, <int>{}, 1);
      if (depth > deepest) deepest = depth;
    }
    return 1 + deepest;
  }

  /// Zincir derinliği sınırı: bundan derini oyuncu için zaten "çok derin".
  static const int _maxDepth = 8;

  int _vacateDepth(
    int piece,
    int cells,
    List<int> positions,
    Set<int> chain,
    int level,
  ) {
    if (level >= _maxDepth) return _maxDepth;
    final nextChain = <int>{...chain, piece};
    var best = _maxDepth;
    for (final option in _vacateOptions(piece, cells, positions)) {
      var worst = 0;
      var cyclic = false;
      for (var j = 0; j < layout.pieceCount; j++) {
        if (option.blockers & (1 << j) == 0) continue;
        if (nextChain.contains(j)) {
          cyclic = true;
          break;
        }
        final depth = _vacateDepth(
          j,
          option.needed,
          positions,
          nextChain,
          level + 1,
        );
        if (depth > worst) worst = depth;
      }
      if (cyclic) continue;
      final depth = 1 + worst;
      if (depth < best) best = depth;
    }
    return best;
  }

  // --- Açgözlü oyuncu ---

  /// Göze en iyi gelen hamleyi yapan oyuncunun [runs] denemesi.
  ///
  /// Her adımda tıkanıklığı ([blocking]) en çok azaltan hamleyi seçer, eşitlikte
  /// rastgele; gördüğü durumlara dönmemeye çalışır ve arada bir (%10) rastgele
  /// dener. Dönen liste her denemenin hamle sayısı; [maxSteps] içinde
  /// bitiremeyen deneme `null`.
  ///
  /// Kolay bölüm: bu oyuncu en kısa çözüme yakın bitirir. Zor bölüm: göze iyi
  /// gelen hamle yanlış yola götürür, oyuncu dolaşır ya da hiç bitiremez.
  List<int?> greedyRuns(
    List<int> start, {
    int runs = 24,
    int maxSteps = 250,
    int seed = 7,
  }) {
    final solver = EscapeSolver(layout);
    final random = Random(seed);
    final results = <int?>[];
    for (var run = 0; run < runs; run++) {
      results.add(_greedyRun(solver, start, random, maxSteps));
    }
    return results;
  }

  int? _greedyRun(
    EscapeSolver solver,
    List<int> start,
    Random random,
    int maxSteps,
  ) {
    var key = layout.keyOf(start);
    final seen = <int>{key};
    for (var step = 1; step <= maxSteps; step++) {
      final children = <int>[];
      solver.expand(key, children.add);
      if (children.isEmpty) return null;
      for (final child in children) {
        if (layout.positionIn(child, layout.targetIndex) ==
            layout.exitPosition) {
          return step;
        }
      }
      final fresh = children.where((int c) => !seen.contains(c)).toList();
      final pool = fresh.isEmpty ? children : fresh;
      int next;
      if (random.nextDouble() < 0.1) {
        next = pool[random.nextInt(pool.length)];
      } else {
        var bestScore = 1 << 30;
        final best = <int>[];
        for (final child in pool) {
          final score = blocking(layout.positionsOf(child));
          if (score < bestScore) {
            bestScore = score;
            best
              ..clear()
              ..add(child);
          } else if (score == bestScore) {
            best.add(child);
          }
        }
        next = best[random.nextInt(best.length)];
      }
      seen.add(next);
      key = next;
    }
    return null;
  }

  // --- Ortak ---

  /// Kırmızının önünden tünele kadar olan hücreler.
  int _pathMask(List<int> positions) {
    final target = layout.target;
    final row = target.lane;
    var mask = 0;
    for (
      var col = positions[layout.targetIndex] + target.length;
      col < layout.width;
      col++
    ) {
      mask |= layout.cellBit(row, col);
    }
    return mask;
  }

  /// [piece]'in [cells] hücrelerinden çekilebileceği en yakın iki konum
  /// (geri ve ileri yönde). Her seçenek: yol boyunca girmesi gereken hücreler
  /// ve o hücrelerde duran metrolar.
  List<_VacateOption> _vacateOptions(
    int piece,
    int cells,
    List<int> positions,
  ) {
    final current = positions[piece];
    final currentMask = layout.maskOf(piece, current);
    var others = 0;
    final owners = List<int>.filled(layout.pieceCount, 0);
    for (var j = 0; j < layout.pieceCount; j++) {
      if (j == piece) continue;
      owners[j] = layout.maskOf(j, positions[j]);
      others |= owners[j];
    }
    final options = <_VacateOption>[];
    for (final step in const <int>[-1, 1]) {
      var needed = 0;
      for (
        var p = current + step;
        p >= 0 && p <= layout.maxPosition(piece);
        p += step
      ) {
        final mask = layout.maskOf(piece, p);
        needed |= mask & ~currentMask;
        if (mask & cells == 0) {
          var blockers = 0;
          if (needed & others != 0) {
            for (var j = 0; j < layout.pieceCount; j++) {
              if (j != piece && owners[j] & needed != 0) blockers |= 1 << j;
            }
          }
          options.add(_VacateOption(needed: needed, blockers: blockers));
          break;
        }
      }
    }
    return options;
  }

  static int _bitCount(int value) {
    var count = 0;
    var v = value;
    while (v != 0) {
      v &= v - 1;
      count++;
    }
    return count;
  }
}

/// Bir metronun kenara çekilme yolu.
final class _VacateOption {
  const _VacateOption({required this.needed, required this.blockers});

  /// Metronun yol boyunca girmesi gereken hücreler.
  final int needed;

  /// O hücrelerde duran metrolar (bit başına bir metro sırası).
  final int blockers;
}
