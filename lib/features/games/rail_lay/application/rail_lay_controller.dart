import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../data/rail_lay_levels.dart';
import '../domain/rail_lay_solver.dart';
import '../domain/rail_lay_state.dart';

/// Ray Döşe — metro duvara kadar kayar, geçtiği her kareye ray döşer.
///
/// Tünele Kaç gibi **bölümlü** ve kaybetmesiz: `gameOver` yolu yok, tek
/// final varış. Puan yalnızca biten bölümden yazılır; yarım kalan bölüm,
/// baştan alınan boyama ya da ileri geri kayışlar puan getirmez.
class RailLayController extends JourneyGameController {
  RailLayController({
    required super.journey,
    required super.recordToBeat,
    int startLevel = 1,
    super.store,
    super.discovery,
    super.tick = const Duration(milliseconds: 16),
    super.session,
  }) : super(gameId: id, maxFrameSeconds: _maxFrameSeconds) {
    _load(RailLayLevels.byNumber(max(1, startLevel)));
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'rail_lay';

  /// Diğer gerçek zamanlı oyunlarla aynı kırpma: uzun bir donmadan sonra
  /// metro tek karede tahtanın öbür ucuna ışınlanmasın.
  static const double _maxFrameSeconds = 0.05;

  /// Testteki bir karenin nominal süresi.
  static const double _nominalFrameSeconds = 1 / 60;

  late RailLayLevel _level;

  /// Bölümün çözücüsü: anında çıkmaz uyarısı için. Tahta çözücünün
  /// maskesine sığmıyorsa `null` ve sezgisel yoklamaya düşülür.
  RailLaySolver? _solver;
  late List<int> _paint;
  late Point<int> _position;
  int _paintedCount = 0;

  /// Sürmekte olan kayışın geçeceği kareler; boşsa metro duruyor.
  List<Point<int>> _path = const <Point<int>>[];
  double _slideDistance = 0;
  RailLayDirection _facing = RailLayDirection.right;
  RailLayDirection? _queued;

  /// Bölüm artık bitirilemiyor (çözücünün kesin cevabı).
  ///
  /// Geri dönüşsüz: döşenen kare silinmediği için ölü bir durumdan canlıya
  /// dönülemez. Bu yüzden çözücü bir kez "ölü" dedikten sonra bir daha
  /// sorulmuyor.
  bool _dead = false;

  /// Çıkmaza girdikten sonra biten kayış sayısı.
  int _movesSinceDead = 0;
  double _celebration = 0;
  int _levelsCleared = 0;
  int _lastAward = 0;
  int _clearPulse = 0;
  int _bumpPulse = 0;
  int _moves = 0;

  RailLayLevel get level => _level;
  int get levelNumber => _level.number;
  Point<int> get position => _position;
  RailLayDirection get facing => _facing;
  bool get isSliding => _path.isNotEmpty;
  int get paintedCount => _paintedCount;
  int get openCount => _level.openCount;
  int get moves => _moves;

  /// Bu oturumda bitirilen bölüm sayısı.
  int get levelsCleared => _levelsCleared;

  /// Son biten bölümün yolculuğa kattığı puan; kutlama yazısı bunu
  /// gösterir. Ham sayı (açık kare) gösterilseydi skor tablosuyla tutmazdı.
  int get lastAward => _lastAward;

  /// Her biten bölümde artar — ekran ses ve titreşimi buna bağlar.
  int get clearPulse => _clearPulse;

  /// Duvara dayalı yöne kaydırıldığında artar — kısa bir "tık" için.
  int get bumpPulse => _bumpPulse;

  /// "Sıkıştın" uyarısı gösterilsin mi?
  ///
  /// Bölüm çıkmaza girdiği an değil, ondan sonra [railLayStuckHintMoves]
  /// hamle yapılınca: oyuncu önce kendisi fark etme şansı bulsun.
  bool get isStuck => _dead && _movesSinceDead >= railLayStuckHintMoves;

  /// Bölüm artık bitirilemiyor mu (uyarı gecikmesinden bağımsız)?
  @visibleForTesting
  bool get isDead => _dead;

  /// Bölüm bitti, kutlama sürüyor; girdi alınmıyor.
  bool get isCelebrating => _celebration > 0;

  /// Kutlamanın ne kadarı geçti (0..1).
  double get celebrationProgress =>
      isCelebrating ? 1 - _celebration / railLayCelebrateSeconds : 0;

  /// Karenin döşeme bitleri; 0 döşenmemiş.
  int paintAt(Point<int> cell) => _paint[_level.indexOf(cell)];

  /// Metronun çizileceği konum (hücre cinsinden, kesirli).
  Offset get visualPosition {
    if (_path.isEmpty) {
      return Offset(_position.x.toDouble(), _position.y.toDouble());
    }
    final delta = _facing.delta;
    final travelled = min(_slideDistance, _path.length.toDouble());
    return Offset(
      _position.x + delta.x * travelled,
      _position.y + delta.y * travelled,
    );
  }

  /// Motorun "baştan" çağrısı (duraklatma paneli) mevcut bölümü sıfırlar.
  ///
  /// Kutlama sürerken gelirse bölüm zaten bitmiş ve puanı yazılmıştır;
  /// aynı bölümü yeniden açmak onu ikinci kez puanlatırdı. O durumda
  /// sıradaki bölüme geçilir.
  @override
  void onRestart() =>
      _load(isCelebrating ? RailLayLevels.byNumber(_level.number + 1) : _level);

  /// Bölümü baştan alır: döşeme sıfırlanır, bölüm aynı kalır.
  ///
  /// Puan zaten yalnızca bölüm bitince yazıldığı için baştan almak hiçbir
  /// şey kaybettirmez; kaybedilen tek şey süre.
  void restartLevel() {
    if (status != GameStatus.playing || isCelebrating) return;
    _load(_level);
    notifyListeners();
  }

  /// Kaydırma. Kayış sürerken gelen istek tek adımlık kuyruğa alınır.
  void swipe(RailLayDirection direction) {
    if (status != GameStatus.playing || isCelebrating) return;
    if (_path.isNotEmpty) {
      _queued = direction;
      return;
    }
    _startSlide(direction);
  }

  @override
  void onTick(double dt) {
    if (isCelebrating) {
      _celebration -= dt;
      if (_celebration <= 0) {
        _celebration = 0;
        _load(RailLayLevels.byNumber(_level.number + 1));
      }
      notifyListeners();
      return;
    }
    if (_path.isEmpty) return;

    _slideDistance += railLaySlideCellsPerSecond * dt;
    // Kare, metronun ortası üzerine geldiğinde döşenir: hepsi birden değil,
    // metro geçtikçe birer birer.
    final reached = min(_path.length, (_slideDistance + 0.5).floor());
    for (var i = 0; i < reached; i++) {
      _paintCell(_path[i], _facing.axisBit);
    }
    if (_slideDistance >= _path.length) _finishSlide();
    notifyListeners();
  }

  /// Testte gerçek zamanlayıcıyı beklemeden nominal kareler ilerletir.
  @visibleForTesting
  void step([int frames = 1]) {
    for (var i = 0; i < frames; i++) {
      if (status != GameStatus.playing) return;
      advance(_nominalFrameSeconds);
    }
  }

  /// Testte elle kurulmuş bir bölümü yükler.
  @visibleForTesting
  void debugLoadLevel(RailLayLevel level) {
    _load(level);
    notifyListeners();
  }

  void _load(RailLayLevel level) {
    _level = level;
    _solver = level.openCount <= RailLaySolver.maxOpenCells
        ? RailLaySolver(level)
        : null;
    _paint = List<int>.filled(level.width * level.height, 0);
    _paintedCount = 0;
    _position = level.start;
    _path = const <Point<int>>[];
    _slideDistance = 0;
    _queued = null;
    _dead = false;
    _movesSinceDead = 0;
    _celebration = 0;
    _moves = 0;
    _paintCell(level.start, railLayStation);
  }

  void _startSlide(RailLayDirection direction) {
    _facing = direction;
    final path = _level.slide(_position, direction);
    if (path.isEmpty) {
      _bumpPulse++;
      notifyListeners();
      return;
    }
    _path = path;
    _slideDistance = 0;
    _moves++;
    // Metro çıktığı kareye de o eksende ray döşer; yoksa her duruşta hat
    // kopuk görünürdü.
    _paintCell(_position, direction.axisBit);
    notifyListeners();
  }

  void _finishSlide() {
    for (final cell in _path) {
      _paintCell(cell, _facing.axisBit);
    }
    _position = _path.last;
    _path = const <Point<int>>[];
    _slideDistance = 0;

    if (_paintedCount == _level.openCount) {
      _complete();
      return;
    }
    if (_dead) {
      _movesSinceDead++;
    } else if (!_canStillFinish()) {
      _dead = true;
      _movesSinceDead = 0;
    }

    final queued = _queued;
    _queued = null;
    if (queued != null) _startSlide(queued);
  }

  void _complete() {
    _queued = null;
    _levelsCleared++;
    _clearPulse++;
    // Ham puan: açık kare (iş) + en kısa çözümün hamlesi (düşünme); bkz.
    // [RailLayLevel.points].
    final before = score;
    addScore(_level.points);
    _lastAward = score - before;
    markStationProgress();
    _celebration = railLayCelebrateSeconds;
    store?.saveRailLayLevel(_level.number + 1);
  }

  /// Bölüm hâlâ bitirilebilir mi?
  ///
  /// Önce çözücü sorulur: kesin cevap verirse o geçerli — tuzağa düşen
  /// oyuncu bunu **hemen** öğrenir (kullanıcı kararı). Çözücü sınırını
  /// aşarsa ("bilinmiyor") kaba yoklamaya düşülür: kalan karelerden biri
  /// hiçbir kayışla kapsanamıyorsa kesin sıkışılmıştır.
  bool _canStillFinish() {
    final exact = _solver?.canFinish(_position, _solver!.maskFromPaint(_paint));
    if (exact != null) return exact;

    final reachable = _level.reachableCells(_position);
    for (var i = 0; i < _paint.length; i++) {
      if (_level.open[i] && _paint[i] == 0 && !reachable.contains(i)) {
        return false;
      }
    }
    return true;
  }

  void _paintCell(Point<int> cell, int bits) {
    final index = _level.indexOf(cell);
    if (_paint[index] == 0) _paintedCount++;
    _paint[index] |= bits;
  }
}
