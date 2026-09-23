import 'dart:collection';

import 'escape_board.dart';

/// Çözücünün cevabı: en kısa çözümün uzunluğu ve bir örneği.
final class EscapeSolution {
  const EscapeSolution({required this.path, required this.explored});

  /// En kısa çözümün hamleleri, sırasıyla. Hedef zaten tüneldeyse boş.
  final List<EscapeMove> path;

  /// Aramanın açtığı durum sayısı — zorluk raporunda kullanılır.
  final int explored;

  int get moves => path.length;
}

/// Tünele Kaç'ın çözücüsü: genişlik öncelikli arama (BFS).
///
/// **Neden BFS.** Hamle ölçüsü "tek sürükleyiş": her kenarın bedeli 1. Bu
/// durumda BFS'in bulduğu ilk çözüm en kısa çözümdür ve ispatı ekstra bir
/// sezgi (A* tahmini) gerektirmez. 6×6 tahtada bir bölümün bütün erişilebilir
/// durumları birkaç yüz bin mertebesinde; BFS rahatça sığıyor.
///
/// **Belirlenimci.** Komşular her zaman aynı sırayla üretilir (metro sırası,
/// önce geri sonra ileri, yakından uzağa). Aynı tahta her seferinde aynı
/// çözümü ve aynı ipucunu verir — testler bu yüzden tek bir yola
/// sabitlenebiliyor.
///
/// Durumlar [EscapeLayout.keyOf] ile tek bir tamsayıya indiriliyor; ziyaret
/// kümesi ve ebeveyn tablosu bu anahtarlarla tutuluyor.
final class EscapeSolver {
  EscapeSolver(this.layout, {this.maxStates = 3000000});

  final EscapeLayout layout;

  /// Güvenlik sınırı: bu kadar durum açılıp çözüm bulunamazsa arama durur
  /// ve bölüm "çözülemedi" sayılır. Gönderilen bölümlerin hiçbiri bu sınıra
  /// yaklaşmıyor (bkz. bölüm testi).
  final int maxStates;

  /// [start] dizilişinin en kısa çözümü; çözüm yoksa `null`.
  EscapeSolution? solve(List<int> start) {
    final startKey = layout.keyOf(start);
    if (_isGoal(startKey)) {
      return const EscapeSolution(path: <EscapeMove>[], explored: 1);
    }

    final parents = HashMap<int, int>()..[startKey] = startKey;
    final queue = ListQueue<int>()..add(startKey);
    var goalKey = -1;

    search:
    while (queue.isNotEmpty) {
      final key = queue.removeFirst();
      final children = <int>[];
      expand(key, children.add);
      for (final child in children) {
        if (parents.containsKey(child)) continue;
        parents[child] = key;
        if (_isGoal(child)) {
          goalKey = child;
          break search;
        }
        if (parents.length >= maxStates) return null;
        queue.add(child);
      }
    }
    if (goalKey < 0) return null;

    final path = <EscapeMove>[];
    var key = goalKey;
    while (key != startKey) {
      final parent = parents[key]!;
      path.add(_moveBetween(parent, key));
      key = parent;
    }
    return EscapeSolution(
      path: path.reversed.toList(growable: false),
      explored: parents.length,
    );
  }

  /// En kısa çözüme götüren **ilk** hamle — ipucu budur.
  ///
  /// Bütün çözümü değil, yalnız sıradaki faydalı adımı verir.
  EscapeMove? nextMove(List<int> positions) {
    final solution = solve(positions);
    if (solution == null || solution.path.isEmpty) return null;
    return solution.path.first;
  }

  /// [key] durumundan tek hamlede varılan bütün durumlar.
  ///
  /// Sıra sabit: metro sırası, her metroda önce geri (sol/yukarı) yakından
  /// uzağa, sonra ileri yakından uzağa.
  void expand(int key, void Function(int child) visit) {
    final count = layout.pieceCount;
    var occupied = 0;
    for (var i = 0; i < count; i++) {
      occupied |= layout.maskOf(i, layout.positionIn(key, i));
    }
    for (var i = 0; i < count; i++) {
      final position = layout.positionIn(key, i);
      final others = occupied & ~layout.maskOf(i, position);
      for (var p = position - 1; p >= 0; p--) {
        if (layout.maskOf(i, p) & others != 0) break;
        visit(layout.keyWith(key, i, p));
      }
      final max = layout.maxPosition(i);
      for (var p = position + 1; p <= max; p++) {
        if (layout.maskOf(i, p) & others != 0) break;
        visit(layout.keyWith(key, i, p));
      }
    }
  }

  /// Bir durumdaki yasal hamle sayısı — dallanma ölçüsü.
  int branching(int key) {
    var count = 0;
    expand(key, (_) => count++);
    return count;
  }

  /// [start]'tan erişilebilen **bütün** durumların haritası.
  ///
  /// Hamleler geri alınabilir (her kaydırmanın tersi de yasal bir
  /// kaydırma), yani durum çizgesi yönsüz. Bu yüzden "bu durumun çözümü kaç
  /// hamle" sorusu, bütün hedef durumlardan aynı anda başlayan tek bir
  /// BFS ile her durum için birden cevaplanabiliyor. Bölüm üretim aracı en
  /// zor başlangıcı bununla buluyor.
  EscapeComponent explore(List<int> start) {
    final startKey = layout.keyOf(start);
    final seen = HashSet<int>()..add(startKey);
    final order = <int>[startKey];
    for (var head = 0; head < order.length; head++) {
      if (order.length > maxStates) {
        throw StateError('Durum uzayı $maxStates sınırını aştı');
      }
      expand(order[head], (int child) {
        if (seen.add(child)) order.add(child);
      });
    }

    final distance = HashMap<int, int>();
    final queue = ListQueue<int>();
    for (final key in order) {
      if (_isGoal(key)) {
        distance[key] = 0;
        queue.add(key);
      }
    }
    while (queue.isNotEmpty) {
      final key = queue.removeFirst();
      final next = distance[key]! + 1;
      expand(key, (int child) {
        if (distance.containsKey(child)) return;
        distance[child] = next;
        queue.add(child);
      });
    }
    return EscapeComponent(states: order, distance: distance);
  }

  bool _isGoal(int key) =>
      layout.positionIn(key, layout.targetIndex) == layout.exitPosition;

  EscapeMove _moveBetween(int from, int to) {
    for (var i = 0; i < layout.pieceCount; i++) {
      final a = layout.positionIn(from, i);
      final b = layout.positionIn(to, i);
      if (a != b) return EscapeMove(piece: i, from: a, to: b);
    }
    throw StateError('Aynı durum iki kez yazılmış');
  }
}

/// Bir başlangıçtan erişilebilen durumlar ve her birinin çözüm uzaklığı.
final class EscapeComponent {
  EscapeComponent({required this.states, required this.distance});

  /// BFS sırasıyla bütün durumlar.
  final List<int> states;

  /// Duruma göre en kısa çözüm uzunluğu. Hedefe hiç ulaşamayan bir
  /// bileşende boş kalır.
  final Map<int, int> distance;

  int get size => states.length;

  bool get isSolvable => distance.isNotEmpty;

  /// Bileşendeki en uzun en-kısa-çözüm.
  int get maxDistance {
    var best = -1;
    for (final value in distance.values) {
      if (value > best) best = value;
    }
    return best;
  }
}
