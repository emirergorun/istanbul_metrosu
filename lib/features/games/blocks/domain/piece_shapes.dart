import 'block_piece.dart';
import 'cell.dart';

/// Parça kataloğu.
///
/// Çekirdek set `01 - MVP` notundan gelir: 1x1, 1x2, 1x3, 1x4, 2x1, 3x1,
/// 2x2, L-3, L-5, T-4, T-5. Döndürülmüş varyantlar ayrı şekil olarak
/// tutulur — runtime rotasyon yoktur, varyantlar hazır gelir.
///
/// **Arcade seti sonradan eklendi:** S/Z zikzakları, 2x3 ve 3x2
/// dikdörtgenler, 5'li çubuklar ve 3x3 kare. Sebep: eldeki set en fazla 5
/// hücreydi ve tek hamlede birden çok hat temizlemek neredeyse yalnızca
/// şansa kalıyordu. Büyük parçalar hem daha çok yer kaplar (risk) hem de
/// tek hamlede iki hattı birden tamamlayabilir (ödül) — oyunun "patlatma"
/// anları buradan çıkar.
///
/// 3x3 kare kataloğun en büyük parçasıdır: 9 hücre, tahtanın yedide biri.
/// Konacak yer bulmak ciddi bir karar, bulunca da genelde büyük bir
/// temizlik gelir.
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

  // S ve Z zikzakları, yatay ve dikey.
  static const BlockPiece s4 = BlockPiece(
    id: 's4',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 1), Cell(0, 2), Cell(1, 0), Cell(1, 1)],
  );
  static const BlockPiece z4 = BlockPiece(
    id: 'z4',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(1, 1), Cell(1, 2)],
  );
  static const BlockPiece s4Vertical = BlockPiece(
    id: 's4_v',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(2, 1)],
  );
  static const BlockPiece z4Vertical = BlockPiece(
    id: 'z4_v',
    difficulty: PieceDifficulty.medium,
    cells: <Cell>[Cell(0, 1), Cell(1, 0), Cell(1, 1), Cell(2, 0)],
  );

  // --- ZOR ---

  /// 2x3 dikdörtgen — tek hamlede iki satırı birden besler.
  static const BlockPiece rect23 = BlockPiece(
    id: 'rect23',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(1, 0),
      Cell(1, 1),
      Cell(1, 2),
    ],
  );

  /// 3x2 dikdörtgen — iki sütunu birden besler.
  static const BlockPiece rect32 = BlockPiece(
    id: 'rect32',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[
      Cell(0, 0),
      Cell(0, 1),
      Cell(1, 0),
      Cell(1, 1),
      Cell(2, 0),
      Cell(2, 1),
    ],
  );

  /// 1x5 çubuk — sekiz genişliğindeki tahtada satırın yarısından fazlası.
  static const BlockPiece h5 = BlockPiece(
    id: 'h5',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(0, 3), Cell(0, 4)],
  );

  /// 5x1 çubuk.
  static const BlockPiece v5 = BlockPiece(
    id: 'v5',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(3, 0), Cell(4, 0)],
  );

  /// 3x3 kare — kataloğun en büyük parçası, 9 hücre.
  ///
  /// Tahtanın yedide biri. Yer bulmak zor, bulunca üç satır ve üç sütunu
  /// birden besler: oyunun en büyük temizliklerinin çoğu bundan çıkar.
  static const BlockPiece square3 = BlockPiece(
    id: 'square3',
    difficulty: PieceDifficulty.hard,
    cells: <Cell>[
      Cell(0, 0),
      Cell(0, 1),
      Cell(0, 2),
      Cell(1, 0),
      Cell(1, 1),
      Cell(1, 2),
      Cell(2, 0),
      Cell(2, 1),
      Cell(2, 2),
    ],
  );

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
    s4,
    z4,
    s4Vertical,
    z4Vertical,
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
    rect23,
    rect32,
    h5,
    v5,
    square3,
  ];

  static const List<BlockPiece> all = <BlockPiece>[...easy, ...medium, ...hard];

  static final Map<String, BlockPiece> _byId = <String, BlockPiece>{
    for (final piece in all) piece.id: piece,
  };

  /// Kayıtlı oyunu geri yüklerken şekli id'sinden bulmak için.
  static BlockPiece? byId(String id) => _byId[id];

  static List<BlockPiece> pool(PieceDifficulty difficulty) =>
      switch (difficulty) {
        PieceDifficulty.easy => easy,
        PieceDifficulty.medium => medium,
        PieceDifficulty.hard => hard,
      };
}
