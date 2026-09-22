import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../journey/models/station.dart';

/// Izgaranın genişliği (sütun sayısı).
///
/// Sekiz sütun: oyuncu bir boşluğu yakalamak için yana kaçabilecek kadar
/// yer bulur ama hücre trenin üzerindeki hat kodunu okunur kılacak kadar
/// büyük kalır. Dokuz sütunda levha treni tamamen örtüyordu (simülatörde
/// görüldü).
const int crossingColumns = 8;

/// Aynı anda ekranda duran satır sayısı.
///
/// Oyuncunun **önünü görmesi** bu oyunun tamamı: hangi rayda tren var,
/// boşluk nerede, hepsi zıplamadan önce okunmalı. On satır, oyuncunun
/// üstünde altı satırlık bir okuma alanı bırakıyor — telefonda alanın
/// yüksekliği hücre boyunu belirlediği için satır sayısı aynı zamanda
/// trenlerin ne kadar büyük çizileceği demek.
const int crossingVisibleRows = 10;

/// Oyuncunun ekranın altından kaçıncı satırda tutulduğu.
///
/// Altta üç satır kalıyor: geri adım atmak için yer var ama ekranın çoğu
/// ileriyi gösteriyor.
const int crossingPlayerViewRow = 3;

/// Bir hücreden diğerine zıplama süresi.
///
/// Yılan oyununun adım aralığından (0,22 sn) belirgin biçimde kısa: orada
/// tren kendi kendine ilerliyor, burada her adımı oyuncu veriyor ve
/// gecikme doğrudan "kontrol etmiyorum" hissine dönüşüyor.
const double crossingHopSeconds = 0.14;

/// Başlangıçtaki güvenli peron satırı sayısı.
const int crossingStartSafeRows = 2;

/// Art arda gelebilecek en fazla ray satırı.
///
/// Dördü geçince oyun "boşluğu yakala"dan "üst üste dört kez şansın
/// yaver gitsin"e dönüyor: oyuncu ortadaki raylarda duramadığı için
/// bütün diziyi tek nefeste geçmek zorunda kalır.
const int crossingMaxTrackStreak = 3;

/// Kaç ray geçişinde bir durak ilerlemesi işlenir.
///
/// Diğer oyunlarla aynı ritim: Yolcu Topla'da her yolcu, Ray Uçuşu'nda her
/// kapı. Burada geçilen ray, oyunun "iyi hamle"si.
const int crossingRowsPerStation = 4;

/// Yeni bir peron satırına ilk kez varmanın ham puanı.
const int crossingPlatformPoints = 4;

/// Yeni bir ray satırına ilk kez varmanın ham puanı.
///
/// Riskli olan iş ödüllendirilir: peronda ilerlemek bedava, rayın üstünde
/// durmak canına mal olabilir.
const int crossingTrackPoints = 10;

/// Trenin hücre yüksekliğine oranı.
///
/// Vagon satırı tam doldurmaz; altında ve üstünde ray görünür kalır,
/// yoksa tren bir "renk şeridi" gibi okunur.
const double crossingTrainHeightCells = 0.74;

/// Vagon en/boy oranı ve vagonlar arası bağlantı payı.
///
/// `MetroTrainPainter.defaultWagonAspect` ve `MetroTrainPainter
/// .couplingRatio` ile aynı olmak **zorunda**: çarpışma kutusu ile ekranda
/// çizilen tren aynı uzunlukta olmazsa oyuncu görmediği bir trene çarpar.
/// `test/game/crossing_controller_test.dart` ikisini karşılaştırıyor.
const double crossingWagonAspect = 1.1;
const double crossingCouplingRatio = 0.14;

/// Oyuncunun çarpışma kutusunun hücre kenarlarından içeri payı.
///
/// Kutu hücrenin tamamı değil, ortadaki yarısı: figür hücreye tam
/// oturmuyor ve "daha değmeden öldüm" hissi bu oyunun en kolay bozulan
/// yeri. Tren tarafında pay yok — tren gövdesi neredeyse ne görünüyorsa o.
const double crossingPlayerInset = 0.25;

/// [cars] vagonluk bir trenin hücre cinsinden uzunluğu.
double crossingTrainLengthCells(int cars) =>
    crossingTrainHeightCells *
    (crossingWagonAspect * cars + crossingCouplingRatio * (cars - 1));

/// Satır tipi. Oyunun tamamı bu ikilinin üzerine kurulu.
enum CrossingRowKind {
  /// Peron: güvenli, üzerinde durulabilir.
  platform,

  /// Ray: üzerinden tren geçer.
  track,
}

/// Oyuncunun hamle yönü. Satır indeksi **yukarı doğru artar**.
enum CrossingDirection { forward, back, left, right }

extension CrossingDirectionX on CrossingDirection {
  /// (sütun, satır) değişimi.
  Point<int> get delta => switch (this) {
    CrossingDirection.forward => const Point<int>(0, 1),
    CrossingDirection.back => const Point<int>(0, -1),
    CrossingDirection.left => const Point<int>(-1, 0),
    CrossingDirection.right => const Point<int>(1, 0),
  };
}

/// Ray üzerinde akan bir tren.
@immutable
class CrossingTrain {
  const CrossingTrain({
    required this.id,
    required this.line,
    required this.cars,
    required this.x,
  });

  final int id;

  /// Gerçek hat: kodu trenin üzerine yazılır, gövdesi bu rengi alır.
  final MetroLine line;
  final int cars;

  /// Trenin **sol** kenarının sütun cinsinden konumu; ızgara dışına taşar.
  final double x;

  double get length => crossingTrainLengthCells(cars);
  double get right => x + length;

  /// Tren, [column] sütunundaki oyuncuya değiyor mu?
  bool hits(int column) =>
      x < column + 1 - crossingPlayerInset &&
      right > column + crossingPlayerInset;

  CrossingTrain copyWith({double? x}) =>
      CrossingTrain(id: id, line: line, cars: cars, x: x ?? this.x);
}

/// Bir satır: ya peron ya da üzerinde trafik akan bir ray.
class CrossingRow {
  CrossingRow.platform(this.index)
    : kind = CrossingRowKind.platform,
      speed = 0,
      toRight = true,
      nextGap = 0;

  CrossingRow.track(
    this.index, {
    required this.speed,
    required this.toRight,
    required this.nextGap,
  }) : kind = CrossingRowKind.track;

  final int index;
  final CrossingRowKind kind;

  /// Hücre/saniye, işaretsiz. Yön [toRight] ile taşınır.
  final double speed;
  final bool toRight;

  /// Bu satırdaki trenler; baştan sona sıralı değil, akış sırasına bağlı.
  final List<CrossingTrain> trains = <CrossingTrain>[];

  /// Bir sonraki trenin öncekinden kaç hücre geride doğacağı.
  double nextGap;

  bool get isTrack => kind == CrossingRowKind.track;

  /// Trenin trafik yönündeki konumu.
  ///
  /// Sağa giden satırda trenler soldan girer, sola gidende sağdan. İki hâli
  /// ayrı ayrı yazmak doğuş/silme kodunu iki katına çıkarıyordu; bunun
  /// yerine her tren **gittiği yönde artan** tek bir eksene taşınıyor:
  /// [trackPosition] 0'dan küçükken tren henüz ekrana girmemiş,
  /// [crossingColumns]'u aşınca çıkmıştır.
  double trackPosition(CrossingTrain train) =>
      toRight ? train.x : crossingColumns - train.right;

  /// [trackPosition] üzerinden verilen konumdaki trenin sol kenarı.
  double leftEdgeFor(double position, int cars) => toRight
      ? position
      : crossingColumns - position - crossingTrainLengthCells(cars);

  /// Oyuncu [column] sütununda bu satırda dursa trene çarpar mı?
  bool hits(int column) => trains.any((CrossingTrain t) => t.hits(column));
}

/// Zorluk ayarı.
///
/// [RailFlightConfig.forGates] ile aynı kalıp: oyun **geçilen satır**
/// sayısına göre kolaydan zora doğru yumuşakça kayar, yolculuğun uzunluğuna
/// bakmaz. Uzun rotada oyunu en zor ayarla başlatmak, o oyunu seçen
/// oyuncuyu cezalandırıyordu (bkz. Ray Uçuşu'nun aynı notu).
@immutable
class CrossingConfig {
  const CrossingConfig({
    required this.trackChance,
    required this.minSpeed,
    required this.maxSpeed,
    required this.gapSeconds,
    required this.maxCars,
  });

  factory CrossingConfig.forRows(int rows) {
    final t = (rows / hardenAfterRows).clamp(0.0, 1.0);
    double lerp(double easy, double hard) => easy + (hard - easy) * t;
    return CrossingConfig(
      trackChance: lerp(0.45, 0.78),
      minSpeed: lerp(2.2, 3.6),
      maxSpeed: lerp(3.4, 5.6),
      gapSeconds: lerp(1.45, 1.05),
      // Uzun tren ancak oyun ilerleyince çıkar: üç vagon, tek bir boşluğu
      // beklemeyi gerektiren ilk gerçek engel. Alt sınır iki: tek vagonluk
      // tren hat kodunu taşıyamayacak kadar kısa kalıyor.
      maxCars: t < 0.35 ? 2 : 3,
    );
  }

  /// Kaç satır sonra en zor ayara ulaşılır.
  static const int hardenAfterRows = 60;

  final double trackChance;
  final double minSpeed;
  final double maxSpeed;

  /// İki tren arasındaki **süre** cinsinden en küçük boşluk.
  ///
  /// Hücre değil saniye: hızlı bir satırda aynı hücre boşluğu geçilemez
  /// olurdu. Zıplama 0,14 saniye sürdüğüne göre 0,75 saniyelik pencere
  /// en zor ayarda bile beş katı pay bırakıyor — yani her ray satırı
  /// **her zaman** geçilebilir, sorun boşluğu görmek.
  final double gapSeconds;
  final int maxCars;
}

/// Hat sırasını dağıtan torba.
///
/// Rastgele seçim "üst üste beş M2" üretebiliyordu (kullanıcının açıkça
/// istemediği şey). Torba yöntemi: bütün hatlar karılır, birer birer
/// dağıtılır, torba bitince yeniden karılır. Böylece on trenlik her
/// pencerede her hat bir kez geçer. Yeni torbanın ilki bir öncekiyle
/// aynıysa ikinciyle takas edilir; tek eş hat bile arka arkaya gelmez.
class CrossingLineBag {
  CrossingLineBag(List<MetroLine> lines, this._random)
    : _lines = List<MetroLine>.of(lines) {
    assert(_lines.isNotEmpty, 'Hat listesi boş olamaz');
  }

  final List<MetroLine> _lines;
  final Random _random;
  final List<MetroLine> _pending = <MetroLine>[];
  String? _lastId;

  MetroLine next() {
    if (_pending.isEmpty) _refill();
    final line = _pending.removeLast();
    _lastId = line.id;
    return line;
  }

  void _refill() {
    _pending
      ..addAll(_lines)
      ..shuffle(_random);
    // `removeLast` sondan çektiği için "ilk dağıtılacak" son elemandır.
    if (_pending.length > 1 && _pending.last.id == _lastId) {
      final last = _pending.removeLast();
      _pending.insert(_pending.length - 1, last);
    }
  }
}
