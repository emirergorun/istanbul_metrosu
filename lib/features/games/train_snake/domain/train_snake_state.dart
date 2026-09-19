import 'dart:math';

const int trainSnakeMaxLevel = 11;
const int trainSnakePassengersPerLevel = 3;

/// Izgara boyutu. Satır/sütun oranı (17/11 ≈ 1.55) tipik dikey oyun
/// alanının en/boy oranına yakın seçildi — kutu şeklinde büyük bir boşluk
/// bırakmadan hücreler kareye yakın kalır.
const int trainSnakeColumns = 11;
const int trainSnakeRows = 17;

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
