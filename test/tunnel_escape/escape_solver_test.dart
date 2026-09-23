import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_board.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_solver.dart';

(EscapeSolver, List<int>) solverFor(List<String> grid) {
  final (layout, start) = EscapeLevel.parseGrid(grid);
  return (EscapeSolver(layout), start);
}

/// Çözüm yolunu baştan oynatır: her hamle yasal mı, son durum çözülmüş mü?
void expectPlayable(EscapeSolver solver, List<int> start, EscapeSolution s) {
  var board = EscapeBoard(solver.layout, start);
  for (final move in s.path) {
    expect(board.positions[move.piece], move.from, reason: '$move');
    expect(board.canMove(move.piece, move.to), isTrue, reason: '$move');
    board = board.moved(move.piece, move.to);
  }
  expect(board.isSolved, isTrue);
}

void main() {
  group('Çözücü', () {
    test('yolu açık hedef tek hamlede çözülür', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '......',
        'RR....',
        '......',
        '......',
        '......',
      ]);
      final solution = solver.solve(start)!;
      expect(solution.moves, 1);
      // Tek sürükleyiş: kırmızı baştan tünel ağzına.
      expect(solution.path.single.from, 0);
      expect(solution.path.single.to, 4);
    });

    test('tünel ağzındaki hedef sıfır hamle', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '......',
        '....RR',
        '......',
        '......',
        '......',
      ]);
      expect(solver.solve(start)!.moves, 0);
    });

    test('bilinen en kısa çözüm: engel + hedef = 2', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '......',
        'RR..A.',
        '....A.',
        '......',
        '......',
      ]);
      final solution = solver.solve(start)!;
      expect(solution.moves, 2);
      expectPlayable(solver, start, solution);
    });

    test('zincirleme çözüm: yatay, sonra dikey, sonra hedef = 3', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '....A.',
        'RR..A.',
        '....A.',
        '......',
        '...BB.',
      ]);
      final solution = solver.solve(start)!;
      expect(solution.moves, 3);
      expectPlayable(solver, start, solution);
      // İlk hamle B'yi (yatay) oynatmak zorunda: A başka türlü inemez.
      expect(solver.layout.pieces[solution.path.first.piece].id, 'B');
    });

    test('çözümsüz bölüm null döner', () {
      // Hedefin önünde 3 hücrelik dikey metro; iki ucu da yatay metrolarla
      // kilitli, yatay metrolar da duvarla kilitli.
      final (solver, start) = solverFor(<String>[
        '......',
        '...A..',
        'RR.A..',
        '...A..',
        'CCCDDD',
        '......',
      ]);
      // Yukarı: A zaten 1-3; 0-2 de hâlâ satır 2'yi kapatır. Aşağı: C ve D
      // tam satırı dolduruyor, kıpırdayamazlar.
      expect(solver.solve(start), isNull);
      expect(solver.explore(start).isSolvable, isFalse);
    });

    test('aynı tahta her seferinde aynı çözümü verir', () {
      const grid = <String>[
        '..ABBB',
        '..A...',
        'RRA..C',
        '.....C',
        'DD....',
        '....EE',
      ];
      final (a, start) = solverFor(grid);
      final (b, _) = solverFor(grid);
      final first = a.solve(start)!;
      final second = b.solve(start)!;
      expect(first.moves, second.moves);
      expect(first.path, second.path);
      expectPlayable(a, start, first);
    });

    test('ipucu en kısa çözümün ilk hamlesi', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '....A.',
        'RR..A.',
        '....A.',
        '......',
        '...BB.',
      ]);
      final hint = solver.nextMove(start)!;
      expect(hint, solver.solve(start)!.path.first);
      // İpucunu uygulayınca kalan çözüm bir kısalır.
      final after = EscapeBoard(
        solver.layout,
        start,
      ).moved(hint.piece, hint.to);
      expect(solver.solve(after.positions)!.moves, 2);
    });

    test('çözülmüş tahtada ipucu yok', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '......',
        '....RR',
        '......',
        '......',
        '......',
      ]);
      expect(solver.nextMove(start), isNull);
    });
  });

  group('Durum uzayı', () {
    test('her durum bir kez açılır: ziyaret kümesi tekrar etmez', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '....A.',
        'RR..A.',
        '....A.',
        '......',
        '...BB.',
      ]);
      final component = solver.explore(start);
      expect(component.states.toSet().length, component.size);
      // Her durumun bütün komşuları da bileşende.
      final all = component.states.toSet();
      for (final key in component.states) {
        solver.expand(key, (int child) {
          expect(all.contains(child), isTrue);
        });
      }
    });

    test('hamleler geri alınabilir: komşuluk simetrik', () {
      final (solver, start) = solverFor(<String>[
        '..ABBB',
        '..A...',
        'RRA..C',
        '.....C',
        'DD....',
        '....EE',
      ]);
      final key = solver.layout.keyOf(start);
      solver.expand(key, (int child) {
        final back = <int>[];
        solver.expand(child, back.add);
        expect(back, contains(key));
      });
    });

    test('uzaklık haritası çözücüyle aynı sayıyı verir', () {
      final (solver, start) = solverFor(<String>[
        '......',
        '....A.',
        'RR..A.',
        '....A.',
        '......',
        '...BB.',
      ]);
      final component = solver.explore(start);
      final key = solver.layout.keyOf(start);
      expect(component.distance[key], solver.solve(start)!.moves);
      // Rastgele birkaç durumda da aynı.
      for (final state in component.states.take(40)) {
        final positions = solver.layout.positionsOf(state);
        expect(
          component.distance[state],
          solver.solve(positions)!.moves,
          reason: '$positions',
        );
      }
    });
  });
}
