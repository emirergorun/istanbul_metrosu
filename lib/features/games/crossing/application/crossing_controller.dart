import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../journey/models/station.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/crossing_state.dart';

/// Karşıdan Karşıya — oyuncu peronlar ve raylar arasında yukarı doğru ilerler.
///
/// Oyunu **yalnızca** bir trene çarpmak bitirir. Beklemek serbest: kamera
/// kendi başına kaymaz, arkadan kovalayan bir şey yoktur. Bu bilinçli bir
/// karar — Yolcu Topla'da duvar ölümünü kaldırmakla aynı sebep: oyuncu
/// zaten yolculuk saatine karşı oynuyor, beklemek ona puan kaybettiriyor.
class CrossingController extends JourneyGameController {
  CrossingController({
    required super.journey,
    required super.recordToBeat,
    required List<MetroLine> lines,
    super.store,
    super.discovery,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
    super.session,
  }) : _random = random ?? Random(),
       _lines = List<MetroLine>.of(lines),
       super(gameId: id, maxFrameSeconds: _maxFrameSeconds) {
    _bag = CrossingLineBag(_lines, _random);
    _layout();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'crossing';

  /// Diğer gerçek zamanlı oyunlarla aynı kırpma: tek karede en fazla bu
  /// kadar süre sayılır, yoksa uzun bir donmadan sonra tren oyuncunun
  /// içinden geçip gider.
  static const double _maxFrameSeconds = 0.05;

  /// Testteki bir karenin nominal süresi.
  static const double _nominalFrameSeconds = 1 / 60;

  /// Kameranın oyuncuya yetişme hızı. Ray Değiştir'deki ray geçişiyle aynı
  /// üstel yumuşatma: ışınlanma yok, takip var.
  static const double _cameraRate = 11.0;

  final Random _random;
  final List<MetroLine> _lines;
  late CrossingLineBag _bag;

  /// Saklanan satırlar, indeksleri artan sırada.
  final List<CrossingRow> _rows = <CrossingRow>[];

  int _column = crossingColumns ~/ 2;
  int _row = 0;
  int _fromColumn = crossingColumns ~/ 2;
  int _fromRow = 0;
  int _maxRow = 0;
  int _tracksCrossed = 0;
  int _nextTrainId = 0;
  int _trackStreak = 0;

  bool _hopping = false;
  double _hopElapsed = 0;
  CrossingDirection _facing = CrossingDirection.forward;
  CrossingDirection? _queued;
  double _cameraRow = 0;
  bool _crashed = false;

  /// Ekrandaki satırlar; en alttaki başta.
  List<CrossingRow> get rows => List<CrossingRow>.unmodifiable(_rows);

  CrossingRow? rowAt(int index) {
    for (final row in _rows) {
      if (row.index == index) return row;
    }
    return null;
  }

  int get column => _column;
  int get row => _row;

  /// Ulaşılan en ileri satır — puanın ve zorluğun dayandığı sayı.
  int get rowsCrossed => _maxRow;
  int get tracksCrossed => _tracksCrossed;
  CrossingDirection get facing => _facing;
  bool get isHopping => _hopping;

  /// Trene çarpılarak mı bitti? Sonuç paneli metnini buna göre seçer.
  bool get crashed => _crashed;

  /// Şu anki zıplamanın ne kadarı geçti (0..1). Zıplanmıyorsa 1.
  double get hopProgress =>
      _hopping ? (_hopElapsed / crossingHopSeconds).clamp(0.0, 1.0) : 1.0;

  /// Oyuncunun çizilecek sütunu — hücreden hücreye kayar.
  double get visualColumn =>
      _fromColumn + (_column - _fromColumn) * hopProgress;

  /// Oyuncunun çizilecek satırı.
  double get visualRow => _fromRow + (_row - _fromRow) * hopProgress;

  /// Kameranın odaklandığı satır; oyuncunun biraz gerisinden gelir.
  double get cameraRow => _cameraRow;

  /// Oyuncunun geri gidebileceği en alt satır.
  ///
  /// Sınırsız geri gitmek yok: ekranın altından çıkan satırlar siliniyor,
  /// dönülecek bir yer kalmıyor. Oyuncu yine de üç satır geri çekilip
  /// bir trenin geçmesini bekleyebilir — kaçışın tamamı bu.
  int get backLimit => max(0, _maxRow - crossingPlayerViewRow);

  /// Çarpışma hangi hücreden hesaplanır.
  ///
  /// Zıplamanın ilk yarısında oyuncu hâlâ çıktığı hücrede sayılır, ikinci
  /// yarısında vardığı hücrede. Aksi hâlde raya adım atar atmaz, daha
  /// hücrenin kenarındayken ezilmek mümkün olurdu.
  int get _hitRow => hopProgress < 0.5 ? _fromRow : _row;
  int get _hitColumn => hopProgress < 0.5 ? _fromColumn : _column;

  @override
  void onRestart() {
    _rows.clear();
    _bag = CrossingLineBag(_lines, _random);
    _column = crossingColumns ~/ 2;
    _row = 0;
    _fromColumn = _column;
    _fromRow = 0;
    _maxRow = 0;
    _tracksCrossed = 0;
    _nextTrainId = 0;
    _trackStreak = 0;
    _hopping = false;
    _hopElapsed = 0;
    _facing = CrossingDirection.forward;
    _queued = null;
    _cameraRow = 0;
    _crashed = false;
    _layout();
  }

  /// Bir hamle iste. Zıplama sürerken gelen istek kuyruğa alınır.
  ///
  /// Kuyruk tek adımlık: hızlı arka arkaya dokunuş zincirinin kopmaması
  /// için şart, ama daha derin bir kuyruk oyuncunun dokunmayı bıraktıktan
  /// sonra da yürümesi demek olurdu.
  void move(CrossingDirection direction) {
    if (status != GameStatus.playing) return;
    if (_hopping) {
      _queued = direction;
      return;
    }
    _startHop(direction);
  }

  @override
  void onTick(double dt) {
    _advanceHop(dt);
    _advanceTraffic(dt);
    _cameraRow += (_row - _cameraRow) * (1 - exp(-_cameraRate * dt));
    _checkCollision();
  }

  /// Testte gerçek zamanlayıcıyı beklemeden nominal kareler ilerletir.
  @visibleForTesting
  void step([int frames = 1]) {
    for (var i = 0; i < frames; i++) {
      if (status != GameStatus.playing) return;
      advance(_nominalFrameSeconds);
    }
  }

  /// Testte oyuncuyu doğrudan bir hücreye koyar.
  @visibleForTesting
  void debugSetPlayer(int column, int row) {
    _column = column;
    _fromColumn = column;
    _row = row;
    _fromRow = row;
    _maxRow = max(_maxRow, row);
    _hopping = false;
    _hopElapsed = 0;
    _cameraRow = row.toDouble();
    _layout();
    notifyListeners();
  }

  /// Testte bir satıra istenen treni koyar.
  @visibleForTesting
  void debugSetTrains(int rowIndex, List<CrossingTrain> trains) {
    final row = rowAt(rowIndex);
    if (row == null) return;
    row.trains
      ..clear()
      ..addAll(trains);
    notifyListeners();
  }

  /// Testte tek bir tren üretir.
  @visibleForTesting
  CrossingTrain debugTrain({
    required double x,
    int cars = 2,
    MetroLine? line,
  }) => CrossingTrain(
    id: _nextTrainId++,
    line: line ?? _lines.first,
    cars: cars,
    x: x,
  );

  void _advanceHop(double dt) {
    if (!_hopping) {
      // Duruyorken kuyrukta bekleyen bir istek varsa hemen başlat.
      final queued = _queued;
      if (queued != null) {
        _queued = null;
        _startHop(queued);
      }
      if (!_hopping) return;
    }
    _hopElapsed += dt;

    // `while`: kırpılmış da olsa uzun bir kare iki kısa zıplamayı birden
    // hak edebilir; oyuncu verdiği komutun yutulduğunu hissetmesin.
    var guard = 0;
    while (_hopping && _hopElapsed >= crossingHopSeconds && guard++ < 4) {
      final carry = _hopElapsed - crossingHopSeconds;
      _finishHop();
      if (status != GameStatus.playing) return;
      final queued = _queued;
      _queued = null;
      if (queued == null) break;
      _startHop(queued);
      if (_hopping) _hopElapsed = carry;
    }
  }

  void _startHop(CrossingDirection direction) {
    final delta = direction.delta;
    final column = (_column + delta.x).clamp(0, crossingColumns - 1);
    final row = max(_row + delta.y, backLimit);
    _facing = direction;
    if (column == _column && row == _row) {
      // Kenara dayandı: hamle yok ama figür o yöne dönsün.
      notifyListeners();
      return;
    }
    _fromColumn = _column;
    _fromRow = _row;
    _column = column;
    _row = row;
    _hopping = true;
    _hopElapsed = 0;
    _layout();
    notifyListeners();
  }

  void _finishHop() {
    _hopping = false;
    _hopElapsed = 0;
    _fromColumn = _column;
    _fromRow = _row;
    if (_row <= _maxRow) return;

    // Puan yalnızca **yeni** en ileri satırda yazılır: ileri geri gidip
    // aynı satırı defalarca saymak yok.
    _maxRow = _row;
    final arrived = rowAt(_row);
    final isTrack = arrived?.isTrack ?? false;
    addScore(isTrack ? crossingTrackPoints : crossingPlatformPoints);
    if (isTrack) {
      _tracksCrossed++;
      if (_tracksCrossed % crossingRowsPerStation == 0) markStationProgress();
    }
    _layout();
  }

  void _advanceTraffic(double dt) {
    final config = CrossingConfig.forRows(_maxRow);
    for (final row in _rows) {
      if (!row.isTrack) continue;
      final step = row.speed * dt;
      for (var i = 0; i < row.trains.length; i++) {
        final train = row.trains[i];
        row.trains[i] = train.copyWith(
          x: row.toRight ? train.x + step : train.x - step,
        );
      }
      row.trains.removeWhere(
        (CrossingTrain t) => row.trackPosition(t) > crossingColumns,
      );
      _spawnIfDue(row, config);
    }
  }

  void _checkCollision() {
    if (status != GameStatus.playing) return;
    final row = rowAt(_hitRow);
    if (row == null || !row.isTrack) return;
    if (!row.hits(_hitColumn)) return;
    _crashed = true;
    endGame();
  }

  /// Eksik satırları üretir, geride kalanları siler.
  void _layout() {
    _pruneRows();
    _ensureRows();
  }

  void _pruneRows() {
    final lowest = backLimit - 1;
    _rows.removeWhere((CrossingRow row) => row.index < lowest);
  }

  void _ensureRows() {
    final lowest = backLimit - 1;
    final highest = _row + crossingVisibleRows;
    if (_rows.isEmpty) {
      for (var index = lowest; index <= highest; index++) {
        _rows.add(_buildRow(index));
      }
      return;
    }
    for (var index = _rows.last.index + 1; index <= highest; index++) {
      _rows.add(_buildRow(index));
    }
  }

  CrossingRow _buildRow(int index) {
    if (index < crossingStartSafeRows) {
      _trackStreak = 0;
      return CrossingRow.platform(index);
    }
    final config = CrossingConfig.forRows(_maxRow);
    final canStack = _trackStreak < crossingMaxTrackStreak;
    if (!canStack || _random.nextDouble() >= config.trackChance) {
      _trackStreak = 0;
      return CrossingRow.platform(index);
    }
    _trackStreak++;
    final row = CrossingRow.track(
      index,
      speed:
          config.minSpeed +
          _random.nextDouble() * (config.maxSpeed - config.minSpeed),
      toRight: _random.nextBool(),
      nextGap: 0,
    );
    _fillRow(row, config);
    return row;
  }

  /// Yeni satırı trenlerle doldurur.
  ///
  /// Satır ekrana boş girseydi oyuncu "burası güvenli" diye okuyup tam da
  /// ilk tren belirdiğinde üzerinde olurdu. Bu yüzden satır daha
  /// görünmeden trafiği kurulmuş oluyor; ilk trenin yeri rastgele, arkası
  /// normal boşluk kuralıyla diziliyor.
  void _fillRow(CrossingRow row, CrossingConfig config) {
    var head = _random.nextDouble() * (crossingColumns + 1);
    for (var guard = 0; guard < 12; guard++) {
      final cars = _cars(config);
      final position = head - crossingTrainLengthCells(cars);
      if (position < -crossingColumns) break;
      row.trains.add(_train(row, position, cars));
      head = position - _gapFor(row, config);
    }
    row.nextGap = _gapFor(row, config);
  }

  void _spawnIfDue(CrossingRow row, CrossingConfig config) {
    // Rastgelelik yalnızca gerçekten tren doğarken tüketilir: her karede
    // zar atmak tohumlu koşuyu kare sayısına bağımlı kılardı ve botla
    // ölçülen denge tekrarlanamaz olurdu.
    if (row.trains.isNotEmpty) {
      // En geri trenin ön ucu ekrana girmeden yenisi kuyruğa alınmaz; aksi
      // hâlde satır görünmeyen bir tren dizisiyle dolar.
      final rearEntered = row.trains
          .map((CrossingTrain t) => row.trackPosition(t) + t.length)
          .reduce(min);
      if (rearEntered < 0) return;
    }

    final cars = _cars(config);
    final length = crossingTrainLengthCells(cars);
    var position = -length;
    if (row.trains.isNotEmpty) {
      final rear = row.trains
          .map((CrossingTrain t) => row.trackPosition(t))
          .reduce(min);
      position = rear - row.nextGap - length;
      // Tren her hâlükârda ekran dışında doğar; boşluk büyür, küçülmez.
      if (position > -length) position = -length;
    }
    row.trains.add(_train(row, position, cars));
    row.nextGap = _gapFor(row, config);
  }

  /// Trenin vagon sayısı: en az iki, en fazla zorluğun izin verdiği kadar.
  int _cars(CrossingConfig config) => 2 + _random.nextInt(config.maxCars - 1);

  CrossingTrain _train(CrossingRow row, double position, int cars) =>
      CrossingTrain(
        id: _nextTrainId++,
        line: _bag.next(),
        cars: cars,
        x: row.leftEdgeFor(position, cars),
      );

  /// İki tren arasındaki boşluk (hücre).
  ///
  /// Taban, satırın hızında [CrossingConfig.gapSeconds] saniyelik bir
  /// pencereye karşılık gelir — yani her satır geçilebilir. Üzerine
  /// rastgele pay: trafik metronomik olmasın, oyuncu ritmi ezberleyip
  /// bakmadan geçemesin.
  double _gapFor(CrossingRow row, CrossingConfig config) =>
      row.speed * config.gapSeconds * (1 + _random.nextDouble() * 0.9);
}
