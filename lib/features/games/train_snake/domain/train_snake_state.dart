import 'dart:math';

const int trainSnakeMaxLevel = 11;

/// Bir üst hatta geçmek için toplanması gereken yolcu.
///
/// Üçtü ve oyunun bir hedefi yoktu: M11'e ~45 saniyede ulaşılıyor, sonra
/// oyun sonsuza kadar sürüyordu. Beşe çıkarıldı ve M11 artık **zafer**.
///
/// Hesap: 10 hat × 5 = 50 yolcu. Yolcu başına ortalama ~12 adım (tren
/// uzadıkça yol bulmak zorlaşır), adım 0,20 saniye → yaklaşık iki dakika.
/// En kısa yolculukta (6 dakika) bile kazanılabilir; hedefin ulaşılabilir
/// olması şart, yoksa anlamını yitirir.
const int trainSnakePassengersPerLevel = 5;

/// Hat atlayınca verilen ek vagon.
///
/// Yolcu başına bir vagon zaten uzuyor; hat atlamak ayrıca ödüllendirilir
/// ki merdivenin her basamağı tahtada görünür bir bedel yaratsın.
///
/// Son uzunluk: 3 + 50 + (10 × 2) = 73 vagon. 11×15 = 165 hücrede %44
/// doluluk — yılan türünde "zor ama yapılabilir" bandı; %50 üstünde tren
/// kendi kuyruğuyla kilitleniyor.
const int trainSnakeLevelBonusCars = 2;

/// Izgara boyutu.
///
/// 15/11 ≈ 1.36: ekranın tamamını kaplayan bir sahne görseli yerine kendi
/// çizdiğimiz tahtayı kullanınca oran serbest kaldı. Bu oran alt tuş
/// sırasına yer bırakırken hücreleri kare tutuyor.
const int trainSnakeColumns = 11;
const int trainSnakeRows = 15;

/// Kazanmak için gereken toplam yolcu.
const int trainSnakeGoalPassengers =
    (trainSnakeMaxLevel - 1) * trainSnakePassengersPerLevel;

/// Trenin başlangıç uzunluğu (vagon dahil lokomotif).
const int trainSnakeStartLength = 3;

const List<String> trainSnakeLineLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
  'M8',
  'M9',
  'M10',
  'M11',
];

String trainSnakeLabelForLevel(int level) {
  final index = (level - 1).clamp(0, trainSnakeLineLabels.length - 1);
  return trainSnakeLineLabels[index];
}

/// Toplanan yolcu sayısından hangi hatta olunduğunu türetir.
///
/// Her [trainSnakePassengersPerLevel] yolcuda bir üst hatta geçilir,
/// [trainSnakeMaxLevel]'de durur — M11'den sonra tren aynı hatta kalıp
/// oyun yüksek skor için sürer.
int trainSnakeLevelForPassengers(int passengers) {
  return (passengers ~/ trainSnakePassengersPerLevel + 1).clamp(
    1,
    trainSnakeMaxLevel,
  );
}

/// Tren dört yönde hareket eder. Ekranın diğer ucundan geri çıkma yok —
/// sınırın dışına çıkan hamle oyunu bitirir.
enum SnakeDirection { up, down, left, right }

extension SnakeDirectionX on SnakeDirection {
  /// Bu yönde bir adımın ızgara üzerindeki karşılığı.
  Point<int> get delta => switch (this) {
    SnakeDirection.up => const Point<int>(0, -1),
    SnakeDirection.down => const Point<int>(0, 1),
    SnakeDirection.left => const Point<int>(-1, 0),
    SnakeDirection.right => const Point<int>(1, 0),
  };

  /// Tam ters yön mü? Trenin kendi boynuna anında dönmesini (tek karede
  /// öz-çarpışma) engellemek için kullanılır.
  bool isOppositeOf(SnakeDirection other) {
    final a = delta;
    final b = other.delta;
    return a.x == -b.x && a.y == -b.y;
  }
}
