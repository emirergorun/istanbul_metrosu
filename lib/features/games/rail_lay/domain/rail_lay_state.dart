import 'dart:math';

/// Tahtanın en büyük genişliği (sütun).
///
/// Dokuz sütun telefonun genişliğine sığan sınır: hücre 40 pt'nin altına
/// inerse metro ve döşenen raylar okunmuyor.
const int railLayMaxWidth = 9;

/// Tahtanın en büyük yüksekliği (satır).
///
/// Alanın üstünde HUD, altında kontrol satırı ve yolculuk şeridi var; on
/// bir satır, küçük bir telefonda bile hücreyi dokuz sütunla aynı boyda
/// tutuyor.
const int railLayMaxHeight = 11;

/// Metronun kayış hızı (hücre/saniye).
///
/// Videodaki top bir tahtayı yaklaşık yarım saniyede geçiyor. Daha yavaşı
/// "bekletiyor", daha hızlısı döşenen karelerin birer birer yandığını
/// göstermiyor.
const double railLaySlideCellsPerSecond = 20;

/// Bölüm sonundaki kutlamanın süresi.
///
/// Sıradaki bölüm kendiliğinden yükleniyor; kutlama oyuncunun "bitti"
/// anını görmesine yetecek kadar, akışı bölmeyecek kadar kısa.
const double railLayCelebrateSeconds = 0.9;

/// Çıkmaza girdikten sonra "Sıkıştın" uyarısından önce yapılan hamle sayısı.
///
/// Uyarı önce anında geliyordu; bazı bölümlerde ilk hamle yanlışsa oyuncu
/// daha ilk kayışta "yanlış yaptın" duyuyordu. Kullanıcının isteği: oyuncu
/// önce kendisi fark etsin. Fark etmezse de boşa çok süre harcamasın —
/// üç hamle ikisinin arası.
const int railLayStuckHintMoves = 3;

/// Kayış yönü. Satır indeksi **aşağı doğru** artar (ekran koordinatı).
enum RailLayDirection { up, down, left, right }

extension RailLayDirectionX on RailLayDirection {
  /// (sütun, satır) değişimi.
  Point<int> get delta => switch (this) {
    RailLayDirection.up => const Point<int>(0, -1),
    RailLayDirection.down => const Point<int>(0, 1),
    RailLayDirection.left => const Point<int>(-1, 0),
    RailLayDirection.right => const Point<int>(1, 0),
  };

  bool get isHorizontal =>
      this == RailLayDirection.left || this == RailLayDirection.right;

  /// Bu yönde geçilen karenin ray ekseni ([railLayHorizontal] ya da
  /// [railLayVertical]).
  int get axisBit => isHorizontal ? railLayHorizontal : railLayVertical;
}

/// Döşenen karenin bitleri. Bir kare iki eksende de döşenebilir (makas
/// gibi kesişen iki hat); ekran ikisini de çizer.
const int railLayHorizontal = 1;
const int railLayVertical = 2;

/// Döşenmiş ama üzerinden geçilmemiş kare — yalnızca başlangıç karesi.
const int railLayStation = 4;

/// Bir bölüm: açık kareler, başlangıç ve bilinen bir çözüm.
class RailLayLevel {
  RailLayLevel({
    required this.number,
    required this.width,
    required this.height,
    required List<bool> open,
    required this.start,
    List<RailLayDirection> solution = const <RailLayDirection>[],
  }) : open = List<bool>.unmodifiable(open),
       solution = List<RailLayDirection>.unmodifiable(solution),
       openCount = open.where((bool cell) => cell).length {
    assert(open.length == width * height, 'Izgara boyutu tutmuyor');
    assert(isOpen(start), 'Başlangıç karesi açık olmalı');
  }

  /// Testler için metinden bölüm: `#` duvar, `.` açık, `S` başlangıç.
  factory RailLayLevel.parse(
    List<String> rows, {
    int number = 1,
    List<RailLayDirection> solution = const <RailLayDirection>[],
  }) {
    final height = rows.length;
    final width = rows.first.length;
    final open = <bool>[];
    Point<int>? start;
    for (var y = 0; y < height; y++) {
      assert(rows[y].length == width, 'Satırlar eşit uzunlukta olmalı');
      for (var x = 0; x < width; x++) {
        final char = rows[y][x];
        if (char == 'S') start = Point<int>(x, y);
        open.add(char != '#');
      }
    }
    return RailLayLevel(
      number: number,
      width: width,
      height: height,
      open: open,
      start: start!,
      solution: solution,
    );
  }

  final int number;
  final int width;
  final int height;

  /// Satır satır açık kareler: `y * width + x`.
  final List<bool> open;
  final Point<int> start;

  /// Bölümün en kısa çözümü (araç çözücüyle buldu). Elle kurulan
  /// (testteki) bölümlerde boş.
  final List<RailLayDirection> solution;
  final int openCount;

  /// Bölüm bitince yolculuğa yazılan ham puan.
  ///
  /// Açık kare "ne kadar iş", en kısa çözümün hamle sayısı "ne kadar
  /// düşünme". Yalnız kare sayılsaydı küçük ama tuzaklı bir bölüm, büyük
  /// ama düz bir bölümden az ödüllendirilirdi.
  int get points => openCount + 3 * solution.length;

  int indexOf(Point<int> cell) => cell.y * width + cell.x;

  bool contains(Point<int> cell) =>
      cell.x >= 0 && cell.y >= 0 && cell.x < width && cell.y < height;

  bool isOpen(Point<int> cell) => contains(cell) && open[indexOf(cell)];

  /// [from]'dan [direction] yönünde kayınca geçilen kareler, sırayla.
  ///
  /// Başlangıç karesi dahil değil; son eleman metronun duracağı kare. Önü
  /// hemen duvarsa boş liste.
  List<Point<int>> slide(Point<int> from, RailLayDirection direction) {
    final delta = direction.delta;
    final path = <Point<int>>[];
    var cell = Point<int>(from.x + delta.x, from.y + delta.y);
    while (isOpen(cell)) {
      path.add(cell);
      cell = Point<int>(cell.x + delta.x, cell.y + delta.y);
    }
    return path;
  }

  /// [position]'dan hâlâ döşenebilecek kareler.
  ///
  /// Duruş noktaları döşemeden bağımsız (duvarlar sabit), bu yüzden
  /// buradan ulaşılabilen her duruştan yapılan her kayışın geçtiği kareler
  /// toplanır. Döşenmemiş bir kare bu kümede değilse bölüm artık
  /// bitirilemez.
  ///
  /// Tersi her zaman doğru değil: tek yönlü bir cebe girilirse kareler
  /// kümede görünür ama sırayla hepsine gidilemeyebilir. Bu yüzden
  /// sonuç "kesin sıkıştın" sinyali; "baştan al" düğmesi her zaman açık.
  Set<int> reachableCells(Point<int> position) {
    final covered = <int>{};
    final seen = <Point<int>>{position};
    final queue = <Point<int>>[position];
    while (queue.isNotEmpty) {
      final stop = queue.removeLast();
      for (final direction in RailLayDirection.values) {
        final path = slide(stop, direction);
        if (path.isEmpty) continue;
        for (final cell in path) {
          covered.add(indexOf(cell));
        }
        if (seen.add(path.last)) queue.add(path.last);
      }
    }
    return covered;
  }

  /// Çözümü oynatıp bütün açık kareleri döşeyip döşemediğini söyler.
  bool solutionPaintsAll() {
    final painted = <int>{indexOf(start)};
    var position = start;
    for (final direction in solution) {
      final path = slide(position, direction);
      if (path.isEmpty) return false;
      for (final cell in path) {
        painted.add(indexOf(cell));
      }
      position = path.last;
    }
    return painted.length == openCount;
  }
}
