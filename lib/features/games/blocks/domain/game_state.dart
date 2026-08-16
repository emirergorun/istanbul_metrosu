import 'package:flutter/foundation.dart';

import '../../../journey/models/journey.dart';
import '../../../session/journey_status.dart';
import 'block_piece.dart';
import 'board.dart';
import 'scoring.dart';

// Oyun kodu GameStatus'u bu dosyadan almaya devam edebilsin diye
// yeniden dışa aktarılıyor; tanım paylaşılan katmanda.
export '../../../session/journey_status.dart';

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
    required this.recordToBeat,
    required this.recordBeaten,
    required this.stationsPassed,
    required this.placedPieces,
  });

  factory GameSession.initial({
    required Journey journey,
    required Board board,
    required List<BlockPiece?> tray,
    int recordToBeat = 0,
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
      recordToBeat: recordToBeat,
      recordBeaten: false,
      stationsPassed: 0,
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

  /// Bu rotadaki mevcut rekor. 0 ise rotada ilk yolculuk.
  final int recordToBeat;

  /// Rekor bu oturumda geçildi mi?
  final bool recordBeaten;

  /// Tren kaç durağı geçti — durak bonusu bundan tetiklenir.
  final int stationsPassed;

  final int placedPieces;

  /// Rotada daha önce oynanmadıysa kıyaslanacak bir rekor yok.
  bool get isFirstRun => recordToBeat <= 0;

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

  /// Rekora göre tamamlanma oranı 0.0 - 1.0.
  double get recordProgress {
    if (isFirstRun) return 0;
    final value = score / recordToBeat;
    return value > 1 ? 1 : value;
  }

  /// Yolculuğun son dilimi: puanlar iki katı.
  bool get isSprint => progress >= ScoreRules.sprintStartsAt;

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
    bool? recordBeaten,
    int? stationsPassed,
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
      recordToBeat: recordToBeat,
      recordBeaten: recordBeaten ?? this.recordBeaten,
      stationsPassed: stationsPassed ?? this.stationsPassed,
      placedPieces: placedPieces ?? this.placedPieces,
    );
  }
}
