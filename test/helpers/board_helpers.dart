import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';

/// Testlerde okunabilir board kurmak için yardımcı.
///
/// `.` boş, diğer her karakter dolu kabul edilir.
///
/// ```dart
/// final board = boardFrom(<String>[
///   'XXXXXXX.',
///   '........',
/// ]);
/// ```
Board boardFrom(List<String> rows) {
  return Board.fromGrid(<List<int>>[
    for (final row in rows)
      <int>[for (final char in row.split('')) char == '.' ? kEmptyCell : 1],
  ]);
}

/// Tamamen dolu board.
Board fullBoard({int rows = 8, int cols = 8}) {
  return Board.fromGrid(
    List<List<int>>.generate(rows, (_) => List<int>.filled(cols, 1)),
  );
}
