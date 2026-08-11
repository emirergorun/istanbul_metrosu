import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/local_store.dart';
import '../../journey/models/journey.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/game_state.dart';
import '../domain/scoring.dart';
import 'game_snapshot.dart';
import 'piece_generator.dart';

/// Bir yerleştirme denemesinin sonucu — UI geri bildirimi için.
@immutable
class PlaceOutcome {
  const PlaceOutcome({
    required this.accepted,
    this.gainedPoints = 0,
    this.clearedRows = const <int>[],
    this.clearedColumns = const <int>[],
    this.combo = 0,
    this.trayRefilled = false,
    this.beatRecord = false,
  });

  const PlaceOutcome.rejected() : this(accepted: false);

  final bool accepted;
  final int gainedPoints;
  final List<int> clearedRows;
  final List<int> clearedColumns;
  final int combo;
  final bool trayRefilled;

  /// Rotanın rekoru **bu hamlede** geçildi mi? Yalnızca bir kez `true` olur;
  /// oyun durmaz, UI kısa bir bildirim gösterir.
  final bool beatRecord;

  int get linesCleared => clearedRows.length + clearedColumns.length;
  bool get didClear => linesCleared > 0;
}

/// Oyun oturumunu yöneten controller.
///
/// UI, oyun kurallarını bilmez; sadece bu controller'ı dinler.
/// Kuralların kendisi `domain/` altındaki saf fonksiyonlardadır.
class GameController extends ChangeNotifier {
  GameController({
    required Journey journey,
    PieceGenerator? generator,
    this.store,
    Random? random,
    this.recordToBeat = 0,
    this.tick = AppConstants.playTick,
    GameSession? resumeFrom,
  }) : _generator = generator ?? PieceGenerator(random: random) {
    _session = resumeFrom ?? _createSession(journey);
  }

  final PieceGenerator _generator;

  /// En iyi skorun yazılacağı local depo. Test'te null bırakılabilir.
  final LocalStore? store;

  /// Bu rotada geçilmesi gereken rekor. 0 ise rotada ilk yolculuk.
  final int recordToBeat;

  /// Aktif oyun süresi sayacının periyodu (test'te kısaltılabilir).
  final Duration tick;

  late GameSession _session;
  GameSession? _undoSnapshot;
  Timer? _timer;
  bool _isNewBest = false;
  bool _scoreSaved = false;

  /// Son durak geçişinden beri line temizlendi mi? Durak bonusunun koşulu.
  bool _clearedSinceLastStation = false;

  /// Kazanılan son durak bonusu ve onu tetikleyen sayaç. UI, sayaç değişince
  /// kısa bir bildirim gösterir.
  int lastStationBonus = 0;
  int stationBonusPulse = 0;

  GameSession get session => _session;
  Journey get journey => _session.journey;
  Board get board => _session.board;
  List<BlockPiece?> get tray => _session.tray;
  GameStatus get status => _session.status;
  bool get isNewBest => _isNewBest;
  bool get canUndo =>
      _undoSnapshot != null &&
      _session.undoLeft > 0 &&
      _session.status == GameStatus.playing;

  GameSession _createSession(Journey journey) {
    final profile = journey.difficulty;
    final board = _generator.applyInitialBlockers(Board.empty(), profile);
    return GameSession.initial(
      journey: journey,
      board: board,
      tray: _generator.generateTray(board, profile),
      recordToBeat: recordToBeat,
    );
  }

  // --- Yaşam döngüsü ---

  void start() {
    if (_session.status == GameStatus.playing) return;
    _session = _session.copyWith(status: GameStatus.playing);
    _startTimer();
    notifyListeners();
  }

  void pause() {
    if (_session.status != GameStatus.playing) return;
    _stopTimer();
    _session = _session.copyWith(status: GameStatus.paused);
    _persistSnapshot();
    notifyListeners();
  }

  void resume() {
    if (_session.status != GameStatus.paused) return;
    _session = _session.copyWith(status: GameStatus.playing);
    _startTimer();
    notifyListeners();
  }

  /// Aynı rotayla yeni oyun.
  void restart() {
    _stopTimer();
    _undoSnapshot = null;
    _isNewBest = false;
    _scoreSaved = false;
    _clearedSinceLastStation = false;
    lastStationBonus = 0;
    _session = _createSession(_session.journey);
    _persistSnapshot();
    start();
  }

  /// Kullanıcı rotadan çıktığında (ör. geri tuşu).
  ///
  /// Oyun bitmediyse kayıt korunur; kullanıcı açılış ekranından devam
  /// edebilir.
  void abandon() {
    _stopTimer();
    if (_session.status.isFinished) return;
    _persistSnapshot();
    _session = _session.copyWith(status: GameStatus.abandoned);
    notifyListeners();
  }

  /// Yarım kalan oyunu diske yazar. Oyun bittiyse kaydı siler.
  void _persistSnapshot() {
    final target = store;
    if (target == null) return;
    if (_session.status.isFinished) {
      unawaited(target.clearSavedGame());
      return;
    }
    unawaited(target.saveGame(GameSnapshot.encode(_session)));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick() {
    if (_session.status != GameStatus.playing) return;
    _session = _session.copyWith(elapsedSeconds: _session.elapsedSeconds + 1);

    _awardStationBonusIfPassed();

    if (_session.remainingSeconds <= 0) {
      _finish(GameStatus.arrived);
      return;
    }
    notifyListeners();
  }

  /// Tren yeni bir durağı geçtiyse, o duraktan beri line temizlendiyse bonus.
  ///
  /// İlerleme çubuğunu dekorasyon olmaktan çıkarır: her durak arası küçük
  /// bir hedef olur.
  void _awardStationBonusIfPassed() {
    final stops = _session.journey.stopCount;
    if (stops <= 0) return;

    final passed = (_session.progress * stops).floor();
    if (passed <= _session.stationsPassed) return;

    final earned = _clearedSinceLastStation;
    _clearedSinceLastStation = false;
    _session = _session.copyWith(
      stationsPassed: passed,
      score: earned ? _session.score + ScoreRules.stationBonus : null,
    );

    if (earned) {
      lastStationBonus = ScoreRules.stationBonus;
      stationBonusPulse++;
      _checkRecord();
    }
  }

  /// Rekor bu anda geçildiyse işaretler ve geçildiğini döner.
  bool _checkRecord() {
    if (_session.recordBeaten || _session.isFirstRun) return false;
    if (_session.score <= _session.recordToBeat) return false;
    _session = _session.copyWith(recordBeaten: true);
    return true;
  }

  // --- Oyun hamlesi ---

  /// [trayIndex] parçasını board üzerinde ([row],[col]) köşesine koymayı dener.
  PlaceOutcome place(int trayIndex, int row, int col) {
    if (_session.status != GameStatus.playing) {
      return const PlaceOutcome.rejected();
    }
    if (trayIndex < 0 || trayIndex >= _session.tray.length) {
      return const PlaceOutcome.rejected();
    }

    final piece = _session.tray[trayIndex];
    if (piece == null) return const PlaceOutcome.rejected();
    if (!canPlace(_session.board, piece, row, col)) {
      return const PlaceOutcome.rejected();
    }

    _undoSnapshot = _session;

    var board = placePiece(_session.board, piece, row, col);
    final completedRows = findCompletedRows(board);
    final completedColumns = findCompletedColumns(board);

    final score = calculateScore(
      placedCells: piece.size,
      clearedRows: completedRows.length,
      clearedColumns: completedColumns.length,
      currentCombo: _session.combo,
      isSprint: _session.isSprint,
    );

    board = clearLines(board, rows: completedRows, columns: completedColumns);

    final tray = List<BlockPiece?>.of(_session.tray);
    tray[trayIndex] = null;

    var refilled = false;
    if (tray.every((piece) => piece == null)) {
      tray
        ..clear()
        ..addAll(_generator.generateTray(board, _session.journey.difficulty));
      refilled = true;
    }

    if (score.linesCleared > 0) _clearedSinceLastStation = true;

    final newScore = _session.score + score.points;
    _session = _session.copyWith(
      board: board,
      tray: tray,
      score: newScore,
      combo: score.combo,
      bestCombo: score.combo > _session.bestCombo
          ? score.combo
          : _session.bestCombo,
      clearedRows: _session.clearedRows + completedRows.length,
      clearedColumns: _session.clearedColumns + completedColumns.length,
      placedPieces: _session.placedPieces + 1,
    );

    final beatRecord = _checkRecord();

    final outcome = PlaceOutcome(
      accepted: true,
      gainedPoints: score.points,
      clearedRows: completedRows,
      clearedColumns: completedColumns,
      combo: score.combo,
      trayRefilled: refilled,
      beatRecord: beatRecord,
    );

    _evaluateEndConditions();
    _persistSnapshot();
    notifyListeners();
    return outcome;
  }

  /// Son hamleyi geri alır. Süre geri sarılmaz — sadece board/skor.
  bool undo() {
    if (!canUndo) return false;
    final snapshot = _undoSnapshot!;
    _undoSnapshot = null;
    _session = snapshot.copyWith(
      elapsedSeconds: _session.elapsedSeconds,
      undoLeft: snapshot.undoLeft - 1,
      status: GameStatus.playing,
    );
    notifyListeners();
    return true;
  }

  void _evaluateEndConditions() {
    // Hedefe ulaşmak oyunu bitirmez — tek final varıştır.
    // Hiç legal hamle kalmadıysa: game over.
    if (!hasAnyLegalMove(_session.board, _session.tray)) {
      _finish(GameStatus.gameOver);
    }
  }

  void _finish(GameStatus status) {
    _stopTimer();
    _session = _session.copyWith(status: status);
    unawaited(store?.clearSavedGame() ?? Future<void>.value());
    notifyListeners();
    unawaited(_persistScore());
  }

  Future<void> _persistScore() async {
    final target = store;
    if (target == null || _scoreSaved) return;
    _isNewBest = await target.submitRouteScore(
      originId: _session.journey.origin.id,
      destinationId: _session.journey.destination.id,
      score: _session.score,
    );
    _scoreSaved = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
