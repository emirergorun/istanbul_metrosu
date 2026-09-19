import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/train_snake_state.dart';

class TrainSnakeController extends JourneyGameController {
  TrainSnakeController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
  }) : _random = random ?? Random(),
       super(gameId: id, maxFrameSeconds: _maxFrameSeconds) {
    _body = _initialBody();
    _previousBody = _body;
    _passenger = _spawnPassenger();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'train_snake';

  /// Ray Değiştir/Ray Uçuşu'ndaki aynı düzeltme: gerçek geçen süre ölçülür,
  /// `Timer`'ın düzenli tetiklendiği varsayılmaz; tek karede en fazla bu
  /// kadar süre sayılır.
  static const double _maxFrameSeconds = 0.05;

  /// Trenin bir hücre ilerlemesi kaç saniye sürer. Yolcu toplandıkça çok
  /// hafifçe azalır (istenen: "oyun çok hafif hızlansın"), bir tabanın
  /// altına inmez.
  static const double _baseStepSeconds = 0.22;
  static const double _minStepSeconds = 0.11;
  static const double _stepSpeedupPerPassenger = 0.0035;

  final Random _random;

  late List<Point<int>> _body;
  late List<Point<int>> _previousBody;
  SnakeDirection _direction = SnakeDirection.right;
  SnakeDirection? _queuedDirection;
  late Point<int> _passenger;
  int _passengersCollected = 0;
  double _stepElapsed = 0;

  /// Baştan kuyruğa tüm vagonlar. İlk eleman lokomotif (baş).
  List<Point<int>> get body => List<Point<int>>.unmodifiable(_body);

  /// Bir önceki adımdaki gövde — ekran katmanı bunu [body] ile karıştırıp
  /// (bkz. [stepProgress]) treni hücre hücre değil kayarak çizer.
  ///
  /// `previousBody[i-1] == body[i]` her zaman doğrudur (baş hariç): yeni
  /// gövde, eski gövdenin başına bir hücre eklenip (büyümüyorsa) kuyruktan
  /// bir hücre çıkarılarak kurulur. Bu sayede her vagon "eskiden nerede
  /// olduğu"ndan "şimdi nerede olduğu"na doğru düzgün bir çizgide kayar.
  List<Point<int>> get previousBody => List<Point<int>>.unmodifiable(
    _previousBody,
  );

  /// Şu anki adımın ne kadarının geçtiği, 0..1. Ekran katmanı [previousBody]
  /// ile [body] arasında bu orana göre ara değer çizer.
  double get stepProgress => (_stepElapsed / _stepSeconds).clamp(0.0, 1.0);

  Point<int> get passenger => _passenger;
  int get passengersCollected => _passengersCollected;
  int get level => trainSnakeLevelForPassengers(_passengersCollected);
  String get lineLabel => trainSnakeLabelForLevel(level);

  /// Şu anki hatta bu yolcuyla kaçıncı yolcu toplandı (0..2).
  int get passengersInLevel =>
      _passengersCollected % trainSnakePassengersPerLevel;

  double get _stepSeconds => max(
    _minStepSeconds,
    _baseStepSeconds - _passengersCollected * _stepSpeedupPerPassenger,
  );

  @visibleForTesting
  Point<int> get head => _body.first;

  List<Point<int>> _initialBody() {
    final y = trainSnakeRows ~/ 2;
    final startX = trainSnakeColumns ~/ 3;
    return <Point<int>>[
      for (var i = 0; i < trainSnakeStartLength; i++) Point<int>(startX - i, y),
    ];
  }

  @override
  void onRestart() {
    _body = _initialBody();
    _previousBody = _body;
    _direction = SnakeDirection.right;
    _queuedDirection = null;
    _passengersCollected = 0;
    _stepElapsed = 0;
    _passenger = _spawnPassenger();
  }

  /// Yön değişikliğini kuyruğa alır; bir sonraki adımda uygulanır.
  ///
  /// Anında uygulanmaz: aynı karede iki kez yön değiştirilirse (hızlı art
  /// arda dokunma/tuş) tren, henüz uygulanmamış bir hedefe göre "tam ters"
  /// sayılıp kendi boynuna çarpmasın diye kuyruktaki **son istek** referans
  /// alınır.
  void turn(SnakeDirection next) {
    if (status != GameStatus.playing) return;
    final reference = _queuedDirection ?? _direction;
    if (next.isOppositeOf(reference)) return;
    _queuedDirection = next;
  }

  @visibleForTesting
  void debugSetBody(List<Point<int>> body, {SnakeDirection? direction}) {
    _body = List<Point<int>>.of(body);
    _previousBody = _body;
    if (direction != null) _direction = direction;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetPassenger(Point<int> passenger) {
    _passenger = passenger;
    notifyListeners();
  }

  /// Testte gerçek zamanlayıcıyı beklemeden nominal adımlar ilerletir.
  @visibleForTesting
  void step([int steps = 1]) {
    for (var i = 0; i < steps; i++) {
      if (status != GameStatus.playing) return;
      _advanceStep();
    }
  }

  @override
  void onTick(double dt) {
    _stepElapsed += dt;
    final interval = _stepSeconds;
    // `while`: uzun bir donmadan sonra (kırpılmış da olsa) birikmiş süre
    // birden fazla adımı hak edebilir; tren donma öncesi hıza göre "kayıp"
    // hissettirmesin.
    while (_stepElapsed >= interval) {
      _stepElapsed -= interval;
      _advanceStep();
      if (status != GameStatus.playing) return;
    }
  }

  void _advanceStep() {
    _previousBody = _body;
    if (_queuedDirection != null) {
      _direction = _queuedDirection!;
      _queuedDirection = null;
    }

    final delta = _direction.delta;
    final next = Point<int>(head.x + delta.x, head.y + delta.y);

    if (next.x < 0 ||
        next.x >= trainSnakeColumns ||
        next.y < 0 ||
        next.y >= trainSnakeRows) {
      endGame();
      return;
    }

    final eating = next == _passenger;
    // Büyümüyorsa kuyruk bu adımda tam da bu hücreyi boşaltacağı için
    // kendi kuyruğuna değmek çarpışma sayılmaz — klasik yılan kuralı.
    final bodyForCollision = eating
        ? _body
        : _body.sublist(0, _body.length - 1);
    if (bodyForCollision.contains(next)) {
      endGame();
      return;
    }

    _body = <Point<int>>[next, ..._body];
    if (eating) {
      _passengersCollected++;
      addScore(10 * level);
      markStationProgress();
      _passenger = _spawnPassenger();
    } else {
      _body = _body.sublist(0, _body.length - 1);
    }
    notifyListeners();
  }

  Point<int> _spawnPassenger() {
    // Işıklı sonsuz döngü riski yok: ızgara 11×17 = 187 hücre, tren en
    // kötü ihtimalle bunun küçük bir kısmını kaplar (oyun ondan önce
    // biter); rastgele deneme pratikte tek seferde bulur.
    while (true) {
      final candidate = Point<int>(
        _random.nextInt(trainSnakeColumns),
        _random.nextInt(trainSnakeRows),
      );
      if (!_body.contains(candidate)) return candidate;
    }
  }
}
