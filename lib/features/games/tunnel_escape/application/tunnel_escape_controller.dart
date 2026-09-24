import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../data/escape_levels.dart';
import '../domain/escape_board.dart';
import '../domain/escape_level.dart';
import '../domain/escape_rules.dart';
import 'escape_hint_service.dart';
import 'escape_progress_controller.dart';

/// Oyun ekranının hangi yüzü görünüyor.
enum EscapePhase {
  /// Hat haritası: bölüm seçimi.
  map,

  /// Bölüm oynanıyor.
  playing,

  /// Kırmızı metro tünele giriyor; dokunuş kilitli.
  exiting,

  /// Bölüm bitti, tamamlanma paneli açık.
  solved,
}

/// Bir sürükleyişin sonucu.
enum EscapeMoveOutcome {
  /// Metro yer değiştirdi, bir hamle sayıldı.
  moved,

  /// Metro yer değiştirdi ve kırmızı metro tünel ağzına ulaştı.
  solved,

  /// Metro bıraktığı yere geri döndü: hamle sayılmaz.
  unchanged,

  /// Oyun oynanmıyor ya da girdi kilitli.
  ignored,
}

/// İpucunun gösterdiği hamle.
@immutable
class EscapeHint {
  const EscapeHint({required this.piece, required this.from, required this.to});

  final int piece;
  final int from;
  final int to;
}

/// Biten bölümün özeti — tamamlanma paneli bunu çizer.
@immutable
class EscapeCompletion {
  const EscapeCompletion({
    required this.level,
    required this.moves,
    required this.stars,
    required this.usedHint,
    required this.record,
    required this.pointsAwarded,
    required this.hasNext,
  });

  final EscapeLevel level;
  final int moves;
  final int stars;
  final bool usedHint;
  final EscapeRecordResult record;

  /// Yolculuğa yazılan puan (ölçek uygulanmış, HUD'daki birimle aynı).
  final int pointsAwarded;

  /// Sonraki bölüm var mı? Son bölümde "sonraki durak" yok.
  final bool hasNext;

  int get bestMoves => record.current.bestMoves ?? moves;

  bool get isNewBest => record.isNewBestFor(moves);

  /// Son bölüm — "HAT TAMAMLANDI".
  bool get isFinale => !hasNext;
}

/// Tünele Kaç — kaydırmalı metro bulmacası.
///
/// Tahtada beyaz metrolar ve tek bir kırmızı metro var. Metrolar yalnız
/// kendi eksenlerinde kayar; amaç beyazları kaydırıp kırmızının önünü açmak
/// ve onu sağdaki tünele götürmek.
///
/// **İki ilerleme, tek olay.** Bölüm bitince iki ayrı şey olur:
///
/// * Bulmaca ilerlemesi ([EscapeProgressController]): bölüm bitti, en iyi
///   hamle, yıldız, sonraki bölümün açılması. Yolculuktan bağımsız ve
///   kalıcı.
/// * Yolculuk puanı ([JourneyGameController.addScore]): rota rekoruna
///   yazılan ortak kova. Tekrar oynayarak kasılamaz, bkz.
///   [EscapeRules.journeyPoints].
///
/// Oyunun bir "yanma" hâli yok: hatalı hamle geri alınır, bölüm baştan
/// başlatılır. Koşu bu yüzden varışla ya da oyuncunun çıkışıyla biter
/// ([leave]).
class TunnelEscapeController extends JourneyGameController {
  TunnelEscapeController({
    required super.journey,
    required super.recordToBeat,
    required this.levelProgress,
    super.store,
    super.discovery,
    super.tick = AppConstants.playTick,
    super.session,
    List<EscapeLevel>? levels,
    this.hintSolver = solveHintInBackground,
  }) : levels = levels ?? EscapeLevels.all,
       super(gameId: id);

  /// Rekor ve kayıt anahtarlarında kullanılır; değiştirilmemeli.
  static const String id = 'tunnel_escape';

  /// Bulmaca ilerlemesi — yolculuktan bağımsız, kalıcı.
  final EscapeProgressController levelProgress;
  final List<EscapeLevel> levels;

  /// Sıradaki faydalı hamleyi arayan işlev; uygulamada ayrı isolate.
  final EscapeHintSolver hintSolver;

  /// Bu yolculukta tekrar payı alınmış bölümler.
  ///
  /// Oyuna değil **yolculuğa** bağlı: oyuncu oyundan çıkıp aynı yolculukta
  /// geri dönerse küme sıfırlanmamalı, yoksa çık-gir ile tekrar payı
  /// yeniden alınırdı. [Expando] kümeyi oturum nesnesine iliştiriyor;
  /// oturum ölünce küme de gider.
  static final Expando<Set<int>> _creditedByJourney = Expando<Set<int>>(
    'tunnel_escape_credited',
  );

  EscapePhase _phase = EscapePhase.map;
  EscapeLevel? _level;
  EscapeBoard? _board;
  final List<EscapeBoard> _history = <EscapeBoard>[];
  int _moves = 0;
  bool _usedHint = false;
  bool _usedUndo = false;
  EscapeHint? _hint;
  int _hintToken = 0;
  bool _hintPending = false;
  EscapeCompletion? _completion;

  int _levelsSolved = 0;
  int _starsEarned = 0;

  EscapePhase get phase => _phase;
  EscapeLevel? get level => _level;
  EscapeBoard? get board => _board;
  int get moves => _moves;
  bool get usedHint => _usedHint;
  bool get usedUndo => _usedUndo;
  EscapeHint? get hint => _hint;
  bool get isHintPending => _hintPending;
  EscapeCompletion? get completion => _completion;

  /// Bu koşuda bitirilen bölüm sayısı.
  int get levelsSolvedThisRun => _levelsSolved;

  /// Bu koşuda bitirilen bölümlerin yıldız toplamı.
  int get starsThisRun => _starsEarned;

  bool get canUndo => acceptsInput && _history.isNotEmpty;

  /// Tahtaya dokunuş kabul ediliyor mu?
  bool get acceptsInput =>
      status == GameStatus.playing && _phase == EscapePhase.playing;

  /// Haritada öne çıkan bölüm: açık olup bitmemiş ilk bölüm.
  int get nextLevelNumber => levelProgress.nextLevel(levels.length);

  Set<int> get _credited => _creditedByJourney[journeySession] ??= <int>{};

  // --- Harita ---

  /// Bölümü açar. Kilitli bölüm açılmaz.
  bool openLevel(int number) {
    if (number < 1 || number > levels.length) return false;
    if (!levelProgress.isUnlocked(number)) return false;
    if (status != GameStatus.playing && status != GameStatus.paused) {
      return false;
    }
    _loadLevel(levels[number - 1]);
    _phase = EscapePhase.playing;
    notifyListeners();
    return true;
  }

  /// Haritaya döner. Yarım bölüm bırakılır; ilerleme zaten yalnız bitişte
  /// yazıldığı için kaybolan bir şey yok.
  void showMap() {
    if (_phase == EscapePhase.map) return;
    _phase = EscapePhase.map;
    _hint = null;
    _hintToken++;
    notifyListeners();
  }

  /// Tamamlanma panelindeki "sonraki durak".
  bool openNext() {
    final done = _completion;
    if (done == null || !done.hasNext) return false;
    return openLevel(done.level.number + 1);
  }

  /// Tamamlanma panelindeki "tekrar".
  bool replay() {
    final current = _level;
    if (current == null) return false;
    return openLevel(current.number);
  }

  // --- Hamleler ---

  /// Metronun şu anki tahtada gidebileceği aralık.
  (int, int) rangeOf(int piece) => _board!.rangeOf(piece);

  /// Bir sürükleyişi işler: metro [to] konumuna bırakıldı.
  ///
  /// Tek sürükleyiş tek hamledir, metro kaç hücre giderse gitsin. Metro
  /// bırakıldığı yere dönmüşse hamle sayılmaz.
  EscapeMoveOutcome commitMove(int piece, int to) {
    final board = _board;
    if (!acceptsInput || board == null) return EscapeMoveOutcome.ignored;
    if (piece < 0 || piece >= board.positions.length) {
      return EscapeMoveOutcome.ignored;
    }
    if (board.positions[piece] == to) return EscapeMoveOutcome.unchanged;
    if (!board.canMove(piece, to)) return EscapeMoveOutcome.ignored;

    _history.add(board);
    _board = board.moved(piece, to);
    _moves++;
    _hint = null;
    _hintToken++;
    markStationProgress();

    if (_board!.isSolved) {
      _complete();
      return EscapeMoveOutcome.solved;
    }
    notifyListeners();
    return EscapeMoveOutcome.moved;
  }

  /// Son hamleyi geri alır: tahta ve hamle sayısı bir önceki hâline döner.
  ///
  /// Yığında yalnız **tamamlanmış** hamlelerin tahtası var; yarım kalmış
  /// bir sürükleyiş hiçbir zaman buraya girmez.
  bool undo() {
    if (!canUndo) return false;
    _board = _history.removeLast();
    _moves--;
    _usedUndo = true;
    _hint = null;
    _hintToken++;
    notifyListeners();
    return true;
  }

  /// Bölümü başa sarar. Yeni bir deneme: sayaç, geçmiş ve ipucu sıfırlanır.
  void restartLevel() {
    final current = _level;
    if (current == null || _phase != EscapePhase.playing) return;
    _loadLevel(current);
    notifyListeners();
  }

  /// Sıradaki faydalı hamleyi ister.
  ///
  /// Arama ayrı bir isolate'te yürür; cevap gelene kadar tahta değişmişse
  /// (oyuncu bu arada bir metro kaydırdıysa) sonuç atılır.
  Future<void> requestHint() async {
    final board = _board;
    if (!acceptsInput || board == null || _hintPending) return;
    final token = ++_hintToken;
    _hintPending = true;
    notifyListeners();
    final move = await hintSolver(board.layout, board.positions);
    if (token != _hintToken) {
      // İstek geçersizleşti ama bekleme bitti.
      _hintPending = false;
      notifyListeners();
      return;
    }
    _hintPending = false;
    if (move != null && acceptsInput && identical(_board, board)) {
      _hint = EscapeHint(piece: move.piece, from: move.from, to: move.to);
      _usedHint = true;
    }
    notifyListeners();
  }

  void clearHint() {
    if (_hint == null) return;
    _hint = null;
    notifyListeners();
  }

  /// Tünel animasyonu bitti: tamamlanma paneli açılır.
  void finishExit() {
    if (_phase != EscapePhase.exiting) return;
    _phase = EscapePhase.solved;
    notifyListeners();
  }

  /// Oyuncu oyundan çıkıyor.
  ///
  /// Bu koşuda en az bir bölüm bittiyse koşu **bitmiş** sayılır ve
  /// bildirilir (günlük görev, Yolculuk Kartı). Hiç bölüm bitmediyse
  /// yarıda bırakılmış bir oyundur, diğer oyunlardaki gibi sayılmaz.
  void leave() {
    if (status.isFinished || status == GameStatus.abandoned) return;
    if (_levelsSolved > 0) {
      endGame();
    } else {
      abandon();
    }
  }

  void _loadLevel(EscapeLevel level) {
    _level = level;
    _board = level.initialBoard;
    _history.clear();
    _moves = 0;
    _usedHint = false;
    _usedUndo = false;
    _hint = null;
    _hintToken++;
    _hintPending = false;
    _completion = null;
  }

  void _complete() {
    final level = _level!;
    final stars = EscapeRules.starsFor(
      moves: _moves,
      threeStarMoves: level.threeStarMoves,
      twoStarMoves: level.twoStarMoves,
      usedHint: _usedHint,
    );
    final perfect =
        !_usedHint &&
        _moves <= level.optimalMoves &&
        level.optimalMoves >= EscapeRules.perfectMinimumMoves;
    final record = levelProgress.record(
      level: level.number,
      moves: _moves,
      stars: stars,
      perfect: perfect,
    );

    final raw = EscapeRules.journeyPoints(
      optimal: level.optimalMoves,
      stars: stars,
      previousBestStars: record.previousBestStars,
      alreadyCreditedThisJourney: _credited.contains(level.number),
    );
    _credited.add(level.number);
    final before = score;
    if (raw > 0) addScore(raw);

    _levelsSolved++;
    _starsEarned += stars;
    _completion = EscapeCompletion(
      level: level,
      moves: _moves,
      stars: stars,
      usedHint: _usedHint,
      record: record,
      pointsAwarded: score - before,
      hasNext: level.number < levels.length,
    );
    _phase = EscapePhase.exiting;
    notifyListeners();
  }

  @override
  void onRestart() {
    _levelsSolved = 0;
    _starsEarned = 0;
    _level = null;
    _board = null;
    _history.clear();
    _completion = null;
    _hint = null;
    _hintToken++;
    _hintPending = false;
    _phase = EscapePhase.map;
  }
}
