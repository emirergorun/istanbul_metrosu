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
    super.discovery,
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

  /// Tren ilk yön girdisine kadar bekler.
  ///
  /// Önce oyun açılır açılmaz hareket ediyordu: ızgara 11 sütun, tren
  /// x=3'ten sağa doğru başlıyor ve adım aralığı 0,22 saniye. Yani sağ
  /// duvara **1,54 saniyede** varıyordu. Oyuncu ekranı görüp parmağını
  /// kaldırmadan oyun bitiyor, skor 0 kalıyordu.
  ///
  /// Beklemek yılan türünün standardı ve yolculuk saatini de durdurmuyor
  /// — oyun başlamış sayılıyor, yalnızca tren duruyor.
  bool _awaitingFirstInput = true;

  /// Tren hâlâ ilk girdiyi mi bekliyor? Ekran ipucunu buna göre gösterir.
  bool get isAwaitingFirstInput => _awaitingFirstInput;

  /// Oyun kazanılarak mı bitti?
  ///
  /// Yolculuk motorunun üç finali var: varış (süre doldu), oyun sonu
  /// (çarpma) ve bu. Motora yeni bir durum eklemek altı oyunu birden
  /// ilgilendirirdi; zafer burada bir bayrak, sonuç paneli metnini
  /// değiştiriyor.
  bool _victory = false;
  bool get isVictory => _victory;

  /// Kazanmaya kalan yolcu.
  int get passengersToGoal =>
      (trainSnakeGoalPassengers - _passengersCollected).clamp(0, 999);

  /// Trenin o an baktığı yön.
  ///
  /// Ekran bunu yön tuşlarını çizmek için okuyor: tam ters yöndeki tuş
  /// sönük gösterilir, çünkü o hamle yok sayılıyor.
  SnakeDirection get direction => _direction;
  late Point<int> _passenger;
  int _passengersCollected = 0;

  /// Sıradaki adımlarda kuyruğun kısaltılmayacağı sayı.
  ///
  /// Hat bonusu tek karede birden çok vagon ekleyemez (gövde ızgarada
  /// süreklidir); bonus buraya yazılır ve sonraki adımlarda birer birer
  /// ödenir.
  int _pendingGrowth = 0;
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
  List<Point<int>> get previousBody =>
      List<Point<int>>.unmodifiable(_previousBody);

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
    _awaitingFirstInput = true;
    _victory = false;
    _pendingGrowth = 0;
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

    // İlk girdi treni başlatır. Aynı yöne basmak da başlatır: oyuncu
    // "sağa gideceğim" diyorsa onu beklet
    if (_awaitingFirstInput) {
      _awaitingFirstInput = false;
      _stepElapsed = 0;
      notifyListeners();
    }
    _queuedDirection = next;
  }

  /// Trenin gittiği yöne göre **sola** döner.
  ///
  /// Mutlak yön yerine göreli dönüş: dört yönlü tuş takımında her an bir
  /// tuş ölüdür (tam ters yön yasak) ve başparmak dört hedef arasında
  /// gezinir. İki dönüş tuşuyla ölü tuş kalmıyor ve tek elle oynanıyor.
  void turnLeft() => turn(switch (_queuedDirection ?? _direction) {
    SnakeDirection.up => SnakeDirection.left,
    SnakeDirection.left => SnakeDirection.down,
    SnakeDirection.down => SnakeDirection.right,
    SnakeDirection.right => SnakeDirection.up,
  });

  /// Trenin gittiği yöne göre **sağa** döner.
  void turnRight() => turn(switch (_queuedDirection ?? _direction) {
    SnakeDirection.up => SnakeDirection.right,
    SnakeDirection.right => SnakeDirection.down,
    SnakeDirection.down => SnakeDirection.left,
    SnakeDirection.left => SnakeDirection.up,
  });

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
    // Tren ilk girdiye kadar durur; yolculuk saati işlemeye devam eder.
    if (_awaitingFirstInput) return;
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
    final growing = eating || _pendingGrowth > 0;
    // Büyümüyorsa kuyruk bu adımda tam da bu hücreyi boşaltacağı için
    // kendi kuyruğuna değmek çarpışma sayılmaz — klasik yılan kuralı.
    final bodyForCollision = growing
        ? _body
        : _body.sublist(0, _body.length - 1);
    if (bodyForCollision.contains(next)) {
      endGame();
      return;
    }

    _body = <Point<int>>[next, ..._body];
    if (eating) {
      final levelBefore = level;
      _passengersCollected++;
      addScore(10 * level);
      markStationProgress();

      // Hat atlandıysa ek vagon borcu yazılır.
      if (level > levelBefore) _pendingGrowth += trainSnakeLevelBonusCars;

      if (_passengersCollected >= trainSnakeGoalPassengers) {
        _victory = true;
        notifyListeners();
        endGame();
        return;
      }
      _passenger = _spawnPassenger();
    } else if (_pendingGrowth > 0) {
      _pendingGrowth--;
    } else {
      _body = _body.sublist(0, _body.length - 1);
    }
    notifyListeners();
  }

  Point<int> _spawnPassenger() {
    // Sonsuz döngü riski yok: ızgara 11×15 = 165 hücre, tren zaferde bile
    // 73 hücre kaplıyor (%44); rastgele deneme pratikte birkaç turda boş
    // hücre bulur.
    while (true) {
      final candidate = Point<int>(
        _random.nextInt(trainSnakeColumns),
        _random.nextInt(trainSnakeRows),
      );
      if (!_body.contains(candidate)) return candidate;
    }
  }
}
