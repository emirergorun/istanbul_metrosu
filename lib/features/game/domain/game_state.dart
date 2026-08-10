import 'package:flutter/foundation.dart';

import '../../journey/models/journey.dart';
import 'block_piece.dart';
import 'board.dart';

/// Oyun oturumunun durumu.
///
/// `02 - Oyun Tasarımı` notundaki state listesine ek olarak [arrived]
/// eklenmiştir: yolculuk süresi dolduğunda oyun biter ve sonuç ekranı
/// açılır ("Trip Complete / Result"). [victory] ise hedef skora
/// yolculuk bitmeden ulaşıldığı durumdur.
enum GameStatus {
  setup,
  ready,
  playing,
  paused,
  victory,
  arrived,
  gameOver,
  abandoned,
}

extension GameStatusX on GameStatus {
  bool get isFinished =>
      this == GameStatus.victory ||
      this == GameStatus.arrived ||
      this == GameStatus.gameOver;

  bool get isActive => this == GameStatus.playing;
}

/// Tek bir oyun oturumunun tam anlık görüntüsü.
///
/// Immutable — undo, snapshot ve test bu sayede kolaydır.
@immutable
class GameSession {
  const GameSession({
    required this.journey,
    required this.board,
    required this.tray,
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.clearedRows,
    required this.clearedColumns,
    required this.elapsedSeconds,
    required this.status,
    required this.undoLeft,
    required this.targetReached,
    required this.placedPieces,
  });

  factory GameSession.initial({
    required Journey journey,
    required Board board,
    required List<BlockPiece?> tray,
  }) {
    return GameSession(
      journey: journey,
      board: board,
      tray: List<BlockPiece?>.unmodifiable(tray),
      score: 0,
      combo: 0,
      bestCombo: 0,
      clearedRows: 0,
      clearedColumns: 0,
      elapsedSeconds: 0,
      status: GameStatus.ready,
      undoLeft: journey.difficulty.undoCount,
      targetReached: false,
      placedPieces: 0,
    );
  }

  final Journey journey;
  final Board board;

  /// Tepside kalan parçalar; kullanılan slot `null` olur.
  final List<BlockPiece?> tray;

  final int score;
  final int combo;
  final int bestCombo;
  final int clearedRows;
  final int clearedColumns;

  /// Sadece **aktif oyun süresi**. Uygulama arka plandayken artmaz.
  final int elapsedSeconds;

  final GameStatus status;
  final int undoLeft;

  /// Hedef skora ulaşıldı mı (endless devam edilse bile true kalır).
  final bool targetReached;

  final int placedPieces;

  int get targetScore => journey.difficulty.targetScore;

  int get totalClearedLines => clearedRows + clearedColumns;

  /// Yolculuk ilerlemesi 0.0 - 1.0.
  double get progress {
    final total = journey.estimatedSeconds;
    if (total <= 0) return 1;
    final value = elapsedSeconds / total;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  int get remainingSeconds {
    final left = journey.estimatedSeconds - elapsedSeconds;
    return left < 0 ? 0 : left;
  }

  /// Hedefe göre tamamlanma oranı 0.0 - 1.0.
  double get targetProgress {
    if (targetScore <= 0) return 1;
    final value = score / targetScore;
    return value > 1 ? 1 : value;
  }

  bool get trayIsEmpty => tray.every((piece) => piece == null);

  GameSession copyWith({
    Board? board,
    List<BlockPiece?>? tray,
    int? score,
    int? combo,
    int? bestCombo,
    int? clearedRows,
    int? clearedColumns,
    int? elapsedSeconds,
    GameStatus? status,
    int? undoLeft,
    bool? targetReached,
    int? placedPieces,
  }) {
    return GameSession(
      journey: journey,
      board: board ?? this.board,
      tray: tray == null ? this.tray : List<BlockPiece?>.unmodifiable(tray),
      score: score ?? this.score,
      combo: combo ?? this.combo,
      bestCombo: bestCombo ?? this.bestCombo,
      clearedRows: clearedRows ?? this.clearedRows,
      clearedColumns: clearedColumns ?? this.clearedColumns,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      status: status ?? this.status,
      undoLeft: undoLeft ?? this.undoLeft,
      targetReached: targetReached ?? this.targetReached,
      placedPieces: placedPieces ?? this.placedPieces,
    );
  }
}
