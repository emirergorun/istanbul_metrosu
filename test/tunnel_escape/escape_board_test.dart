import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_board.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_piece.dart';

/// Izgaradan tahta kurar; metro sırası harf sırasıdır (R her zaman ilk).
EscapeBoard boardOf(List<String> grid) {
  final (layout, start) = EscapeLevel.parseGrid(grid);
  return EscapeBoard(layout, start);
}

int indexOf(EscapeBoard board, String id) =>
    board.layout.pieces.indexWhere((EscapePiece p) => p.id == id);

void main() {
  group('Izgara ayrıştırma', () {
    test('eksen, uzunluk ve şerit ızgaradan çıkarılır', () {
      final board = boardOf(<String>[
        '......',
        '..A...',
        'RRA...',
        '..A...',
        'BB....',
        '......',
      ]);
      final layout = board.layout;
      final r = layout.pieces[indexOf(board, 'R')];
      final a = layout.pieces[indexOf(board, 'A')];
      final b = layout.pieces[indexOf(board, 'B')];

      expect(r.isTarget, isTrue);
      expect(r.axis, EscapeAxis.horizontal);
      expect(r.length, 2);
      expect(r.lane, 2);

      expect(a.axis, EscapeAxis.vertical);
      expect(a.length, 3);
      expect(a.lane, 2);
      expect(board.positions[indexOf(board, 'A')], 1);

      expect(b.axis, EscapeAxis.horizontal);
      expect(b.length, 2);
      expect(b.lane, 4);
      expect(layout.exitRow, 2);
      expect(layout.exitPosition, 4);
    });

    test('hedef her zaman ilk metro, diğerleri harf sırasıyla', () {
      final board = boardOf(<String>[
        'C.....',
        'C.....',
        '..RR..',
        '...B..',
        '...B..',
        'AA....',
      ]);
      expect(
        board.layout.pieces.map((EscapePiece p) => p.id).toList(),
        <String>['R', 'A', 'B', 'C'],
      );
    });

    test('geçersiz ızgaralar reddedilir', () {
      expect(
        () => EscapeLevel.parseGrid(<String>['......', '..A...', '......']),
        throwsFormatException,
        reason: 'hedef yok',
      );
      expect(
        () => EscapeLevel.parseGrid(<String>['RR.A..', '...A..', '..AA..']),
        throwsFormatException,
        reason: 'A düz değil',
      );
      expect(
        () => EscapeLevel.parseGrid(<String>['RR....', 'AAAA..', '......']),
        throwsFormatException,
        reason: '4 hücrelik metro',
      );
      expect(
        () => EscapeLevel.parseGrid(<String>['RR.R..', '......', '......']),
        throwsFormatException,
        reason: 'bitişik olmayan hücreler',
      );
      expect(
        () => EscapeLevel.parseGrid(<String>['R.....', 'R.....', '......']),
        throwsArgumentError,
        reason: 'dikey hedef: tünel sağda',
      );
    });

    test('ızgara geri yazılınca aynısı çıkar', () {
      const grid = <String>[
        '..ABBB',
        '..A...',
        'RRA..C',
        '.....C',
        'DD....',
        '....EE',
      ];
      final (layout, start) = EscapeLevel.parseGrid(grid);
      expect(EscapeLevel.render(layout, start), grid);
    });
  });

  group('Hareket', () {
    final board = boardOf(<String>[
      '......',
      '....A.',
      'RR..A.',
      '......',
      '.BBB..',
      '......',
    ]);
    final r = indexOf(board, 'R');
    final a = indexOf(board, 'A');
    final b = indexOf(board, 'B');

    test('yatay metro yalnız kendi satırında kayar', () {
      // R: solda duvar, sağda A (sütun 4). En sağ konum 2.
      expect(board.rangeOf(r), (0, 2));
      final moved = board.moved(r, 2);
      expect(moved.positions[r], 2);
      // Satırı değişmedi: şerit sabit.
      expect(moved.layout.pieces[r].lane, 2);
    });

    test('dikey metro yalnız kendi sütununda kayar', () {
      // A: yukarıda duvar (satır 0), aşağıda B yok (sütun 4 boş) → 4'e kadar.
      expect(board.rangeOf(a), (0, 4));
      expect(board.moved(a, 0).positions[a], 0);
      expect(board.moved(a, 4).positions[a], 4);
    });

    test('3 hücrelik metro sınırlarını doğru hesaplar', () {
      // B satır 4, sütun 1-3; genişlik 6 → en sağ konum 3.
      expect(board.rangeOf(b), (0, 3));
    });

    test('metro başka metronun içine giremez', () {
      final blocked = board.moved(a, 3); // A satır 3-4, sütun 4
      // B artık sağa gidemez: sütun 4 satır 4'te A var.
      expect(blocked.rangeOf(b), (0, 1));
      expect(blocked.canMove(b, 2), isFalse);
      expect(() => blocked.moved(b, 3), throwsStateError);
    });

    test('metro başka metronun üstünden atlayamaz', () {
      // R sağa giderken A'yı atlayıp 4'e varamaz.
      expect(board.canMove(r, 4), isFalse);
      expect(() => board.moved(r, 4), throwsStateError);
    });

    test('tahta dışına çıkılamaz', () {
      expect(board.canMove(a, -1), isFalse);
      expect(board.canMove(b, 4), isFalse);
      expect(
        () => EscapeBoard(board.layout, <int>[0, 5, 1]),
        throwsArgumentError,
      );
    });

    test('hamle yeni tahta üretir, eskisi değişmez', () {
      final moved = board.moved(r, 1);
      expect(board.positions[r], 0);
      expect(moved.positions[r], 1);
      expect(identical(board, moved), isFalse);
    });

    test('hücre sorgusu doğru metroyu verir', () {
      expect(board.pieceAt(2, 0), r);
      expect(board.pieceAt(2, 4), a);
      expect(board.pieceAt(4, 3), b);
      expect(board.pieceAt(0, 0), isNull);
      expect(board.pieceAt(-1, 0), isNull);
      expect(board.pieceAt(0, 6), isNull);
    });
  });

  group('Tünel', () {
    test('hedef tünel ağzına varınca bölüm çözülmüş olur', () {
      final board = boardOf(<String>[
        '......',
        '......',
        'RR....',
        '......',
        '......',
        '......',
      ]);
      expect(board.isSolved, isFalse);
      expect(board.isTargetPathClear, isTrue);
      final solved = board.moved(0, 4);
      expect(solved.isSolved, isTrue);
    });

    test('önü kapalı hedefin yolu açık sayılmaz', () {
      final board = boardOf(<String>[
        '......',
        '......',
        'RR..A.',
        '....A.',
        '......',
        '......',
      ]);
      expect(board.isTargetPathClear, isFalse);
      expect(board.moved(1, 3).isTargetPathClear, isTrue);
    });
  });

  group('Kanonik anahtar', () {
    test('aynı diziliş aynı anahtar, farklı diziliş farklı anahtar', () {
      final board = boardOf(<String>[
        '......',
        '....A.',
        'RR..A.',
        '......',
        '.BBB..',
        '......',
      ]);
      final layout = board.layout;
      final a = board.moved(0, 1).moved(0, 0);
      expect(a.key, board.key);
      expect(a, board);

      final keys = <int>{};
      for (var r = 0; r <= 2; r++) {
        for (var p = 0; p <= 4; p++) {
          keys.add(layout.keyOf(<int>[r, p, 1]));
        }
      }
      expect(keys.length, 15);
    });

    test('anahtar konumlara geri açılır', () {
      final board = boardOf(<String>[
        '..ABBB',
        '..A...',
        'RRA..C',
        '.....C',
        'DD....',
        '....EE',
      ]);
      final layout = board.layout;
      expect(layout.positionsOf(board.key), board.positions);
      final changed = layout.keyWith(board.key, 3, 1);
      expect(layout.positionIn(changed, 3), 1);
      for (var i = 0; i < layout.pieceCount; i++) {
        if (i == 3) continue;
        expect(layout.positionIn(changed, i), board.positions[i]);
      }
    });

    test('başlangıç dizilişinde üst üste binme yok', () {
      final board = boardOf(<String>[
        '......',
        '....A.',
        'RR..A.',
        '......',
        '.BBB..',
        '......',
      ]);
      expect(board.isValid, isTrue);
      // Elle kurulmuş çakışan diziliş geçersiz sayılır.
      expect(EscapeBoard(board.layout, <int>[3, 1, 1]).isValid, isFalse);
    });
  });
}
