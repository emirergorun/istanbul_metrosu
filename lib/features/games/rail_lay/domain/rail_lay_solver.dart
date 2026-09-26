import 'dart:math';

import 'rail_lay_state.dart';

/// Bir bölümün çözücüyle ölçülen zorluğu.
class RailLayAnalysis {
  const RailLayAnalysis({
    required this.optimal,
    required this.solution,
    required this.decisions,
    required this.traps,
    required this.states,
    required this.deadShare,
  });

  /// En kısa çözümün hamle sayısı.
  final int optimal;

  /// En kısa çözümlerden biri.
  final List<RailLayDirection> solution;

  /// En kısa çözüm boyunca, yeni kare döşeyip bölümü **bitirilebilir**
  /// bırakan birden fazla hamlenin olduğu duruş sayısı — oyuncunun gerçekten
  /// seçim yaptığı an.
  final int decisions;

  /// En kısa çözüm boyunca, yeni kare döşeyen ama bölümü **bitirilemez**
  /// hâle getiren hamle sayısı — cazip görünen yanlış hamleler. Bu türün
  /// asıl zorluğu bunlar: videodaki "yanlış sırayla gidersen o kareye bir
  /// daha ulaşamazsın".
  final int traps;

  /// Başlangıçtan ulaşılabilen durum sayısı.
  final int states;

  /// Ulaşılabilen durumların ne kadarı artık bitirilemez (0..1).
  final double deadShare;

  /// Seçim ve tuzağın ağırlıklandırıldığı zorluk puanı; araç bölümleri buna
  /// göre sıralar.
  int get score => optimal + 3 * traps + 2 * decisions;
}

/// Ray Döşe çözücüsü.
///
/// Durum: metronun durduğu kare + döşenmiş karelerin maskesi. Maske tek bir
/// `int`: açık kare sayısı en fazla [maxOpenCells] (Dart'ın yerel `int`'i 64
/// bit; işaret biti ve bir yedek pay dışarıda). Bölüm aracı bu sınırı
/// zorluyor.
///
/// Tünele Kaç'ın çözücüsüyle aynı ilke: oyundaki kural ile bölümü
/// doğrulayan kural ayrı düşemesin diye araç da oyun da bu sınıfı
/// kullanıyor.
class RailLaySolver {
  RailLaySolver(this.level)
    : assert(level.openCount <= maxOpenCells, 'Tahta çözücüye sığmıyor') {
    var ordinal = 0;
    _bit = List<int>.filled(level.width * level.height, -1);
    for (var i = 0; i < _bit.length; i++) {
      if (level.open[i]) _bit[i] = ordinal++;
    }
    fullMask = (1 << ordinal) - 1;
  }

  /// Maskeye sığan en fazla açık kare.
  static const int maxOpenCells = 62;

  final RailLayLevel level;
  late final List<int> _bit;
  late final int fullMask;

  /// Duruş → yön → (sonraki duruş, geçilen kareler). Tembel doldurulur.
  final Map<int, List<(int, int)?>> _moves = <int, List<(int, int)?>>{};

  /// Bir karenin maske biti.
  int maskOf(Point<int> cell) => 1 << _bit[level.indexOf(cell)];

  /// Döşenmiş kareler listesinden maske.
  int maskFromPaint(List<int> paint) {
    var mask = 0;
    for (var i = 0; i < paint.length; i++) {
      if (paint[i] != 0 && _bit[i] >= 0) mask |= 1 << _bit[i];
    }
    return mask;
  }

  List<(int, int)?> _movesFrom(int stop) => _moves.putIfAbsent(stop, () {
    final from = Point<int>(stop % level.width, stop ~/ level.width);
    return <(int, int)?>[
      for (final direction in RailLayDirection.values)
        () {
          final path = level.slide(from, direction);
          if (path.isEmpty) return null;
          var mask = 0;
          for (final cell in path) {
            mask |= 1 << _bit[level.indexOf(cell)];
          }
          return (level.indexOf(path.last), mask);
        }(),
    ];
  });

  /// Başlangıçtan bütün durum uzayını çıkarır ve ölçer.
  ///
  /// Durum sayısı [cap]'i aşarsa ya da bölüm çözülemiyorsa `null`.
  RailLayAnalysis? explore({int cap = 300000}) {
    final startStop = level.indexOf(level.start);
    final startMask = maskOf(level.start);

    final stopOf = <int>[startStop];
    final maskOfState = <int>[startMask];
    final parent = <int>[-1];
    final parentMove = <int>[-1];
    final successors = <List<int>>[];
    final seen = <int, Map<int, int>>{
      startStop: <int, int>{startMask: 0},
    };

    var goal = -1;
    for (var id = 0; id < stopOf.length; id++) {
      final stop = stopOf[id];
      final mask = maskOfState[id];
      if (mask == fullMask && goal < 0) goal = id;
      final next = List<int>.filled(RailLayDirection.values.length, -1);
      final moves = _movesFrom(stop);
      for (var d = 0; d < moves.length; d++) {
        final move = moves[d];
        if (move == null) continue;
        final (to, path) = move;
        final toMask = mask | path;
        final byMask = seen.putIfAbsent(to, () => <int, int>{});
        var target = byMask[toMask];
        if (target == null) {
          target = stopOf.length;
          if (target >= cap) return null;
          byMask[toMask] = target;
          stopOf.add(to);
          maskOfState.add(toMask);
          parent.add(id);
          parentMove.add(d);
        }
        next[d] = target;
      }
      successors.add(next);
    }
    if (goal < 0) return null;

    // Canlı durumlar: hedefe ulaşabilenler (geri tarama).
    final predecessors = List<List<int>>.generate(
      stopOf.length,
      (_) => <int>[],
    );
    for (var id = 0; id < successors.length; id++) {
      for (final to in successors[id]) {
        if (to >= 0) predecessors[to].add(id);
      }
    }
    final alive = List<bool>.filled(stopOf.length, false);
    final queue = <int>[];
    for (var id = 0; id < stopOf.length; id++) {
      if (maskOfState[id] == fullMask) {
        alive[id] = true;
        queue.add(id);
      }
    }
    for (var head = 0; head < queue.length; head++) {
      for (final from in predecessors[queue[head]]) {
        if (alive[from]) continue;
        alive[from] = true;
        queue.add(from);
      }
    }

    // BFS ağacında ilk bulunan hedef en kısa çözümdür.
    final pathStates = <int>[];
    final solution = <RailLayDirection>[];
    for (var id = goal; id > 0; id = parent[id]) {
      pathStates.add(parent[id]);
      solution.add(RailLayDirection.values[parentMove[id]]);
    }
    final ordered = pathStates.reversed.toList();

    var decisions = 0;
    var traps = 0;
    for (final id in ordered) {
      final mask = maskOfState[id];
      var goodChoices = 0;
      for (final to in successors[id]) {
        if (to < 0) continue;
        final paintsNew = (maskOfState[to] & ~mask) != 0;
        if (!paintsNew) continue;
        if (alive[to]) {
          goodChoices++;
        } else {
          traps++;
        }
      }
      if (goodChoices >= 2) decisions++;
    }

    final dead = alive.where((bool a) => !a).length;
    return RailLayAnalysis(
      optimal: solution.length,
      solution: solution.reversed.toList(),
      decisions: decisions,
      traps: traps,
      states: stopOf.length,
      deadShare: dead / stopOf.length,
    );
  }

  /// [position]'da, [mask] döşenmişken bölüm hâlâ bitirilebilir mi?
  ///
  /// Derinlik öncelikli arama; önce en çok yeni kare döşeyen hamle denenir,
  /// böylece çözülebilir durumlarda cevap genellikle birkaç düzine durumda
  /// bulunur. Bitirilemez durumlarda bütün uzay taranmak zorunda; [cap]
  /// aşılırsa `null` ("bilinmiyor") döner.
  bool? canFinish(Point<int> position, int mask, {int cap = 20000}) {
    if (mask == fullMask) return true;
    final seen = <int, Set<int>>{};
    final stack = <(int, int)>[(level.indexOf(position), mask)];
    var visited = 0;
    while (stack.isNotEmpty) {
      final (stop, current) = stack.removeLast();
      if (!seen.putIfAbsent(stop, () => <int>{}).add(current)) continue;
      if (++visited > cap) return null;

      final options = <(int, int, int)>[];
      for (final move in _movesFrom(stop)) {
        if (move == null) continue;
        final (to, path) = move;
        final next = current | path;
        if (next == fullMask) return true;
        options.add((to, next, _bitCount(next & ~current)));
      }
      // Yığın sondan çektiği için en iyi hamle en sona.
      options.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (to, next, _) in options) {
        stack.add((to, next));
      }
    }
    return false;
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
