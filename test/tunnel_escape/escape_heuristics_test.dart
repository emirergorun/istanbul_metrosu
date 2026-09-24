import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_analysis.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_heuristics.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';

/// Zorluk ölçüleri elle kurulmuş küçük tahtalarda: her birinin doğru
/// cevabı gözle görülebiliyor.
void main() {
  EscapeLevel level(List<String> grid) => EscapeLevel.parse(
    number: 1,
    grid: grid,
    optimalMoves: 0,
    threeStarMoves: 0,
    twoStarMoves: 1,
  );

  // Tek engel, iki yöne de serbest.
  final simple = level(<String>[
    '......',
    '......',
    'RR..A.',
    '....A.',
    '......',
    '......',
  ]);

  // Zincir: A kırmızının önünde ve yalnız aşağı çekilebilir (yukarıda yer
  // yok); aşağıda C var, C sola kayınca A iner. C → A → kırmızı.
  final chain = level(<String>[
    '......',
    '....A.',
    'RR..A.',
    '....A.',
    '...CCC',
    '......',
  ]);

  // Önce kırmızı geri çekilmeli: B'nin çıkması için A sola kaymalı, A için
  // C inmeli, C'nin ineceği hücrede de kırmızı duruyor.
  final retreat = level(<String>[
    '..C...',
    '..CAA.',
    '....B.',
    '.RR.B.',
    '....B.',
    '......',
  ]);

  group('Tıkanıklık', () {
    test('çözülmüş tahta 0', () {
      final h = EscapeHeuristics(simple.layout);
      final solved = List<int>.of(simple.start)
        ..[simple.layout.targetIndex] = simple.layout.exitPosition;
      // A kenara çekilmeden R tünelde olamaz; burada yalnız kural sınanıyor.
      expect(h.blocking(solved), 0);
    });

    test('önü boş kırmızı 1, tek serbest engel 2', () {
      final h = EscapeHeuristics(simple.layout);
      expect(h.blocking(simple.start), 2);
      final cleared = List<int>.of(simple.start)..[1] = 4; // A aşağıda
      expect(h.blocking(cleared), 1);
    });

    test('engeli tutan metro da sayılır', () {
      final h = EscapeHeuristics(chain.layout);
      // 1 (kırmızı) + A + A'nın aşağı yolunu tutan C.
      expect(h.blocking(chain.start), 3);
    });
  });

  group('Zincir derinliği', () {
    test('serbest engel: 2', () {
      expect(EscapeHeuristics(simple.layout).dependencyDepth(simple.start), 2);
    });

    test('C → A → kırmızı: 3', () {
      expect(EscapeHeuristics(chain.layout).dependencyDepth(chain.start), 3);
    });

    test('kırmızının kendisi de halka olabilir', () {
      // Kırmızı (geri) → C → A → B → kırmızı: zincirin dibinde kendisi var.
      expect(
        EscapeHeuristics(retreat.layout).dependencyDepth(retreat.start),
        greaterThanOrEqualTo(4),
      );
    });
  });

  group('Zorunlu geri hamle', () {
    test('düz bölümde yok', () {
      expect(EscapeLevelStats.of(simple).detours, 0);
    });

    test('kırmızının geri çekilmesi sayılıyor', () {
      expect(EscapeLevelStats.of(retreat).detours, greaterThanOrEqualTo(1));
    });
  });

  group('Açgözlü oyuncu', () {
    test('tek engelli bölümü her denemede bitirir', () {
      final runs = EscapeHeuristics(simple.layout).greedyRuns(simple.start);
      expect(runs, everyElement(isNotNull));
      final sorted = runs.cast<int>().toList()..sort();
      expect(sorted[sorted.length ~/ 2], 2, reason: 'çoğu deneme en kısa yol');
      expect(EscapeLevelStats.of(simple).greedySolveRate, 1);
    });

    test('aynı tohum aynı sonucu verir', () {
      final h = EscapeHeuristics(retreat.layout);
      expect(h.greedyRuns(retreat.start), h.greedyRuns(retreat.start));
    });
  });

  test('parmak izi ızgaraya bağlı ve kararlı', () {
    final grid = <String>['RR....', '......', '......'];
    expect(EscapeLevel.fingerprintOf(grid), EscapeLevel.fingerprintOf(grid));
    expect(EscapeLevel.fingerprintOf(grid), hasLength(8));
    expect(
      EscapeLevel.fingerprintOf(grid),
      isNot(EscapeLevel.fingerprintOf(<String>['.RR...', '......', '......'])),
    );
    // Sabit değer: algoritma değişirse eski kayıtlar eşleşmez.
    expect(
      EscapeLevel.fingerprintOf(<String>[
        '......',
        '......',
        'RR..A.',
        '....A.',
        '......',
        '......',
      ]),
      '5522d6bc',
    );
  });
}
