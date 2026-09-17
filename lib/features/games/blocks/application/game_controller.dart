import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/local_store.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_game_controller.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/clear_result.dart';
import '../domain/game_state.dart';
import '../domain/scoring.dart';
import 'game_snapshot.dart';
import 'piece_generator.dart';

/// Bir yerleştirme denemesinin sonucu — UI geri bildirimi için.
///
/// Hamlenin **ne olduğu** [ClearResult] içindedir; burada yalnızca
/// yerleştirmenin kabul edilip edilmediği ve yerleştirmeye eşlik eden
/// oturum olayları (tepsi yenilendi, rekor geçildi) durur.
@immutable
class PlaceOutcome {
  const PlaceOutcome({
    required this.accepted,
    this.result,
    this.trayRefilled = false,
    this.beatRecord = false,
  });

  const PlaceOutcome.rejected() : this(accepted: false);

  final bool accepted;

  /// Hamlenin tam sonucu. Yerleştirme reddedildiyse `null`.
  final ClearResult? result;

  final bool trayRefilled;

  /// Rotanın rekoru **bu hamlede** geçildi mi? Yalnızca bir kez `true` olur;
  /// oyun durmaz, UI kısa bir bildirim gösterir.
  final bool beatRecord;

  // --- [ClearResult] kısayolları ---
  //
  // Sunum katmanı her seferinde null kontrolü yapmasın diye.

  int get gainedPoints => result?.scoreAwarded ?? 0;
  List<int> get clearedRows => result?.clearedRows ?? const <int>[];
  List<int> get clearedColumns => result?.clearedColumns ?? const <int>[];

  /// Temizlenen hücrelerin **silinmeden önceki** renk değerleri.
  Map<int, int> get clearedCellValues =>
      result?.clearedCellValues ?? const <int, int>{};

  int get combo => result?.comboIndex ?? 0;
  int get streak => result?.streakIndex ?? 0;

  /// Bu hamlenin yolculuğa kattığı saniye.
  int get journeySeconds => result?.journeySecondsAwarded ?? 0;

  ClearTier get tier => result?.tier ?? ClearTier.none;
  int get linesCleared => result?.totalLines ?? 0;
  bool get didClear => linesCleared > 0;

  /// Aynı hamlede hem satır hem sütun temizlendi mi?
  bool get simultaneousClear => result?.simultaneousClear ?? false;
}

/// Blok Metro'nun oyun kuralları.
///
/// Yolculuk motorunu ([JourneyGameController]) kullanır: sayaç, varış
/// tespiti, durak bonusu, sprint, rekor takibi ve kaydı oradan gelir.
/// Burada yalnızca blok oyununa özgü olan var — tahta, tepsi, combo, seri,
/// geri alma ve yarım kalan oyunun kaydı.
///
/// Motora taşınmadan önce bütün bu ortak mantık burada **ikinci kez**
/// yazılıydı; sayaç, durak geçişi ve rekor kaydı iki yerde sürdürülüyordu.
///
/// UI, oyun kurallarını bilmez; sadece bu controller'ı dinler. Kuralların
/// kendisi `domain/` altındaki saf fonksiyonlardadır.
class GameController extends JourneyGameController {
  GameController({
    required super.journey,
    PieceGenerator? generator,
    super.store,
    Random? random,
    super.recordToBeat = 0,
    super.tick = AppConstants.playTick,
    GameSession? resumeFrom,
    ResumedProgress? resumeProgress,
  }) : _generator = generator ?? PieceGenerator(random: random),
       super(gameId: LocalStore.legacyRouteGameId) {
    _session = resumeFrom ?? _createSession(journey);

    if (resumeProgress != null) {
      // Kayıt, kaydedildiği andaki rekoru taşır; depodaki değer bu arada
      // yükselmiş olabilir. Yüksek olan hedeflenir, yoksa oyun seçim
      // ekranındakinden farklı bir rekor gösterir.
      raiseRecordToBeat(resumeProgress.recordToBeat);
      restoreProgress(
        score: resumeProgress.score,
        elapsedSeconds: resumeProgress.elapsedSeconds.toDouble(),
        stationsPassed: resumeProgress.stationsPassed,
        recordBeaten: resumeProgress.recordBeaten,
      );
      // Kayıttan dönen oyun daima duraklatılmış başlar: kullanıcı hazır
      // olduğunda açıkça "devam et" der.
      setStatus(GameStatus.paused);
    }

    _loadRunRecords();
  }

  /// Blok Metro'nun depodaki oyun kimliği.
  ///
  /// Oyun bazlı rekorlar gelmeden önce yazıldığı için eski, oyun adı
  /// taşımayan rota anahtarını kullanmaya devam eder.
  static const String id = LocalStore.legacyRouteGameId;

  final PieceGenerator _generator;

  late GameSession _session;
  GameSession? _undoSnapshot;

  /// Bu koşuda kırılan combo / seri / durak rekorları.
  ///
  /// Skordan ayrı tutulur: düşük skorlu bir koşuda bile en iyi seri
  /// kurulmuş olabilir ve oyuncu bunu görmeyi hak eder.
  RunRecordResult _runRecords = const RunRecordResult.none();
  RunRecordResult get runRecords => _runRecords;

  /// Koşu başlarken okunan önceki rekorlar; sonuç paneli kıyas için gösterir.
  int _bestComboToBeat = 0;
  int _bestStreakToBeat = 0;
  int _maxStationsToBeat = 0;

  int get bestComboToBeat => _bestComboToBeat;
  int get bestStreakToBeat => _bestStreakToBeat;
  int get maxStationsToBeat => _maxStationsToBeat;

  void _loadRunRecords() {
    final target = store;
    if (target == null) return;
    final origin = journey.origin.id;
    final destination = journey.destination.id;
    _bestComboToBeat = target.bestComboForRoute(
      gameId: gameId,
      originId: origin,
      destinationId: destination,
    );
    _bestStreakToBeat = target.bestStreakForRoute(
      gameId: gameId,
      originId: origin,
      destinationId: destination,
    );
    _maxStationsToBeat = target.maxStationsForRoute(
      gameId: gameId,
      originId: origin,
      destinationId: destination,
    );
  }

  /// Hamle kalmadı ama son hamle geri alınabiliyor.
  ///
  /// Oyun bu durumda hemen bitmez: oyuncu hakkı varken "Hamle kalmadı"
  /// görüp haksızlığa uğramış hissediyordu. Karar verilene kadar yolculuk
  /// sayacı durur; yoksa oyuncu hiç oynamadan bekleyip varışa ulaşabilirdi.
  bool _awaitingUndo = false;
  bool get awaitingUndo => _awaitingUndo;

  /// [_undoSnapshot] alındığı andaki durak bonusu hakkı.
  ///
  /// Geri alınan bir temizlik durak bonusunu hak etmiş saymamalı; yoksa
  /// oyuncu satırı temizleyip geri alarak bedava bonus kasabiliyor.
  bool _undoStationProgress = false;

  /// Son hamlenin kazandırdığı puan ve süre; geri alma bunları geri verir.
  int _undoScore = 0;
  int _trayRefillsLeft = ScoreRules.trayRefillCount;
  int _linesSinceStation = 0;
  int _undoLines = 0;
  int _goalsReached = 0;
  int goalPulse = 0;
  int _undoJourneySeconds = 0;

  /// Durakta boşalan satır bilgisi yok: durakta tahtaya dokunulmuyor.

  GameSession get session => _session;

  Board get board => _session.board;
  List<BlockPiece?> get tray => _session.tray;

  bool get canUndo =>
      _undoSnapshot != null && _session.undoLeft > 0 && status.isActive;

  GameSession _createSession(Journey journey) {
    final profile = journey.difficulty;
    final board = _generator.applyInitialBlockers(Board.empty(), profile);
    return GameSession.initial(
      journey: journey,
      board: board,
      tray: _generator.generateTray(board, profile),
    );
  }

  // --- Motor kancaları ---

  @override
  void onRestart() {
    _undoSnapshot = null;
    _awaitingUndo = false;
    _undoScore = 0;
    _undoJourneySeconds = 0;
    _undoStationProgress = false;
    _runRecords = const RunRecordResult.none();
    _session = _createSession(journey);
    _loadRunRecords();
    _persistSnapshot();
  }

  @override
  void onPause() => _persistSnapshot();

  @override
  void onResume() {
    // Geri alma teklifi açıkken duraklatıldıysa sayaç yine durur.
    if (_awaitingUndo) {
      holdClock();
      return;
    }

    // Kayıttan dönen oyunun tahtası kilitli olabilir: teklif açıkken uygulama
    // kapandıysa geri alma kaydı diske yazılmadığı için hamle de yoktur.
    if (!hasAnyLegalMove(_session.board, _session.tray)) endGame();
  }

  @override
  void onAbandon() => _persistSnapshot();

  @override
  void onFinish(GameStatus status) {
    unawaited(store?.clearSavedGame() ?? Future<void>.value());
    unawaited(_persistRunRecords());
  }

  /// Kullanıcı rotadan çıktığında (ör. geri tuşu).
  ///
  /// Oyun bitmediyse kayıt korunur; kullanıcı açılış ekranından devam
  /// edebilir.
  @override
  void abandon() {
    // Teklif açıkken çıkmak, geri almayı reddetmek demek.
    if (_awaitingUndo && !status.isFinished) {
      acceptGameOver();
      return;
    }
    super.abandon();
  }

  /// Yarım kalan oyunu diske yazar. Oyun bittiyse kaydı siler.
  void _persistSnapshot() {
    final target = store;
    if (target == null) return;
    if (status.isFinished) {
      unawaited(target.clearSavedGame());
      return;
    }
    unawaited(target.saveGame(GameSnapshot.encode(this)));
  }

  /// Testte saniyeleri elle ilerletmek için — gerçek zamanlayıcıyı beklemeden
  /// durak geçişi ve varış sınanabilsin diye.
  @visibleForTesting
  void debugAdvanceSeconds(int seconds) {
    for (var i = 0; i < seconds; i++) {
      if (_awaitingUndo) return;
      advance(1);
    }
  }

  // --- Oyun hamlesi ---

  /// [trayIndex] parçasını board üzerinde ([row],[col]) köşesine koymayı dener.
  ///
  /// Sıra bilinçlidir: önce tahta değişir, sonra combo ve seri ilerler,
  /// sonra puan **o yeni değerlerle** hesaplanır, en sonda yolculuk kazancı
  /// süreye eklenir. Kazanç süreyi ilerlettiği için durak geçişini ve hatta
  /// varışı tetikleyebilir; bu yüzden en sonda durur.
  PlaceOutcome place(int trayIndex, int row, int col) {
    if (!status.isActive || _awaitingUndo) {
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
    _undoStationProgress = hasStationProgress;
    // Bu hamlenin kendi kazancı; önceki hamleninki taşınmamalı.
    _undoScore = 0;
    _undoJourneySeconds = 0;

    var board = placePiece(_session.board, piece, row, col);
    final completedRows = findCompletedRows(board);
    final completedColumns = findCompletedColumns(board);
    final didClear = completedRows.isNotEmpty || completedColumns.isNotEmpty;

    // Sıra takibi burada ilerler; skorlama saf hesaplayıcı kalır.
    final combo = _session.comboState.register(didClear: didClear);
    final streak = _session.streakState.register(didClear: didClear);

    // Sprint motordan okunur ve hamlenin **yapıldığı andaki** ilerlemeye
    // göre belirlenir; hamlenin kendi kazandırdığı saniye sprinti açmış
    // sayılmaz. Çarpan da motorun [addScore] içinde uygulanır, burada
    // ikinci kez uygulanmamalı.
    final score = calculateScore(
      placedCells: piece.size,
      clearedRows: completedRows.length,
      clearedColumns: completedColumns.length,
      combo: combo.value,
      streak: streak.value,
    );

    final clearedCellValues = _cellValuesOf(
      board,
      rows: completedRows,
      columns: completedColumns,
    );
    board = clearLines(board, rows: completedRows, columns: completedColumns);

    final journeySeconds = JourneyRules.secondsFor(
      tier: ClearTier.of(score.linesCleared),
      combo: combo.value,
      streak: streak.value,
    );

    final tray = List<BlockPiece?>.of(_session.tray);
    tray[trayIndex] = null;

    var refilled = false;
    if (tray.every((piece) => piece == null)) {
      tray
        ..clear()
        ..addAll(_generator.generateTray(board, journey.difficulty));
      refilled = true;
    }

    if (didClear) {
      markStationProgress();
      final lines = completedRows.length + completedColumns.length;
      _linesSinceStation += lines;
      _undoLines = lines;
    } else {
      _undoLines = 0;
    }

    _session = _session.copyWith(
      board: board,
      tray: tray,
      comboState: combo,
      streakState: streak,
      clearedRows: _session.clearedRows + completedRows.length,
      clearedColumns: _session.clearedColumns + completedColumns.length,
      placedPieces: _session.placedPieces + 1,
    );

    final scoreBefore = this.score;
    final beatRecord = addScore(score.points);
    _undoScore = this.score - scoreBefore;

    final result = didClear
        ? ClearResult(
            clearedRows: completedRows,
            clearedColumns: completedColumns,
            clearedCellValues: clearedCellValues,
            comboIndex: combo.value,
            streakIndex: streak.value,
            scoreAwarded: _undoScore,
            journeySecondsAwarded: journeySeconds,
          )
        : ClearResult.none(
            comboIndex: combo.value,
            streakIndex: streak.value,
            scoreAwarded: _undoScore,
          );

    final outcome = PlaceOutcome(
      accepted: true,
      result: result,
      trayRefilled: refilled,
      beatRecord: beatRecord,
    );

    // İyi oyun trenin hızını artırır. Varışı tetikleyebileceği için
    // bitiş koşullarından önce uygulanır.
    _applyJourneyBonus(journeySeconds);
    _logMove(result);

    if (status.isFinished) {
      notifyListeners();
      return outcome;
    }

    _evaluateEndConditions();
    _persistSnapshot();
    notifyListeners();
    return outcome;
  }

  /// Hamlenin kazandırdığı saniyeyi yolculuğa ekler.
  ///
  /// Motorun ortak kanalı kullanılıyor ([rewardJourney]); `advance(0)`
  /// birikeni saate yazdırıp durak ve varış kontrollerini çalıştırıyor.
  /// Blok Metro'nun kazancı tek bir sabite sığmadığı için
  /// [journeySecondsPerGoodMove] yerine bu yol seçildi: değer temizlenen
  /// hat sayısına, combo'ya ve seriye göre değişiyor.
  ///
  /// Geri alma bu saniyeyi de geri verir ([undo]); yoksa oyuncu temizleyip
  /// geri alarak bedava zaman kasardı.
  void _applyJourneyBonus(int seconds) {
    if (seconds <= 0) return;
    _undoJourneySeconds = seconds;
    rewardJourney(seconds.toDouble());
    advance(0);
  }

  /// Yolculuk ilerledikçe durak geçişini izler.
  ///
  /// Geri alma durağın öncesine dönemez: dönebilseydi geçilen durak bir
  /// sonraki saniyede **yeniden** işlenir, bonus ikinci kez verilirdi.
  /// Sayaç da, hamlenin kazandırdığı saniye de aynı yoldan geçtiği için
  /// kontrol tek yerde duruyor.
  @override
  void advance(double dt) {
    final stationsBefore = stationsPassed;
    super.advance(dt);
    if (stationsPassed <= stationsBefore) return;

    _undoSnapshot = null;
    // Durak geçildi: bu aralığın hedefi tutturulduysa ek bonus, sonra
    // sayaç sıfırlanır ve yeni aralık başlar.
    if (_linesSinceStation >= ScoreRules.stationGoalLines) {
      _goalsReached++;
      goalPulse++;
      addScore(ScoreRules.stationGoalBonus);
    }
    _linesSinceStation = 0;
  }

  /// Bu durak aralığında temizlenen hat sayısı.
  int get linesSinceStation => _linesSinceStation;

  /// Aralık hedefine kalan hat sayısı; hedef tutmuşsa 0.
  int get linesToStationGoal =>
      (ScoreRules.stationGoalLines - _linesSinceStation).clamp(0, 99).toInt();

  /// Yolculuk boyunca tutturulan durak hedefi sayısı.
  int get goalsReached => _goalsReached;

  /// Dengeleme günlüğü — yalnızca debug derlemede.
  void _logMove(ClearResult result) {
    if (!kDebugMode) return;
    debugPrint(
      'HAMLE #${_session.placedPieces} '
      '| line ${result.totalLines} (${result.tier.name})'
      '${result.simultaneousClear ? " satır+sütun" : ""} '
      '| combo ${result.comboIndex} '
      '| streak ${result.streakIndex} '
      '| skor +${result.scoreAwarded} ($score) '
      '| süre +${result.journeySecondsAwarded} sn '
      '| ${journey.origin.name} -> ${journey.destination.name} '
      '| ${elapsedSeconds.floor()}/${journey.estimatedSeconds} sn '
      '| durak $stationsPassed/${journey.stopCount}',
    );
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

  /// Son hamleyi geri alır.
  ///
  /// Tahta, tepsi, combo ve seri eski hâline döner; motor tarafında da
  /// hamlenin kazandırdığı puan ve süre geri verilir. Saat geri sarılmaz —
  /// yolculuk gerçek zamanda ilerliyor.
  bool undo() {
    if (!canUndo) return false;
    final snapshot = _undoSnapshot!;
    _undoSnapshot = null;

    // Geri alınan hamle bir line temizlediyse durak bonusu hakkı da geri gider.
    revokeStationProgress(_undoStationProgress);

    // Hamlenin puanı geri alınır, **üstüne** sabit bedel biner.
    restoreProgress(
      score: (score - _undoScore - ScoreRules.undoPenalty).clamp(0, score),
      elapsedSeconds: elapsedSeconds - _undoJourneySeconds,
    );
    _undoScore = 0;
    _undoJourneySeconds = 0;
    // Geri alınan hamle hat temizlediyse hedef sayacı da geri gider.
    _linesSinceStation = (_linesSinceStation - _undoLines).clamp(0, 99).toInt();
    _undoLines = 0;

    _session = snapshot.copyWith(undoLeft: snapshot.undoLeft - 1);

    if (_awaitingUndo) {
      _awaitingUndo = false;
      releaseClock();
    }
    notifyListeners();
    return true;
  }

  /// Kalan tepsi yenileme hakkı.
  int get trayRefillsLeft => _trayRefillsLeft;

  /// Tepsi yenilenebilir mi?
  ///
  /// Yalnızca **hamlesiz kalındığında** kullanılabilir. Oyun sürerken
  /// istenen parçayı beklemek için basılabilseydi tepsi bir kaynak değil,
  /// bir kumanda olurdu.
  bool get canRefillTray =>
      _trayRefillsLeft > 0 &&
      status.isActive &&
      !hasAnyLegalMove(_session.board, _session.tray);

  /// Tepsiyi yeniler: üç yeni parça gelir, oyun devam eder.
  bool refillTray() {
    if (!canRefillTray) return false;
    _trayRefillsLeft--;
    _undoSnapshot = null;
    _session = _session.copyWith(
      tray: _generator.generateTray(_session.board, journey.difficulty),
    );
    if (_awaitingUndo) {
      _awaitingUndo = false;
      releaseClock();
    }
    // Yeni tepsi de sığmıyorsa oyun normal akışına döner.
    _evaluateEndConditions();
    notifyListeners();
    return true;
  }

  /// Oyuncu geri alma teklifini reddetti: oyun "hamle kalmadı" ile biter.
  void acceptGameOver() {
    if (!_awaitingUndo) return;
    _awaitingUndo = false;
    _undoSnapshot = null;
    endGame();
  }

  void _evaluateEndConditions() {
    // Hedefe ulaşmak oyunu bitirmez — tek final varıştır.
    if (hasAnyLegalMove(_session.board, _session.tray)) return;

    // Tepsi yenileme hakkı varsa oyun bitmez: oyuncuya sorulur.
    if (_trayRefillsLeft > 0) {
      _awaitingUndo = true;
      holdClock();
      return;
    }

    // Hak varsa oyun bitmez, son hamleyi geri alma şansı verilir.
    if (canUndo) {
      _awaitingUndo = true;
      holdClock();
      return;
    }
    endGame();
  }

  Future<void> _persistRunRecords() async {
    final target = store;
    if (target == null) return;
    // Combo, seri ve durak rekorları skordan bağımsız değerlendirilir.
    _runRecords = await target.submitRunRecords(
      gameId: gameId,
      originId: journey.origin.id,
      destinationId: journey.destination.id,
      bestCombo: _session.bestCombo,
      bestStreak: _session.bestStreak,
      stationsPassed: stationsPassed,
    );
    notifyListeners();
  }
}

/// Kayıttan dönen oyunun **motor** durumu.
///
/// Tahta durumu [GameSession] içinde, skor/süre/rekor burada: ikisi ayrı
/// katmanda yaşıyor, kayıt da ikisini ayrı taşıyor.
@immutable
class ResumedProgress {
  const ResumedProgress({
    required this.score,
    required this.elapsedSeconds,
    required this.stationsPassed,
    required this.recordToBeat,
    required this.recordBeaten,
  });

  final int score;
  final int elapsedSeconds;
  final int stationsPassed;
  final int recordToBeat;
  final bool recordBeaten;
}
