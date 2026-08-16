import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import 'block_piece.dart';
import 'cell.dart';

/// Boş hücre değeri.
const int kEmptyCell = 0;

/// Oyun başında zorluk profiline göre konan engel hücresi.
/// Normal dolu hücre gibi davranır: satır/sütun temizliğinde silinebilir.
const int kBlockerCell = 9;

/// Immutable 8x8 (varsayılan) oyun tahtası.
///
/// Hücre değerleri: 0 = boş, 1..8 = blok rengi indeksi, 9 = engel.
/// UI bu sınıfı okur ama asla mutasyon yapmaz; tüm dönüşümler saf
/// fonksiyonlardan yeni bir [Board] döner.
@immutable
class Board {
  const Board._(this.rows, this.cols, this._cells);

  factory Board.empty({
    int rows = AppConstants.boardRows,
    int cols = AppConstants.boardCols,
  }) {
    return Board._(
      rows,
      cols,
      List<List<int>>.generate(
        rows,
        (_) => List<int>.filled(cols, kEmptyCell),
        growable: false,
      ),
    );
  }

  /// Test ve snapshot için: verilen grid'in derin kopyasıyla board üretir.
  factory Board.fromGrid(List<List<int>> grid) {
    assert(grid.isNotEmpty, 'Board grid boş olamaz');
    final rows = grid.length;
    final cols = grid.first.length;
    assert(
      grid.every((row) => row.length == cols),
      'Tüm satırlar aynı uzunlukta olmalı',
    );
    return Board._(
      rows,
      cols,
      List<List<int>>.generate(
        rows,
        (r) => List<int>.of(grid[r]),
        growable: false,
      ),
    );
  }

  final int rows;
  final int cols;
  final List<List<int>> _cells;

  int valueAt(int row, int col) => _cells[row][col];

  bool isEmptyAt(int row, int col) => _cells[row][col] == kEmptyCell;

  bool contains(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  int get filledCount {
    var count = 0;
    for (final row in _cells) {
      for (final value in row) {
        if (value != kEmptyCell) count++;
      }
    }
    return count;
  }

  int get cellCount => rows * cols;

  /// Derin kopya — dışarıya sızan referans mutasyonunu engeller.
  List<List<int>> toGrid() => <List<int>>[
    for (final row in _cells) List<int>.of(row),
  ];

  @override
  String toString() => _cells
      .map((r) => r.map((v) => v == kEmptyCell ? '.' : 'X').join())
      .join('\n');
}

/// Parça [piece], sol-üst köşesi ([row],[col]) olacak şekilde konabilir mi?
///
/// Kural: her hücre board içinde olmalı ve boş olmalı.
bool canPlace(Board board, BlockPiece piece, int row, int col) {
  for (final cell in piece.cells) {
    final r = row + cell.row;
    final c = col + cell.col;
    if (!board.contains(r, c)) return false;
    if (!board.isEmptyAt(r, c)) return false;
  }
  return true;
}

/// Parçayı yerleştirip **yeni** board döner.
///
/// [canPlace] false ise çağrılmamalıdır (debug'da assert atar,
/// release'de board'u değiştirmeden aynı içeriği döner).
Board placePiece(Board board, BlockPiece piece, int row, int col) {
  assert(
    canPlace(board, piece, row, col),
    'placePiece geçersiz konumla çağrıldı: ($row,$col) ${piece.id}',
  );
  if (!canPlace(board, piece, row, col)) return board;

  final grid = board.toGrid();
  final value = piece.colorIndex <= 0 ? 1 : piece.colorIndex;
  for (final cell in piece.cells) {
    grid[row + cell.row][col + cell.col] = value;
  }
  return Board.fromGrid(grid);
}

/// Tamamen dolu satırların indeksleri.
List<int> findCompletedRows(Board board) {
  final result = <int>[];
  for (var r = 0; r < board.rows; r++) {
    var full = true;
    for (var c = 0; c < board.cols; c++) {
      if (board.isEmptyAt(r, c)) {
        full = false;
        break;
      }
    }
    if (full) result.add(r);
  }
  return result;
}

/// Tamamen dolu sütunların indeksleri.
List<int> findCompletedColumns(Board board) {
  final result = <int>[];
  for (var c = 0; c < board.cols; c++) {
    var full = true;
    for (var r = 0; r < board.rows; r++) {
      if (board.isEmptyAt(r, c)) {
        full = false;
        break;
      }
    }
    if (full) result.add(c);
  }
  return result;
}

/// Verilen satır ve sütunları **aynı anda** temizler.
///
/// Kesişen hücreler iki kez sayılmaz; sadece bir kez boşaltılır.
Board clearLines(
  Board board, {
  List<int> rows = const [],
  List<int> columns = const [],
}) {
  if (rows.isEmpty && columns.isEmpty) return board;
  final grid = board.toGrid();
  for (final r in rows) {
    for (var c = 0; c < board.cols; c++) {
      grid[r][c] = kEmptyCell;
    }
  }
  for (final c in columns) {
    for (var r = 0; r < board.rows; r++) {
      grid[r][c] = kEmptyCell;
    }
  }
  return Board.fromGrid(grid);
}

/// Parça board üzerinde herhangi bir yere konabiliyor mu?
bool canPlaceAnywhere(Board board, BlockPiece piece) =>
    findFirstLegalPosition(board, piece) != null;

/// Parçanın konabileceği ilk konum (satır, sütun) — yoksa null.
Cell? findFirstLegalPosition(Board board, BlockPiece piece) {
  for (var r = 0; r <= board.rows - piece.height; r++) {
    for (var c = 0; c <= board.cols - piece.width; c++) {
      if (canPlace(board, piece, r, c)) return Cell(r, c);
    }
  }
  return null;
}

/// Elde kalan parçalardan en az biri konabiliyor mu?
///
/// `false` => game over.
bool hasAnyLegalMove(Board board, Iterable<BlockPiece?> pieces) {
  for (final piece in pieces) {
    if (piece == null) continue;
    if (canPlaceAnywhere(board, piece)) return true;
  }
  return false;
}
