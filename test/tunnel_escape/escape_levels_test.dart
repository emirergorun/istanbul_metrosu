import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_level_grids.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_levels.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_analysis.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_board.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_piece.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_rules.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_solver.dart';

/// Gönderilen **her** bölüm çözücüyle yeniden doğrulanır.
///
/// Hiçbir bölüm "çözülebilir görünüyor" diye oyunda değil: bu test bir
/// bölüm bozulursa (veri elle düzenlendi, kural değişti) hangi bölüm
/// olduğunu ve neden olduğunu söyler. Test gevşetilmez, bölüm düzeltilir.
void main() {
  final levels = EscapeLevels.all;

  test('60 bölüm, sıralı ve benzersiz numara', () {
    expect(levels, hasLength(60));
    for (var i = 0; i < levels.length; i++) {
      expect(levels[i].number, i + 1);
      expect(escapeLevelData[i].number, i + 1);
    }
  });

  test('aynı tahta iki kez gönderilmiyor', () {
    final grids = <String>{
      for (final data in escapeLevelData) data.grid.join('/'),
    };
    expect(grids, hasLength(levels.length));
  });

  group('Geçerlilik', () {
    for (final level in levels) {
      test('bölüm ${level.number}', () {
        expect(level.width, 6);
        expect(level.height, 6);

        final board = level.initialBoard;
        expect(board.isValid, isTrue, reason: 'başlangıçta üst üste binme');

        final ids = <String>{};
        for (var i = 0; i < level.pieces.length; i++) {
          final piece = level.pieces[i];
          expect(ids.add(piece.id), isTrue, reason: 'aynı harf iki kez');
          expect(piece.length, inInclusiveRange(2, 3), reason: piece.id);
          expect(
            level.start[i],
            inInclusiveRange(0, level.layout.maxPosition(i)),
            reason: '${piece.id} tahtanın dışında',
          );
          // Hedefin satırında başka yatay metro yok: sağında dursa
          // bölüm çözülemez, solunda dursa hiçbir şey yapmaz.
          if (!piece.isTarget && piece.isHorizontal) {
            expect(piece.lane, isNot(level.exitRow), reason: piece.id);
          }
        }

        final target = level.layout.target;
        expect(target.isHorizontal, isTrue);
        expect(target.length, 2);
        expect(target.lane, level.exitRow, reason: 'hedef tünelin hizasında');
        expect(board.isSolved, isFalse, reason: 'bölüm çözülmüş başlamamalı');

        expect(level.threeStarMoves, greaterThanOrEqualTo(level.optimalMoves));
        expect(level.twoStarMoves, greaterThan(level.threeStarMoves));
      });
    }
  });

  group('Çözücü doğrulaması', () {
    for (final level in levels) {
      test('bölüm ${level.number}: çözülebilir, en kısa çözüm '
          '${level.optimalMoves}', () {
        final solver = EscapeSolver(level.layout);
        final solution = solver.solve(level.start);
        expect(solution, isNotNull, reason: 'çözümsüz bölüm');
        expect(solution!.moves, level.optimalMoves);

        // Çözümü oynat: her hamle yasal, sonunda kırmızı tünelde.
        var board = level.initialBoard;
        for (final move in solution.path) {
          expect(board.canMove(move.piece, move.to), isTrue, reason: '$move');
          board = board.moved(move.piece, move.to);
        }
        expect(board.isSolved, isTrue);

        // Yıldız sınırları kuraldan türüyor: veri ile kural ayrı düşmesin.
        final stats = EscapeLevelStats.of(level);
        expect(
          (level.threeStarMoves, level.twoStarMoves),
          EscapeRules.parFor(
            optimal: stats.optimal,
            branching: stats.branching,
          ),
          reason: 'yıldız sınırları yeniden hesaplanmalı',
        );
      });
    }
  });

  group('Zorluk eğrisi', () {
    final stats = <int, EscapeLevelStats>{
      for (final level in levels) level.number: EscapeLevelStats.of(level),
    };

    double average(EscapeTier tier, double Function(EscapeLevelStats) of) {
      final values = <double>[
        for (final level in levels)
          if (level.tier == tier) of(stats[level.number]!),
      ];
      return values.reduce((a, b) => a + b) / values.length;
    }

    test('öğretici bölümler kısa ve her metro çözüme katılıyor', () {
      expect(stats[1]!.optimal, lessThanOrEqualTo(2), reason: 'ilk bölüm');
      for (final level in levels.where(
        (l) => l.tier == EscapeTier.onboarding,
      )) {
        final s = stats[level.number]!;
        expect(s.optimal, lessThanOrEqualTo(6), reason: '${level.number}');
        expect(s.detours, lessThanOrEqualTo(1), reason: '${level.number}');
        expect(
          s.movedPieces,
          level.pieces.length,
          reason: 'bölüm ${level.number}: süs metro yeni oyuncuyu yanıltır',
        );
      }
    });

    test('kuşaktan kuşağa en kısa çözüm uzuyor', () {
      final tiers = EscapeTier.values;
      for (var i = 1; i < tiers.length; i++) {
        expect(
          average(tiers[i], (s) => s.optimal.toDouble()),
          greaterThan(average(tiers[i - 1], (s) => s.optimal.toDouble())),
          reason: '${tiers[i]} bir öncekinden kolay',
        );
      }
    });

    test('kuşaktan kuşağa bileşik zorluk artıyor', () {
      final tiers = EscapeTier.values;
      for (var i = 1; i < tiers.length; i++) {
        expect(
          average(tiers[i], (s) => s.difficulty),
          greaterThan(average(tiers[i - 1], (s) => s.difficulty)),
          reason: '${tiers[i]} bir öncekinden kolay',
        );
      }
    });

    test('son durak en zor bölüm', () {
      final finale = stats[levels.last.number]!;
      for (final level in levels.take(levels.length - 1)) {
        expect(
          stats[level.number]!.optimal,
          lessThanOrEqualTo(finale.optimal),
          reason: 'bölüm ${level.number} son duraktan uzun',
        );
      }
    });

    test('geç bölümlerde basit tahta yok', () {
      for (final level in levels.where((l) => l.number > 30)) {
        expect(
          stats[level.number]!.optimal,
          greaterThanOrEqualTo(15),
          reason: 'bölüm ${level.number} fazla kolay',
        );
      }
    });

    // "Bu çok kolay" şikâyetinin ölçüsü: hamle sayısı değil, çözümün
    // gözle bulunup bulunmadığı. Eşikler dengeleme aracındaki kuşak
    // kurallarıyla aynı (tool/tunnel_escape/generate_levels.dart).

    test('öğreticiden sonra her bölüm en az bir "önce uzaklaş" istiyor', () {
      for (final level in levels.where((l) => l.number > 5)) {
        final s = stats[level.number]!;
        final least = level.number > 30
            ? 4
            : level.number > 15
            ? 3
            : 1;
        expect(
          s.detours,
          greaterThanOrEqualTo(least),
          reason: 'bölüm ${level.number}: çözüm hep ileri gidiyor',
        );
      }
    });

    test('zorunlu geri hamle kuşaktan kuşağa artıyor', () {
      final tiers = EscapeTier.values;
      for (var i = 1; i < tiers.length; i++) {
        expect(
          average(tiers[i], (s) => s.detours.toDouble()),
          greaterThan(average(tiers[i - 1], (s) => s.detours.toDouble())),
          reason: '${tiers[i]}',
        );
      }
    });

    test('planlama kuşağından sonra bölümler gözle çözülmüyor', () {
      for (final level in levels.where((l) => l.number > 15)) {
        final rate = stats[level.number]!.greedySolveRate;
        expect(
          rate,
          lessThanOrEqualTo(level.number > 30 ? 0.1 : 0.25),
          reason:
              'bölüm ${level.number}: göze iyi gelen hamleyle '
              '%${(rate * 100).round()} bitiyor',
        );
      }
    });

    test('zorluk kalabalıktan gelmiyor: tahtalar dolu değil', () {
      for (final level in levels) {
        expect(
          stats[level.number]!.blockers,
          lessThanOrEqualTo(13),
          reason: 'bölüm ${level.number}',
        );
      }
      final roomy = levels
          .where((l) => l.number > 30 && stats[l.number]!.blockers <= 9)
          .length;
      expect(roomy, greaterThanOrEqualTo(15), reason: 'geç bölümler hep sık');
    });

    test('her kuşakta bir nefes bölümü var', () {
      for (final tier in EscapeTier.values.where(
        (t) => t != EscapeTier.onboarding && t != EscapeTier.finale,
      )) {
        final numbers = <int>[
          for (final l in levels)
            if (l.tier == tier) l.number,
        ];
        final breather = numbers
            .skip(1)
            .any((int n) => stats[n]!.optimal < stats[n - 1]!.optimal);
        expect(breather, isTrue, reason: '$tier hep tırmanıyor');
      }
    });

    test('üç yıldız en iyi çözüme yakın, iki yıldız belirgin pay', () {
      for (final level in levels) {
        expect(
          level.threeStarMoves - level.optimalMoves,
          lessThanOrEqualTo(3),
          reason: 'bölüm ${level.number}',
        );
        expect(
          level.twoStarMoves - level.threeStarMoves,
          greaterThanOrEqualTo(2),
          reason: 'bölüm ${level.number}',
        );
      }
    });

    test('durum uzayı çözücünün güvenlik sınırının çok altında', () {
      for (final level in levels) {
        expect(
          stats[level.number]!.states,
          lessThan(EscapeSolver(level.layout).maxStates ~/ 4),
          reason: 'bölüm ${level.number}',
        );
      }
    });
  });

  test('her bölümün parmak izi benzersiz ve ızgaradan türüyor', () {
    final prints = <String>{};
    for (final level in levels) {
      expect(
        level.fingerprint,
        EscapeLevel.fingerprintOf(escapeLevelData[level.number - 1].grid),
      );
      expect(prints.add(level.fingerprint), isTrue, reason: '${level.number}');
    }
    expect(EscapeLevels.fingerprints, hasLength(levels.length));
  });

  test('ipucu her bölümde en kısa çözümün ilk adımı', () {
    for (final level in levels) {
      final solver = EscapeSolver(level.layout);
      final hint = solver.nextMove(level.start)!;
      final after = List<int>.of(level.start)..[hint.piece] = hint.to;
      expect(
        solver.solve(after)!.moves,
        level.optimalMoves - 1,
        reason: 'bölüm ${level.number}: ipucu çözümden uzaklaştırıyor',
      );
    }
  });

  test('ızgara verisi metro dilinde: yalnız R hedef', () {
    for (final level in levels) {
      final targets = level.pieces.where((EscapePiece p) => p.isTarget);
      expect(targets, hasLength(1));
      expect(targets.single.id, EscapeLevel.targetId);
      expect(
        EscapeLevel.render(level.layout, level.start),
        escapeLevelData[level.number - 1].grid,
      );
      expect(EscapeBoard(level.layout, level.start).isValid, isTrue);
    }
  });
}
