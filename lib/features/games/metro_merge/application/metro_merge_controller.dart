import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/metro_tile.dart';

/// Hat Birleştir — kuralları **birebir 2048**.
///
/// 2048'in kuralları ve buradaki karşılıkları:
///  1. 4x4 tahta, başta iki karo.                     → [metroMergeGridSize]
///  2. Kaydırma: tüm karolar o yöne dayanır.          → [_collapse]
///  3. Aynı değerdeki iki karo birleşir, **bir hamlede bir kez**.
///  4. Birleşen karonun değeri kadar puan yazılır.    → [MetroTile.value]
///  5. Tahta değiştiyse bir yeni karo doğar: %90 M1, %10 M2.
///  6. Boş hücre yoksa **ve** komşu eş karo yoksa oyun biter.
///
/// Eskiden buraya 2048'e ait olmayan bir "dolu satır/sütun silinir"
/// mekaniği eklenmişti; oyunu bozan asıl sebep oydu. 4x4'te bir duvara
/// dayanan dört karo zaten "dolu sütun" demek, yani mekanik neredeyse her
/// hamlede tetikleniyordu. Ölçümde 22 hamlede tahta tamamen boşaldı ve oyun
/// kilitlendi: boş tahtada hiçbir kaydırma bir şeyi değiştirmediği için
/// hamle reddediliyor, yeni karo doğmuyor, oyun ne ilerliyor ne bitiyordu.
/// Ayrıca en üst hatta birleşen karolar yok oluyordu; 2048'de böyle bir
/// kural da yok.
class MetroMergeController extends JourneyGameController {
  MetroMergeController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    super.discovery,
    Random? random,
    super.tick = AppConstants.playTick,
    super.session,
  }) : _random = random ?? Random(),
       super(gameId: id) {
    _resetBoard();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'metro_merge';

  /// 2048'de yeni karo %90 "2", %10 "4" gelir.
  static const double _fourChance = 0.1;

  final Random _random;
  final MetroMergeConfig config = const MetroMergeConfig();
  late List<List<MetroTile?>> _grid;

  int _totalMerges = 0;
  int _highestRank = 1;
  bool _reachedTarget = false;

  List<List<MetroTile?>> get grid => _grid;
  int get totalMerges => _totalMerges;

  /// Tahtada ulaşılan en yüksek hat.
  int get highestRank => _highestRank;

  String get highestLabel =>
      metroMergeLineLabels[(_highestRank - 1).clamp(
        0,
        metroMergeLineLabels.length - 1,
      )];

  /// M11'e (2048) ulaşıldı mı? 2048'de olduğu gibi oyun burada **bitmez**.
  bool get reachedTarget => _reachedTarget;

  @visibleForTesting
  void debugSetGrid(List<List<MetroTile?>> grid) {
    assert(grid.length == config.gridSize);
    assert(grid.every((row) => row.length == config.gridSize));
    _grid = <List<MetroTile?>>[
      for (final row in grid) List<MetroTile?>.of(row),
    ];
    _highestRank = _computeHighestRank();
    notifyListeners();
  }

  @override
  void onRestart() {
    _totalMerges = 0;
    _highestRank = 1;
    _reachedTarget = false;
    _resetBoard();
  }

  MetroMoveOutcome move(MetroMoveDirection direction) {
    if (status != GameStatus.playing) {
      return const MetroMoveOutcome.rejected();
    }

    final n = config.gridSize;
    final next = List<List<MetroTile?>>.generate(
      n,
      (_) => List<MetroTile?>.filled(n, null),
    );
    var moved = false;
    var gained = 0;
    var merges = 0;

    for (var i = 0; i < n; i++) {
      // Satırı/sütunu hareket yönüne doğru sırala: ilk eleman, karoların
      // dayanacağı duvara en yakın olan. Böylece dört yön için tek bir
      // sıkıştırma algoritması yetiyor.
      final cells = <(int, int)>[
        for (var j = 0; j < n; j++)
          switch (direction) {
            MetroMoveDirection.left => (i, j),
            MetroMoveDirection.right => (i, n - 1 - j),
            MetroMoveDirection.up => (j, i),
            MetroMoveDirection.down => (n - 1 - j, i),
          },
      ];

      final source = <MetroTile>[
        for (final (row, col) in cells)
          if (_grid[row][col] != null) _grid[row][col]!,
      ];
      final collapsed = _collapse(source);

      for (var j = 0; j < n; j++) {
        final (row, col) = cells[j];
        final tile = j < collapsed.tiles.length ? collapsed.tiles[j] : null;
        next[row][col] = tile;
        if (tile?.rank != _grid[row][col]?.rank) moved = true;
      }
      gained += collapsed.points;
      merges += collapsed.merges;
    }

    // 2048: tahtayı değiştirmeyen kaydırma hamle sayılmaz.
    if (!moved) return const MetroMoveOutcome.rejected();

    _grid = next;
    _spawnTile();

    final previousHighest = _highestRank;
    _highestRank = _computeHighestRank();
    final justReachedTarget =
        !_reachedTarget && _highestRank >= metroMergeMaxRank;
    if (justReachedTarget) _reachedTarget = true;

    final beatRecord = addScore(gained);
    _totalMerges += merges;
    if (merges > 0) markStationProgress();

    _evaluateEndConditions();
    notifyListeners();

    return MetroMoveOutcome(
      accepted: true,
      gainedPoints: gained,
      merges: merges,
      highestRank: max(previousHighest, _highestRank),
      reachedTarget: justReachedTarget,
      beatRecord: beatRecord,
    );
  }

  /// Bir satırı/sütunu 2048 kurallarıyla sıkıştırır.
  ///
  /// Kritik kural: **bir hamlede birleşen karo tekrar birleşemez.** Bu yüzden
  /// eşleşme bulununca sıradaki karo atlanır (k += 2). Örnek:
  /// [M1 M1 M1 M1] soldan kaydırılınca [M2 M2] olur, [M3] olmaz.
  _Collapsed _collapse(List<MetroTile> source) {
    final tiles = <MetroTile>[];
    var points = 0;
    var merges = 0;

    var k = 0;
    while (k < source.length) {
      final current = source[k];
      final next = k + 1 < source.length ? source[k + 1] : null;
      if (next != null && _canMerge(current, next)) {
        final merged = MetroTile(rank: current.rank + 1);
        tiles.add(merged);
        // 2048'de puan, oluşan karonun değeri kadardır (iki "2" birleşince
        // +4 yazılır).
        points += merged.value;
        merges++;
        k += 2;
      } else {
        tiles.add(current);
        k++;
      }
    }

    return _Collapsed(tiles: tiles, points: points, merges: merges);
  }

  /// Aynı hat mı ve tavana ulaşılmamış mı?
  bool _canMerge(MetroTile a, MetroTile b) =>
      a.rank == b.rank && a.rank < metroMergeMaxRank;

  void _resetBoard() {
    _grid = List<List<MetroTile?>>.generate(
      config.gridSize,
      (_) => List<MetroTile?>.filled(config.gridSize, null),
    );
    _spawnTile();
    _spawnTile();
    _highestRank = _computeHighestRank();
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
    _grid[row][col] = MetroTile(
      rank: _random.nextDouble() < _fourChance ? 2 : 1,
    );
    return true;
  }

  int _computeHighestRank() {
    var best = 1;
    for (final row in _grid) {
      for (final tile in row) {
        if (tile != null && tile.rank > best) best = tile.rank;
      }
    }
    return best;
  }

  /// 2048'in bitiş koşulu: boş hücre yok **ve** birleşebilecek komşu yok.
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
          if (right != null && _canMerge(tile, right)) return true;
        }
        if (row + 1 < n) {
          final down = _grid[row + 1][col];
          if (down != null && _canMerge(tile, down)) return true;
        }
      }
    }
    return false;
  }
}

@immutable
class _Collapsed {
  const _Collapsed({
    required this.tiles,
    required this.points,
    required this.merges,
  });

  final List<MetroTile> tiles;
  final int points;
  final int merges;
}
