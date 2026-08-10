import 'block_piece.dart';
import 'cell.dart';

/// MVP parça kataloğu.
///
/// `01 - MVP` notundaki set: 1x1, 1x2, 1x3, 1x4, 2x1, 3x1, 2x2, L-3, L-5, T-4, T-5.
/// Dikey karşılıkları (4x1 gibi) ve döndürülmüş varyantlar, oyunun adil
/// hissetmesi için ayrı şekiller olarak kataloğa eklenmiştir — MVP'de runtime
/// rotasyon yoktur, varyantlar hazır şekil olarak gelir.
class PieceShapes {
  const PieceShapes._();

  // --- KOLAY ---
  static const BlockPiece dot = BlockPiece(
    id: 'dot',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0)],
  );

  static const BlockPiece h2 = BlockPiece(
    id: 'h2',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0), Cell(0, 1)],
  );

  static const BlockPiece v2 = BlockPiece(
    id: 'v2',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0), Cell(1, 0)],
  );

  static const BlockPiece h3 = BlockPiece(
    id: 'h3',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2)],
  );

  static const BlockPiece v3 = BlockPiece(
    id: 'v3',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(2, 0)],
  );

  static const BlockPiece square2 = BlockPiece(
    id: 'square2',
    difficulty: PieceDifficulty.easy,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(1, 0), Cell(1, 1)],
  );

  // --- ORTA ---
  static const BlockPiece h4 = BlockPiece(
    id: 'h4',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(0, 3)],
  );

  static const BlockPiece v4 = BlockPiece(
    id: 'v4',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(3, 0)],
  );

  // L-3, dört yön.
  static const BlockPiece l3a = BlockPiece(
    id: 'l3a',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(1, 1)],
  );
  static const BlockPiece l3b = BlockPiece(
    id: 'l3b',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(1, 0)],
  );
  static const BlockPiece l3c = BlockPiece(
    id: 'l3c',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(1, 1)],
  );
  static const BlockPiece l3d = BlockPiece(
    id: 'l3d',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 1), Cell(1, 0), Cell(1, 1)],
  );

  // T-4, dört yön.
  static const BlockPiece t4Down = BlockPiece(
    id: 't4_down',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 1)],
  );
  static const BlockPiece t4Up = BlockPiece(
    id: 't4_up',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 1), Cell(1, 0), Cell(1, 1), Cell(1, 2)],
  );
  static const BlockPiece t4Left = BlockPiece(
    id: 't4_left',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 1), Cell(1, 0), Cell(1, 1), Cell(2, 1)],
  );
  static const BlockPiece t4Right = BlockPiece(
    id: 't4_right',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(2, 0)],
  );

  // --- ZOR ---
  // L-5 (3x3 köşe), dört yön.
  static const BlockPiece l5a = BlockPiece(
    id: 'l5a',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(2, 1), Cell(2, 2)],
  );
  static const BlockPiece l5b = BlockPiece(
    id: 'l5b',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 0), Cell(2, 0)],
  );
  static const BlockPiece l5c = BlockPiece(
    id: 'l5c',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 2), Cell(2, 2)],
  );
  static const BlockPiece l5d = BlockPiece(
    id: 'l5d',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 2), Cell(1, 2), Cell(2, 0), Cell(2, 1), Cell(2, 2)],
  );

  // T-5 (uzun saplı T), dört yön.
  static const BlockPiece t5Down = BlockPiece(
    id: 't5_down',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 1), Cell(2, 1)],
  );
  static const BlockPiece t5Up = BlockPiece(
    id: 't5_up',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 1), Cell(1, 1), Cell(2, 0), Cell(2, 1), Cell(2, 2)],
  );
  static const BlockPiece t5Left = BlockPiece(
    id: 't5_left',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 2), Cell(1, 0), Cell(1, 1), Cell(1, 2), Cell(2, 2)],
  );
  static const BlockPiece t5Right = BlockPiece(
    id: 't5_right',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(1, 2), Cell(2, 0)],
  );

  static const List<BlockPiece> easy = <BlockPiece>[
    dot,
    h2,
    v2,
    h3,
    v3,
    square2,
  ];

  static const List<BlockPiece> medium = <BlockPiece>[
    h4,
    v4,
    l3a,
    l3b,
    l3c,
    l3d,
    t4Down,
    t4Up,
    t4Left,
    t4Right,
  ];

  static const List<BlockPiece> hard = <BlockPiece>[
    l5a,
    l5b,
    l5c,
    l5d,
    t5Down,
    t5Up,
    t5Left,
    t5Right,
  ];

  static const List<BlockPiece> all = <BlockPiece>[...easy, ...medium, ...hard];

  static List<BlockPiece> pool(PieceDifficulty difficulty) =>
      switch (difficulty) {
        PieceDifficulty.easy => easy,
        PieceDifficulty.medium => medium,
        PieceDifficulty.hard => hard,
      };
}
