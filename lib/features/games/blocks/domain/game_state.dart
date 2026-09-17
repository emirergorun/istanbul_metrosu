import 'package:flutter/foundation.dart';

import '../../../journey/models/journey.dart';
import 'block_piece.dart';
import 'board.dart';
import 'combo.dart';
import 'streak.dart';

// Oyun kodu GameStatus'u bu dosyadan almaya devam edebilsin diye
// yeniden dışa aktarılıyor; tanım paylaşılan katmanda.
export '../../../session/journey_status.dart';

/// Blok oyununun **tahta durumu**.
///
/// Burada yalnızca oyuna özgü şeyler var: tahta, tepsi, combo, seri ve
/// sayaçlar. Skor, geçen süre, rekor ve durak sayısı **motorun**
/// ([JourneyGameController]) işi; altı oyun onları aynı yerden yönetiyor.
///
/// Ayrım bu sınıfın tek işini netleştirir: geri alma bu nesneyi eski hâline
/// döndürür, motor da kendi sayaçlarını geri sarar. Eskiden ikisi aynı
/// nesnedeydi ve blok oyunu motoru hiç kullanmıyordu; sayaç, varış tespiti,
/// durak bonusu ve rekor kaydı iki ayrı yerde yazılıydı.
///
/// Immutable — undo, snapshot ve test bu sayede kolaydır.
@immutable
class GameSession {
  const GameSession({
    required this.journey,
    required this.board,
    required this.tray,
    required this.comboState,
    required this.streakState,
    required this.clearedRows,
    required this.clearedColumns,
    required this.undoLeft,
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
      comboState: const ComboState(),
      streakState: const StreakState(),
      clearedRows: 0,
      clearedColumns: 0,
      undoLeft: journey.difficulty.undoCount,
      placedPieces: 0,
    );
  }

  final Journey journey;
  final Board board;

  /// Tepside kalan parçalar; kullanılan slot `null` olur.
  final List<BlockPiece?> tray;

  /// Kısa vadeli combo. Hazırlık payı ve en iyi combo bunun içinde.
  final ComboState comboState;

  /// Uzun vadeli seri. Tepsi başına temizlik kuralı bunun içinde.
  final StreakState streakState;

  final int clearedRows;
  final int clearedColumns;

  final int undoLeft;
  final int placedPieces;

  /// Combo ve seri'nin kısa okumaları — arayüz ve kayıt bunları kullanır.
  int get combo => comboState.value;
  int get bestCombo => comboState.best;
  int get streak => streakState.value;
  int get bestStreak => streakState.best;

  int get totalClearedLines => clearedRows + clearedColumns;

  bool get trayIsEmpty => tray.every((piece) => piece == null);

  GameSession copyWith({
    Board? board,
    List<BlockPiece?>? tray,
    ComboState? comboState,
    StreakState? streakState,
    int? clearedRows,
    int? clearedColumns,
    int? undoLeft,
    int? placedPieces,
  }) {
    return GameSession(
      journey: journey,
      board: board ?? this.board,
      tray: tray == null ? this.tray : List<BlockPiece?>.unmodifiable(tray),
      comboState: comboState ?? this.comboState,
      streakState: streakState ?? this.streakState,
      clearedRows: clearedRows ?? this.clearedRows,
      clearedColumns: clearedColumns ?? this.clearedColumns,
      undoLeft: undoLeft ?? this.undoLeft,
      placedPieces: placedPieces ?? this.placedPieces,
    );
  }
}
