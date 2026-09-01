import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/metro_tile.dart';

class MetroMergeController extends JourneyGameController {
  MetroMergeController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    Random? random,
    super.tick = AppConstants.playTick,
  }) : _random = random ?? Random(),
       config = MetroMergeConfig.fromDifficulty(journey.difficulty),
       super(gameId: id) {
    _resetBoard();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'metro_merge';

  final Random _random;
  final MetroMergeConfig config;
  late List<List<MetroTile?>> _grid;

  int _totalMerges = 0;
  int _totalClearedLines = 0;
  int _terminalClears = 0;

  List<List<MetroTile?>> get grid => _grid;
  int get totalMerges => _totalMerges;
  int get totalClearedLines => _totalClearedLines;
  int get terminalClears => _terminalClears;

  @visibleForTesting
  void debugSetGrid(List<List<MetroTile?>> grid) {
    assert(grid.length == config.gridSize);
    assert(grid.every((row) => row.length == config.gridSize));
    _grid = <List<MetroTile?>>[
      for (final row in grid) List<MetroTile?>.of(row),
    ];
    notifyListeners();
  }

  // --- Yolculuk motorunun kancaları ---

  @override
  void onRestart() {
    _totalMerges = 0;
    _totalClearedLines = 0;
    _terminalClears = 0;
    _resetBoard();
  }

  MetroMoveOutcome move(MetroMoveDirection direction) {
    if (status != GameStatus.playing) {
      return const MetroMoveOutcome.rejected();
    }

    final n = config.gridSize;
    final newGrid = List<List<MetroTile?>>.generate(
      n,
      (_) => List<MetroTile?>.filled(n, null),
    );
    var moved = false;
    var gained = 0;
    var merges = 0;
    var terminalClears = 0;

    for (var i = 0; i < n; i++) {
      final line = <_Cell>[];
      for (var j = 0; j < n; j++) {
        final (row, col) = switch (direction) {
          MetroMoveDirection.left => (i, j),
          MetroMoveDirection.right => (i, n - 1 - j),
          MetroMoveDirection.up => (j, i),
          MetroMoveDirection.down => (n - 1 - j, i),
        };
        line.add(_Cell(row, col, _grid[row][col]));
      }

      final filled = line.where((cell) => cell.tile != null).toList();
      var write = 0;
      for (var k = 0; k < filled.length; k++) {
        final current = filled[k];
        final next = k + 1 < filled.length ? filled[k + 1] : null;
        final merge = next == null
            ? null
            : _tryMerge(current.tile!, next.tile!);
        final target = line[write];

        if (merge != null) {
          newGrid[target.row][target.col] = merge.tile;
          gained += merge.points;
          merges++;
          if (merge.vanish) terminalClears++;
          moved = true;
          k++;
        } else {
          newGrid[target.row][target.col] = current.tile;
          if (target.row != current.row || target.col != current.col) {
            moved = true;
          }
        }
        write++;
      }
    }

    if (!moved) return const MetroMoveOutcome.rejected();

    _grid = newGrid;
    _spawnTile();
    final cleared = _clearFullLines();
    gained += cleared.cellCount * 15;

    final beatRecord = addScore(gained);
    _totalMerges += merges;
    _totalClearedLines += cleared.rows.length + cleared.columns.length;
    _terminalClears += terminalClears;
    if (merges > 0 || cleared.cellCount > 0) markStationProgress();

    _evaluateEndConditions();
    notifyListeners();

    return MetroMoveOutcome(
      accepted: true,
      gainedPoints: gained,
      clearedRows: cleared.rows,
      clearedColumns: cleared.columns,
      merges: merges,
      terminalClears: terminalClears,
      beatRecord: beatRecord,
    );
  }

  void _resetBoard() {
    _grid = List<List<MetroTile?>>.generate(
      config.gridSize,
      (_) => List<MetroTile?>.filled(config.gridSize, null),
    );
    _spawnTile();
    _spawnTile();
  }

  bool _spawnTile() {
    final empty = <(int, int)>[];
    for (var row = 0; row < config.gridSize; row++) {
      for (var col = 0; col < config.gridSize; col++) {
        if (_grid[row][col] == null) empty.add((row, col));
      }
    }
    if (empty.isEmpty) return false;
    final (row, col) = empty[_random.nextInt(empty.length)];
    _grid[row][col] = const MetroTile(colorIndex: 0, rank: 1);
    return true;
  }

  _MergeResult? _tryMerge(MetroTile a, MetroTile b) {
    if (a.rank != b.rank) return null;
    if (a.rank < metroMergeMaxRank) {
      return _MergeResult(
        tile: MetroTile(colorIndex: 0, rank: a.rank + 1),
        points: (a.rank + 1) * 20,
      );
    }
    return const _MergeResult(tile: null, points: 300, vanish: true);
  }

  _ClearResult _clearFullLines() {
    final n = config.gridSize;
    final rows = <int>[];
    final columns = <int>[];

    for (var row = 0; row < n; row++) {
      if (_grid[row].every((tile) => tile != null)) rows.add(row);
    }
    for (var col = 0; col < n; col++) {
      var full = true;
      for (var row = 0; row < n; row++) {
        if (_grid[row][col] == null) {
          full = false;
          break;
        }
      }
      if (full) columns.add(col);
    }

    if (rows.isEmpty && columns.isEmpty) {
      return const _ClearResult(rows: <int>[], columns: <int>[], cellCount: 0);
    }

    var cellCount = 0;
    for (final row in rows) {
      for (var col = 0; col < n; col++) {
        if (_grid[row][col] != null) cellCount++;
        _grid[row][col] = null;
      }
    }
    for (final col in columns) {
      for (var row = 0; row < n; row++) {
        if (rows.contains(row)) continue;
        if (_grid[row][col] != null) cellCount++;
        _grid[row][col] = null;
      }
    }

    return _ClearResult(rows: rows, columns: columns, cellCount: cellCount);
  }

  void _evaluateEndConditions() {
    if (_hasEmptyCell()) return;
    if (_hasAnyMerge()) return;
    endGame();
  }

  bool _hasEmptyCell() {
    for (final row in _grid) {
      if (row.any((tile) => tile == null)) return true;
    }
    return false;
  }

  bool _hasAnyMerge() {
    final n = config.gridSize;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final tile = _grid[row][col];
        if (tile == null) continue;
        if (col + 1 < n) {
          final right = _grid[row][col + 1];
          if (right != null && _tryMerge(tile, right) != null) return true;
        }
        if (row + 1 < n) {
          final down = _grid[row + 1][col];
          if (down != null && _tryMerge(tile, down) != null) return true;
        }
      }
    }
    return false;
  }
}

class _Cell {
  const _Cell(this.row, this.col, this.tile);

  final int row;
  final int col;
  final MetroTile? tile;
}

@immutable
class _MergeResult {
  const _MergeResult({
    required this.tile,
    required this.points,
    this.vanish = false,
  });

  final MetroTile? tile;
  final int points;
  final bool vanish;
}

@immutable
class _ClearResult {
  const _ClearResult({
    required this.rows,
    required this.columns,
    required this.cellCount,
  });

  final List<int> rows;
  final List<int> columns;
  final int cellCount;
}
