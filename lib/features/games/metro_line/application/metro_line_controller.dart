import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/metro_line_state.dart';

/// Bir dokunuşun sonucu.
enum MetroLineTapResult {
  /// Tren tahtadan çıktı.
  cleared,

  /// Önü kapalıydı: can gitti.
  blocked,

  /// Oyun oynanmıyor ya da böyle bir tren yok.
  ignored,
}

/// Metro Hattı — tıkanmış bir depoyu doğru sırayla boşaltma bulmacası.
///
/// Tahtada birbirinin içinden kıvrılan metro hatları var; her hattın
/// başında bir ok, trenin hangi yönden çıkacağını söylüyor. Bir trene
/// dokununca, **başının önündeki koridor kenara kadar boşsa** tren
/// raydan çıkar ve arkasında yer açar. Kapalıysa dokunuş bir can götürür.
///
/// Oyunun tamamı sıralama üzerine: hangi treni önce çıkarırsan hangi
/// koridoru açtığın. Bulmacanın her zaman bir çözümü vardır — üretim
/// yöntemi için [generateMetroLinePuzzle].
class MetroLineController extends JourneyGameController {
  MetroLineController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    super.discovery,
    Random? random,
    super.tick = AppConstants.playTick,
    super.session,
  }) : _random = random ?? Random(),
       super(gameId: id) {
    _loadLevel(1);
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'metro_line';

  /// Vagon başına puan. Uzun tren hem daha çok yer kaplar hem de çıkarması
  /// daha çok koridor açar; puanı vagona bağlamak bunu ödüllendiriyor.
  static const int pointsPerCar = 6;

  /// Tahtayı tamamen boşaltmanın primi. Seviye ilerledikçe büyür.
  static const int levelClearBase = 40;
  static const int levelClearPerLevel = 10;

  final Random _random;

  int _level = 1;
  late MetroLinePuzzle _puzzle;
  late List<MetroLineTrain> _remaining;
  int _hearts = metroLineHearts;
  int _clearedTrains = 0;
  int _completedLevels = 0;
  int _wrongTaps = 0;

  /// Tahtadan en son çıkan tren — ekran bunu kayarken çizer.
  MetroLineTrain? _departing;
  int _departurePulse = 0;

  /// İpucunun işaret ettiği tren; ekran onu vurgular.
  int? _hintTrainId;

  int get level => _level;
  MetroLinePuzzle get puzzle => _puzzle;
  int get size => _puzzle.size;

  /// Tahtada duran trenler.
  List<MetroLineTrain> get trains => List<MetroLineTrain>.unmodifiable(
    _remaining,
  );

  int get hearts => _hearts;
  int get clearedTrains => _clearedTrains;
  int get completedLevels => _completedLevels;
  int get wrongTaps => _wrongTaps;

  MetroLineTrain? get departing => _departing;

  /// Her çıkışta artar; ekran yeni bir kayma animasyonu başlatmak için
  /// buna bakar.
  int get departurePulse => _departurePulse;

  int? get hintTrainId => _hintTrainId;

  /// Bu seviyede kaç tren kaldı / başta kaç vardı.
  int get trainsLeft => _remaining.length;
  int get trainsInLevel => _puzzle.trains.length;

  /// Hücrede hangi tren var? Boşsa null.
  MetroLineTrain? trainAt(Point<int> cell) {
    for (final train in _remaining) {
      if (train.cells.contains(cell)) return train;
    }
    return null;
  }

  /// Bu tren şu anda çıkabilir mi?
  ///
  /// Koşul tek: başının önündeki koridorda başka tren olmaması. Trenin
  /// kendi vagonları koridora hiç girmez (üretici buna izin vermiyor), o
  /// yüzden "kendisi hariç" gibi bir ayıklamaya gerek yok.
  bool canExit(MetroLineTrain train) {
    for (final cell in train.corridor(_puzzle.size)) {
      if (trainAt(cell) != null) return false;
    }
    return true;
  }

  /// Şu anda çıkabilecek bir tren — ipucu bunu gösterir.
  ///
  /// Çözülebilirlik garantisi sayesinde tahta boş değilse burada her zaman
  /// en az bir tren bulunur.
  MetroLineTrain? solvableTrain() {
    for (final train in _remaining) {
      if (canExit(train)) return train;
    }
    return null;
  }

  /// İpucu iste: çıkabilecek bir treni işaretler.
  void requestHint() {
    if (status != GameStatus.playing) return;
    _hintTrainId = solvableTrain()?.id;
    notifyListeners();
  }

  void clearHint() {
    if (_hintTrainId == null) return;
    _hintTrainId = null;
    notifyListeners();
  }

  MetroLineTapResult tap(int trainId) {
    if (status != GameStatus.playing) return MetroLineTapResult.ignored;

    final index = _remaining.indexWhere((t) => t.id == trainId);
    if (index < 0) return MetroLineTapResult.ignored;

    final train = _remaining[index];
    _hintTrainId = null;

    if (!canExit(train)) {
      _wrongTaps++;
      _hearts--;
      if (_hearts <= 0) {
        _hearts = 0;
        notifyListeners();
        endGame();
        return MetroLineTapResult.blocked;
      }
      notifyListeners();
      return MetroLineTapResult.blocked;
    }

    _remaining = <MetroLineTrain>[..._remaining]..removeAt(index);
    _departing = train;
    _departurePulse++;
    _clearedTrains++;
    addScore(pointsPerCar * train.carCount);
    markStationProgress();

    if (_remaining.isEmpty) {
      _completedLevels++;
      addScore(levelClearBase + levelClearPerLevel * _level);
      _loadLevel(_level + 1);
    }

    notifyListeners();
    return MetroLineTapResult.cleared;
  }

  @override
  void onRestart() {
    _level = 1;
    _clearedTrains = 0;
    _completedLevels = 0;
    _wrongTaps = 0;
    _departing = null;
    _loadLevel(1);
  }

  void _loadLevel(int level) {
    _level = level;
    final plan = MetroLineLevelPlan.forLevel(level);
    _puzzle = generateMetroLinePuzzle(
      size: plan.size,
      desiredTrains: plan.trains,
      random: _random,
    );
    _remaining = List<MetroLineTrain>.of(_puzzle.trains);
    // Canlar seviyeye ait: yeni tahta tam hakla başlar.
    _hearts = metroLineHearts;
    _hintTrainId = null;
  }

  @visibleForTesting
  void debugSetPuzzle(MetroLinePuzzle puzzle) {
    _puzzle = puzzle;
    _remaining = List<MetroLineTrain>.of(puzzle.trains);
    _hintTrainId = null;
    _departing = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetHearts(int hearts) {
    _hearts = hearts;
    notifyListeners();
  }
}
