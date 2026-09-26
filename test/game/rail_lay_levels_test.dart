import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/data/rail_lay_levels.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_solver.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';

void main() {
  group('ray döşe — bölüm seti', () {
    test('hedeflenen sayıda, sıralı ve benzersiz bölüm var', () {
      expect(RailLayLevels.count, RailLayLevels.target);
      final grids = <String>{};
      for (var i = 0; i < railLayLevelGrids.length; i++) {
        final data = railLayLevelGrids[i];
        expect(data.number, i + 1);
        expect(grids.add(data.grid.join('/')), isTrue, reason: '${i + 1}');
      }
    });

    test('her bölüm telefona ve çözücüye sığar', () {
      for (var n = 1; n <= RailLayLevels.count; n++) {
        final level = RailLayLevels.byNumber(n);
        expect(level.width, lessThanOrEqualTo(railLayMaxWidth), reason: '$n');
        expect(level.height, lessThanOrEqualTo(railLayMaxHeight), reason: '$n');
        expect(
          level.openCount,
          lessThanOrEqualTo(RailLaySolver.maxOpenCells),
          reason: '$n',
        );
      }
    });

    test('kayıtlı çözüm her bölümü tamamen döşer', () {
      for (final data in railLayLevelGrids) {
        final level = RailLayLevels.byNumber(data.number);
        expect(level.solution.length, data.optimal, reason: '${data.number}');
        expect(
          level.solutionPaintsAll(),
          isTrue,
          reason: '${data.number}. bölümün çözümü tahtayı döşemiyor',
        );
      }
    });

    test('ilk 20 bölümün ölçüleri çözücüyle tutuyor', () {
      // Kalanlar araçta ölçüldü; hepsini burada çözmek test süresini
      // şişirirdi.
      for (final data in railLayLevelGrids.take(20)) {
        final analysis = RailLaySolver(
          RailLayLevels.byNumber(data.number),
        ).explore()!;
        expect(analysis.optimal, data.optimal, reason: '${data.number}');
        expect(analysis.traps, data.traps, reason: '${data.number}');
        expect(analysis.decisions, data.decisions, reason: '${data.number}');
      }
    });

    test('zorluk rampası: öğretici, sonra tuzaklar', () {
      // Kullanıcının şikâyeti: "16. bölüme geldim, hâlâ zorlanma yok."
      // Her bölümün tek bir doğru yönü vardı. Artık seçim ve tuzak var.
      for (final data in railLayLevelGrids.take(2)) {
        expect(data.traps, 0, reason: '${data.number} öğretici');
        expect(data.decisions, greaterThanOrEqualTo(1));
      }
      for (final data in railLayLevelGrids.skip(2)) {
        expect(
          data.traps,
          greaterThanOrEqualTo(data.number <= 10 ? 1 : 2),
          reason: '${data.number}. bölümde yeterli tuzak yok',
        );
      }

      int scoreOf(RailLayLevelData d) =>
          d.optimal + 3 * d.traps + 2 * d.decisions;
      double mean(int from, int to) {
        final slice = railLayLevelGrids.sublist(from - 1, to);
        return slice.map(scoreOf).reduce((a, b) => a + b) / slice.length;
      }

      // On bölümlük ortalama hiç belirgin düşmüyor.
      var previous = mean(1, 10);
      for (var from = 11; from + 9 <= RailLayLevels.count; from += 10) {
        final current = mean(from, from + 9);
        expect(
          current,
          greaterThanOrEqualTo(previous - 2),
          reason: '$from-${from + 9}. bölümler öncekilerden kolay',
        );
        previous = current;
      }
      expect(mean(141, 150), greaterThan(mean(11, 20) * 1.8));
    });

    test('son bölümden sonra en zor bölümler döner', () {
      final count = RailLayLevels.count;
      final after = RailLayLevels.byNumber(count + 1);
      expect(after.number, count + 1);
      expect(
        RailLayLevels.dataIndexFor(count + 1),
        count - RailLayLevels.loopLength,
      );
      expect(
        RailLayLevels.dataIndexFor(count + RailLayLevels.loopLength),
        count - 1,
      );
      expect(
        RailLayLevels.dataIndexFor(count + RailLayLevels.loopLength + 1),
        count - RailLayLevels.loopLength,
      );
    });
  });

  group('ray döşe — kayış', () {
    final level = RailLayLevel.parse(<String>['S...#', '#.#.#', '#...#']);

    test('kayış duvara kadar gider', () {
      final path = level.slide(level.start, RailLayDirection.right);
      expect(path.map((p) => p.x), <int>[1, 2, 3]);
      expect(path.last, const Point<int>(3, 0));
    });

    test('önü duvarsa kayış yok', () {
      expect(level.slide(level.start, RailLayDirection.up), isEmpty);
      expect(level.slide(level.start, RailLayDirection.down), isEmpty);
    });

    test('puan: açık kare + 3 × en kısa çözüm', () {
      final first = RailLayLevels.byNumber(1);
      expect(first.points, first.openCount + 3 * first.solution.length);
    });
  });
}
