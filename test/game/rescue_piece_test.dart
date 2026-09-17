import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/piece_generator.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/block_piece.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';

/// Kurtarıcı parça: az kalmış bir hat varken tepsinin onu kapatabilen
/// parçayı vermesi.
///
/// Bilinçli bir kayırma. Tek başına rastgelelik oyuncunun kurduğu planı
/// çoğu zaman ödüllendirmiyor: satırı üç hücreye kadar getirip sonra işe
/// yaramaz üç parça alan oyuncu kendi hatasından değil şanssızlıktan
/// kaybediyor.
///
/// İki sınır korunuyor: kapanmaya yakın hat yokken mekanizma hiç
/// çalışmamalı, çalıştığında da hattı gerçekten kapatabilen bir tepsi
/// gelmeli.
void main() {
  /// Alt satırın yalnızca soldaki [gap] hücresi boş; gerisi dolu.
  Board boardWithGap(int gap) {
    final grid = List<List<int>>.generate(
      8,
      (_) => List<int>.filled(8, kEmptyCell),
    );
    for (var c = gap; c < 8; c++) {
      grid[7][c] = 1;
    }
    return Board.fromGrid(grid);
  }

  DifficultyProfile profile({int candidates = 1}) => DifficultyProfile(
    id: 'test',
    label: 'Test',
    minMinutes: 0,
    maxMinutes: null,
    initialBlockerRatio: 0,
    hardPieceWeight: 0.12,
    undoCount: 1,
    trayCandidates: candidates,
  );

  /// Tepsideki parçalardan biri tek hamlede bir hat kapatabiliyor mu?
  bool canClear(Board board, List<BlockPiece> tray) {
    for (final piece in tray) {
      for (var r = 0; r <= board.rows - piece.height; r++) {
        for (var c = 0; c <= board.cols - piece.width; c++) {
          if (!canPlace(board, piece, r, c)) continue;
          final placed = placePiece(board, piece, r, c);
          if (findCompletedRows(placed).isNotEmpty ||
              findCompletedColumns(placed).isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }

  group('hasNearCompleteLine', () {
    test('boş tahtada kapanmaya yakın hat yok', () {
      expect(hasNearCompleteLine(Board.empty()), isFalse);
    });

    test('üç hücresi boş satır yakın sayılır', () {
      expect(hasNearCompleteLine(boardWithGap(3)), isTrue);
    });

    test('dört hücresi boş satır yakın sayılmaz', () {
      expect(
        hasNearCompleteLine(boardWithGap(4), maxGap: 3),
        isFalse,
        reason: 'üçten fazlası artık "az kalmış" değil',
      );
    });

    test('tamamen dolu hat sayılmaz', () {
      // Dolu hat zaten temizlenmiştir; kurtarılacak bir şey yok.
      final full = Board.fromGrid(
        List<List<int>>.generate(8, (_) => List<int>.filled(8, 1)),
      );
      expect(hasNearCompleteLine(full), isFalse);
    });

    test('sütun da sayılır', () {
      final grid = List<List<int>>.generate(
        8,
        (_) => List<int>.filled(8, kEmptyCell),
      );
      for (var r = 2; r < 8; r++) {
        grid[r][0] = 1;
      }
      expect(hasNearCompleteLine(Board.fromGrid(grid)), isTrue);
    });

    test('eşik ayarlanabilir', () {
      expect(hasNearCompleteLine(boardWithGap(5), maxGap: 5), isTrue);
      expect(hasNearCompleteLine(boardWithGap(5), maxGap: 3), isFalse);
    });
  });

  group('tepsi üretimi', () {
    test('az kalmış hat varken çoğu tepsi hattı kapatabiliyor', () {
      final board = boardWithGap(3);

      var clearing = 0;
      const rounds = 60;
      for (var seed = 0; seed < rounds; seed++) {
        final tray = PieceGenerator(
          random: Random(seed),
        ).generateTray(board, profile());
        if (canClear(board, tray)) clearing++;
      }

      // Kurtarma olasılığı %70; küçük bir örneklemde dalgalanır ama
      // yarısının belirgin üstünde olmalı.
      expect(
        clearing / rounds,
        greaterThan(0.5),
        reason: 'kurtarıcı parça belirgin şekilde sık gelmeli',
      );
    });

    test('her seferinde gelmez', () {
      // Sürekli verilseydi oyuncu kalıbı birkaç turda çözer, patlatma
      // sıradanlaşır ve gerilim biterdi.
      final board = boardWithGap(3);

      var missing = 0;
      for (var seed = 0; seed < 60; seed++) {
        final tray = PieceGenerator(
          random: Random(seed),
        ).generateTray(board, profile());
        if (!canClear(board, tray)) missing++;
      }

      expect(missing, greaterThan(0), reason: 'kalıp öngörülebilir olmamalı');
    });

    test('kapanmaya yakın hat yokken rastgelelik bozulmaz', () {
      // Boş tahtada kurtarma devreye girmez: tek adaylı ve çok adaylı
      // üretici aynı tohumla aynı tepsiyi vermeli.
      const board = Board.empty;
      final single = PieceGenerator(random: Random(5));
      final many = PieceGenerator(random: Random(5));

      expect(
        many.generateTray(board(), profile(candidates: 8)).map((p) => p.id),
        single.generateTray(board(), profile()).map((p) => p.id),
      );
    });

    test('kurtarma fairness kuralını bozmaz', () {
      final board = boardWithGap(2);
      for (var seed = 0; seed < 40; seed++) {
        final tray = PieceGenerator(
          random: Random(seed),
        ).generateTray(board, profile());
        expect(hasAnyLegalMove(board, tray), isTrue, reason: 'seed $seed');
      }
    });

    test('olasılık ve eşik sabitleri tek yerde', () {
      expect(PieceGenerator.rescueChance, inInclusiveRange(0.0, 1.0));
      expect(PieceGenerator.nearCompleteGap, greaterThan(0));
      expect(PieceGenerator.rescueCandidates, greaterThan(1));
    });
  });
}
