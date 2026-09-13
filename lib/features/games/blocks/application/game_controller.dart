import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_store.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_run.dart';
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
    this.clearedCellValues = const <int, int>{},
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

  /// Temizlenen hücrelerin **silinmeden önceki** renk değerleri.
  ///
  /// Anahtar `satır * sütunSayısı + sütun`. Patlama efekti parçacıkları
  /// blokların kendi renginde savurabilsin diye taşınır; tahta temizlendikten
  /// sonra bu bilgi başka yerden okunamaz.
  final Map<int, int> clearedCellValues;

  int get linesCleared => clearedRows.length + clearedColumns.length;
  bool get didClear => linesCleared > 0;
}

/// Oyun oturumunu yöneten controller.
///
/// UI, oyun kurallarını bilmez; sadece bu controller'ı dinler.
/// Kuralların kendisi `domain/` altındaki saf fonksiyonlardadır.
class GameController extends ChangeNotifier implements JourneyRun {
  GameController({
    required Journey journey,
    PieceGenerator? generator,
    this.store,
    Random? random,
    int recordToBeat = 0,
    this.tick = AppConstants.playTick,
    GameSession? resumeFrom,
    // Alan private + mutable (restart tazeliyor), parametre public kalmalı;
    // `this._recordToBeat` dışarıdan kullanılamayacak bir ad üretirdi.
    // ignore: prefer_initializing_formals
  }) : _recordToBeat = recordToBeat,
       _generator = generator ?? PieceGenerator(random: random) {
    _session = resumeFrom ?? _createSession(journey);
  }

  final PieceGenerator _generator;

  /// En iyi skorun yazılacağı local depo. Test'te null bırakılabilir.
  final LocalStore? store;

  /// Bu rotada geçilmesi gereken rekor. 0 ise rotada ilk yolculuk.
  ///
  /// `final` değildir: [restart] bunu depodan tazeler. Aynı ekranda ikinci
  /// kez oynarken hedef, bir önceki oyunun kurduğu rekor olmalıdır.
  int _recordToBeat;

  @override
  int get recordToBeat => _recordToBeat;

  /// Aktif oyun süresi sayacının periyodu (test'te kısaltılabilir).
  final Duration tick;

  late GameSession _session;
  GameSession? _undoSnapshot;
  Timer? _timer;
  bool _isNewBest = false;
  bool _scoreSaved = false;

  /// Son durak geçişinden beri line temizlendi mi? Durak bonusunun koşulu.
  bool _clearedSinceLastStation = false;

  /// [_undoSnapshot] alındığı andaki [_clearedSinceLastStation] değeri.
  ///
  /// Geri alınan bir temizlik durak bonusunu hak etmiş saymamalı; yoksa
  /// oyuncu satırı temizleyip geri alarak bedava +25 kasabiliyor.
  bool _undoClearedSinceLastStation = false;

  /// Kazanılan son durak bonusu ve onu tetikleyen sayaç. UI, sayaç değişince
  /// kısa bir bildirim gösterir.
  @override
  int lastStationBonus = 0;
  @override
  int stationBonusPulse = 0;

  /// Durakta boşalan satır ve hücrelerin boşalmadan önceki renkleri.
  ///
  /// UI bunu yerleştirme temizliğiyle aynı patlama efektinde kullanır:
  /// oyuncu için "satır temizlendi" olayı tektir, sebebi ister hamlesi
  /// ister durak olsun.
  List<int> lastStationClearedRows = const <int>[];
  Map<int, int> lastStationClearedCells = const <int, int>{};
  int stationClearPulse = 0;

  GameSession get session => _session;

  // --- JourneyRun sözleşmesi ---
  //
  // Ortak yolculuk kabuğu ([JourneyScaffold]) yalnızca bu üyeleri görür;
  // board, tepsi ve combo gibi oyuna özgü şeyleri bilmez.
  @override
  int get score => _session.score;
  @override
  bool get recordBeaten => _session.recordBeaten;
  @override
  bool get isFirstRun => _session.isFirstRun;
  @override
  double get progress => _session.progress;
  @override
  double get recordProgress => _session.recordProgress;
  @override
  int get remainingSeconds => _session.remainingSeconds;

  @override
  bool get isSprint => _session.isSprint;

  /// Sprint **bu anda** başladıysa artan sayaç; UI bir kez şerit gösterir.
  @override
  int sprintPulse = 0;
  bool _sprintAnnounced = false;

  void _announceSprintIfStarted() {
    if (_sprintAnnounced || !_session.isSprint) return;
    _sprintAnnounced = true;
    sprintPulse++;
  }

  @override
  Journey get journey => _session.journey;
  Board get board => _session.board;
  List<BlockPiece?> get tray => _session.tray;
  @override
  GameStatus get status => _session.status;
  @override
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

  @override
  void start() {
    if (_session.status == GameStatus.playing) return;
    _session = _session.copyWith(status: GameStatus.playing);
    _startTimer();
    notifyListeners();
  }

  @override
  void pause() {
    if (_session.status != GameStatus.playing) return;
    _stopTimer();
    _session = _session.copyWith(status: GameStatus.paused);
    _persistSnapshot();
    notifyListeners();
  }

  @override
  void resume() {
    if (_session.status != GameStatus.paused) return;
    _session = _session.copyWith(status: GameStatus.playing);
    _startTimer();
    notifyListeners();
  }

  /// Aynı rotayla yeni oyun.
  @override
  void restart() {
    _stopTimer();
    _undoSnapshot = null;
    _isNewBest = false;
    _scoreSaved = false;
    _clearedSinceLastStation = false;
    lastStationBonus = 0;
    sprintPulse = 0;
    _sprintAnnounced = false;
    _refreshRecord();
    _session = _createSession(_session.journey);
    _persistSnapshot();
    start();
  }

  /// Geçilecek rekoru depodan tazeler.
  ///
  /// Rekor ekran açılırken bir kez okunur. Oyuncu sonuç panelinden "tekrar
  /// oyna" derse ekran yeniden kurulmaz; tazelenmezse ikinci oyun, az önce
  /// kırılmış olan **eski** rekoru hedefler ve ilk hamlede "rekoru geçtin"
  /// bildirimi çıkar.
  void _refreshRecord() {
    final journey = _session.journey;
    final stored = store?.bestScoreForRoute(
      journey.origin.id,
      journey.destination.id,
    );
    if (stored != null && stored > _recordToBeat) _recordToBeat = stored;
  }

  /// Kullanıcı rotadan çıktığında (ör. geri tuşu).
  ///
  /// Oyun bitmediyse kayıt korunur; kullanıcı açılış ekranından devam
  /// edebilir.
  @override
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

  /// Testte saniyeleri elle ilerletmek için — gerçek zamanlayıcıyı beklemeden
  /// durak geçişi ve varış sınanabilsin diye.
  @visibleForTesting
  void debugAdvanceSeconds(int seconds) {
    for (var i = 0; i < seconds; i++) {
      _onTick();
    }
  }

  void _onTick() {
    if (_session.status != GameStatus.playing) return;
    _session = _session.copyWith(elapsedSeconds: _session.elapsedSeconds + 1);

    _announceSprintIfStarted();
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

    _emptyCrowdedRowsAtStation();
  }

  /// Durağa varınca **kalabalık vagonlar boşalır**: en az yarısı dolu olan
  /// satırlar temizlenir.
  ///
  /// Ölçümle konuldu, süs değil. `balance_report_test` 150 oyun simüle
  /// ediyor ve tablo şunu söylüyordu: 9 dakikanın üstündeki her yolculukta
  /// varış oranı %0-3. Yani oyuncu tahtayı dolduruyor, oyun "hamle kalmadı"
  /// ile bitiyor ve **ürünün ana vaadi olan varış sahnesi gerçek bir işe
  /// gidiş yolculuğunda hiç oynamıyordu.** Aynı ölçümle uzun yolculukta
  /// varış %3'ten %35-48'e çıkıyor, kısa yolculuk ise değişmiyor.
  ///
  /// Zorluk ayarlarına dokunulmadı (engel oranı, parça havuzu, undo hakkı
  /// aynı). Skora da dokunmaz: boşalan satır puan getirmez, yalnız yer
  /// açar — puanı hâlâ oyuncunun kendi temizlediği satırlar kazandırır.
  void _emptyCrowdedRowsAtStation() {
    final rows = crowdedRows(_session.board);
    if (rows.isEmpty) return;

    lastStationClearedRows = rows;
    lastStationClearedCells = _cellValuesOf(
      _session.board,
      rows: rows,
      columns: const <int>[],
    );
    stationClearPulse++;

    _session = _session.copyWith(board: clearLines(_session.board, rows: rows));

    // Geri alma durağın öncesine dönemez: dönebilseydi boşalan satırlar
    // geri gelir, oyuncu da "geri aldım, tahtam doldu" diye cezalandırılmış
    // hissederdi.
    _undoSnapshot = null;
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
    _undoClearedSinceLastStation = _clearedSinceLastStation;

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

    final clearedCellValues = _cellValuesOf(
      board,
      rows: completedRows,
      columns: completedColumns,
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
      clearedCellValues: clearedCellValues,
    );

    _evaluateEndConditions();
    _persistSnapshot();
    notifyListeners();
    return outcome;
  }

  /// Temizlenecek hücrelerin renk değerleri; kesişimler bir kez yazılır.
  Map<int, int> _cellValuesOf(
    Board board, {
    required List<int> rows,
    required List<int> columns,
  }) {
    if (rows.isEmpty && columns.isEmpty) return const <int, int>{};
    final values = <int, int>{};
    for (final r in rows) {
      for (var c = 0; c < board.cols; c++) {
        values[r * board.cols + c] = board.valueAt(r, c);
      }
    }
    for (final c in columns) {
      for (var r = 0; r < board.rows; r++) {
        values[r * board.cols + c] = board.valueAt(r, c);
      }
    }
    return values;
  }

  /// Son hamleyi geri alır. Süre geri sarılmaz — sadece board/skor.
  bool undo() {
    if (!canUndo) return false;
    final snapshot = _undoSnapshot!;
    _undoSnapshot = null;
    // Geri alınan hamle bir line temizlediyse durak bonusu hakkı da geri gider.
    _clearedSinceLastStation = _undoClearedSinceLastStation;
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
