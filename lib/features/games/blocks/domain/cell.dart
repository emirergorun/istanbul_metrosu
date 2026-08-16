import 'package:flutter/foundation.dart';

/// Grid üzerinde bir hücre koordinatı (satır, sütun).
///
/// Hem board koordinatı hem de piece'in *relative* hücreleri için kullanılır.
@immutable
class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  Cell operator +(Cell other) => Cell(row + other.row, col + other.col);
  Cell translate(int dRow, int dCol) => Cell(row + dRow, col + dCol);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Cell && other.row == row && other.col == col);

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '($row,$col)';
}
