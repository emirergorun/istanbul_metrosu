import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_solver.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';

/// Yukarı ya da aşağı kaymak cazip ama tuzak: metro dikey hatta bir daha
/// ortada duramaz, sol taraf döşenemez kalır. Doğru ilk hamle sola.
///
/// Elle doğrulanan çözüm: sol, aşağı, yukarı, sağ, yukarı, aşağı (6).
final RailLayLevel trapLevel = RailLayLevel.parse(<String>[
  '##.#',
  '##.#',
  '..S#',
  '.#.#',
]);

void main() {
  group('ray döşe — çözücü', () {
    test('düz L: iki hamle, tuzak yok', () {
      final analysis = RailLaySolver(
        RailLayLevel.parse(<String>['S..', '##.', '##.']),
      ).explore()!;

      expect(analysis.optimal, 2);
      expect(analysis.solution, <RailLayDirection>[
        RailLayDirection.right,
        RailLayDirection.down,
      ]);
      expect(analysis.traps, 0);
      expect(analysis.decisions, 0);
    });

    test('tuzaklı tahta: iki cazip yanlış hamle, en kısa çözüm altı', () {
      final analysis = RailLaySolver(trapLevel).explore()!;

      expect(analysis.optimal, 6);
      expect(analysis.solution.first, RailLayDirection.left);
      expect(analysis.traps, 2);
      expect(analysis.deadShare, greaterThan(0));

      // Bulunan çözüm tahtayı gerçekten döşüyor.
      final level = RailLayLevel.parse(<String>[
        '##.#',
        '##.#',
        '..S#',
        '.#.#',
      ], solution: analysis.solution);
      expect(level.solutionPaintsAll(), isTrue);
    });

    test('çözülemeyen tahta ölçülmez', () {
      final analysis = RailLaySolver(
        RailLayLevel.parse(<String>['S..#', '#.##', '#...']),
      ).explore();
      expect(analysis, isNull);
    });

    test('canFinish tuzaktan sonra hayır, doğru hamleden sonra evet der', () {
      final solver = RailLaySolver(trapLevel);
      final start = trapLevel.start;
      var mask = solver.maskOf(start);
      expect(solver.canFinish(start, mask), isTrue);

      // Yukarı: (2,1) ve (2,0) döşenir, metro (2,0)'da durur.
      final up = trapLevel.slide(start, RailLayDirection.up);
      var trapped = mask;
      for (final cell in up) {
        trapped |= solver.maskOf(cell);
      }
      expect(solver.canFinish(up.last, trapped), isFalse);

      // Sola: doğru hamle.
      final left = trapLevel.slide(start, RailLayDirection.left);
      for (final cell in left) {
        mask |= solver.maskOf(cell);
      }
      expect(solver.canFinish(left.last, mask), isTrue);
    });

    test('canFinish sınırı aşınca bilinmiyor der', () {
      final solver = RailLaySolver(trapLevel);
      final up = trapLevel.slide(trapLevel.start, RailLayDirection.up);
      var mask = solver.maskOf(trapLevel.start);
      for (final cell in up) {
        mask |= solver.maskOf(cell);
      }
      expect(solver.canFinish(up.last, mask, cap: 1), isNull);
      expect(const Point<int>(2, 0), up.last);
    });
  });
}
