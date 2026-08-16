import 'package:flutter/foundation.dart';

import 'cell.dart';

/// Parça zorluk havuzu. Piece generator bu havuzlara göre ağırlıklandırır.
enum PieceDifficulty { easy, medium, hard }

/// Yerleştirilebilir blok parçası.
///
/// Hücreler *relative* koordinattır ve normalize edilmiştir
/// (en küçük satır ve en küçük sütun her zaman 0).
@immutable
class BlockPiece {
  const BlockPiece({
    required this.id,
    required this.cells,
    required this.difficulty,
    this.colorIndex = 0,
  });

  final String id;
  final List<Cell> cells;
  final PieceDifficulty difficulty;

  /// Palette içindeki renk indeksi. Generator tarafından atanır.
  final int colorIndex;

  int get size => cells.length;

  int get height {
    var max = 0;
    for (final cell in cells) {
      if (cell.row > max) max = cell.row;
    }
    return max + 1;
  }

  int get width {
    var max = 0;
    for (final cell in cells) {
      if (cell.col > max) max = cell.col;
    }
    return max + 1;
  }

  /// Şeklin geçerliliği: negatif koordinat yok, tekrar eden hücre yok,
  /// normalize edilmiş (0,0 kenarına yaslı).
  bool get isValidShape {
    if (cells.isEmpty) return false;
    final seen = <Cell>{};
    var minRow = 1 << 30;
    var minCol = 1 << 30;
    for (final cell in cells) {
      if (cell.row < 0 || cell.col < 0) return false;
      if (!seen.add(cell)) return false;
      if (cell.row < minRow) minRow = cell.row;
      if (cell.col < minCol) minCol = cell.col;
    }
    return minRow == 0 && minCol == 0;
  }

  BlockPiece withColor(int index) => BlockPiece(
    id: id,
    cells: cells,
    difficulty: difficulty,
    colorIndex: index,
  );

  /// Board üzerinde [row],[col] köşesine konulduğunda kaplayacağı hücreler.
  List<Cell> cellsAt(int row, int col) => <Cell>[
    for (final cell in cells) cell.translate(row, col),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockPiece && other.id == id && other.colorIndex == colorIndex);

  @override
  int get hashCode => Object.hash(id, colorIndex);

  @override
  String toString() => 'BlockPiece($id, ${width}x$height, ${difficulty.name})';
}
