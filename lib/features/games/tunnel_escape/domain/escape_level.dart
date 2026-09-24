import 'escape_board.dart';
import 'escape_piece.dart';

/// Bölümün zorluk kuşağı — hat haritasında ve dengelemede kullanılır.
///
/// Sınırlar bölüm numarasına bağlı ve bilerek kaba: kuşak içinde zorluk
/// dalgalanabilir (nefes aldıran kolay bölümler istenen bir şey), ama
/// kuşaktan kuşağa eğilim açıkça yukarı.
enum EscapeTier {
  /// 1-5: mekanik kendini anlatır, tek fikir.
  onboarding,

  /// 6-15: daha çok engel, 3 hücrelik metrolar, çok adımlı çözüm.
  understanding,

  /// 16-30: zincir — C'yi kaydır, B açılsın, A açılsın.
  planning,

  /// 31-45: sık tahta, az boşluk, yanıltıcı hamleler.
  mastery,

  /// 46-59: uzun bağımlılıklar, dar manevra alanı.
  expert,

  /// 60: son durak.
  finale;

  static EscapeTier of(int number) {
    if (number <= 5) return onboarding;
    if (number <= 15) return understanding;
    if (number <= 30) return planning;
    if (number <= 45) return mastery;
    if (number <= 59) return expert;
    return finale;
  }
}

/// Bölüm verisinin yazıldığı biçim: ızgara metni ve ölçüler.
///
/// `const` olabilsin diye yalnız metin ve sayı taşır; [EscapeLevel]'e
/// ilk kullanımda çevrilir.
final class EscapeLevelData {
  const EscapeLevelData({
    required this.number,
    required this.optimalMoves,
    required this.threeStarMoves,
    required this.twoStarMoves,
    required this.grid,
  });

  final int number;
  final int optimalMoves;
  final int threeStarMoves;
  final int twoStarMoves;
  final List<String> grid;

  EscapeLevel toLevel() => EscapeLevel.parse(
    number: number,
    grid: grid,
    optimalMoves: optimalMoves,
    threeStarMoves: threeStarMoves,
    twoStarMoves: twoStarMoves,
  );
}

/// Bir bölüm: tahta, metrolar, başlangıç dizilişi ve çözücünün ölçüleri.
///
/// **Veri, sunum değil.** Koordinatlar hücre cinsinden; piksel, renk ya da
/// animasyon burada yok. Ekran ızgara uzayını kendi ölçüsüne çevirir.
///
/// Bölümler elle yazılmış ızgara metinlerinden kurulur ([EscapeLevel.parse]).
/// Metin biçimi okunabilir olduğu için seçilmiş: bir bölümü gözden geçiren
/// kişi tahtayı doğrudan görüyor.
final class EscapeLevel {
  EscapeLevel({
    required this.number,
    required this.layout,
    required List<int> start,
    required this.optimalMoves,
    required this.threeStarMoves,
    required this.twoStarMoves,
  }) : start = List<int>.unmodifiable(start);

  /// Bölüm numarası — kalıcı kimlik. Kayıtlar buna bağlı.
  final int number;

  final EscapeLayout layout;

  /// Başlangıç konumları, metro sırasıyla.
  final List<int> start;

  /// Çözücünün bulduğu en kısa çözüm. Testler her bölümde yeniden
  /// hesaplayıp bu sayıyla karşılaştırır.
  final int optimalMoves;

  /// Üç yıldız için en fazla hamle — en iyi çözüm ya da ona çok yakın.
  final int threeStarMoves;

  /// İki yıldız için en fazla hamle. Üstü tek yıldız: bitirmek her zaman
  /// bir sonraki bölümü açar.
  final int twoStarMoves;

  /// Bulmacanın kalıcı parmak izi: tahta değişirse değişir.
  ///
  /// Kayıtlar bununla bulmacaya bağlanır ([EscapeLevelRecord.fingerprint]):
  /// bölüm numarası aynı kalıp tahtası yenilenirse eski en iyi hamle yeni
  /// bulmacayla karşılaştırılmaz.
  late final String fingerprint = fingerprintOf(render(layout, start));

  int get width => layout.width;
  int get height => layout.height;
  List<EscapePiece> get pieces => layout.pieces;
  EscapeTier get tier => EscapeTier.of(number);

  /// Tünelin açıldığı satır — hedef metronun satırı.
  int get exitRow => layout.exitRow;

  EscapeBoard get initialBoard => EscapeBoard(layout, start);

  /// Izgara metninden bölüm kurar.
  ///
  /// Biçim: her satır bir tahta satırı. `.` boş hücre, `R` kırmızı hedef
  /// metro, diğer harfler beyaz metrolar. Aynı harfin hücreleri tek bir
  /// satırda ya da sütunda bitişik olmalı; eksen buradan çıkarılır.
  ///
  /// ```
  /// ......
  /// ......
  /// RR..A.
  /// ....A.
  /// ......
  /// ......
  /// ```
  factory EscapeLevel.parse({
    required int number,
    required List<String> grid,
    required int optimalMoves,
    required int threeStarMoves,
    required int twoStarMoves,
  }) {
    final (layout, start) = parseGrid(grid);
    return EscapeLevel(
      number: number,
      layout: layout,
      start: start,
      optimalMoves: optimalMoves,
      threeStarMoves: threeStarMoves,
      twoStarMoves: twoStarMoves,
    );
  }

  /// Hedef metronun harfi.
  static const String targetId = 'R';

  /// Boş hücre.
  static const String empty = '.';

  /// Izgara metnini geometri ve başlangıç konumlarına çevirir.
  ///
  /// Metrolar harf sırasıyla dizilir (hedef her zaman ilk): aynı ızgara
  /// her seferinde aynı sırayı, dolayısıyla aynı anahtarları verir.
  static (EscapeLayout, List<int>) parseGrid(List<String> grid) {
    if (grid.isEmpty) throw const FormatException('Boş ızgara');
    final height = grid.length;
    final width = grid.first.length;
    final cells = <String, List<(int, int)>>{};
    for (var row = 0; row < height; row++) {
      final line = grid[row];
      if (line.length != width) {
        throw FormatException('Satır $row genişliği $width değil: "$line"');
      }
      for (var col = 0; col < width; col++) {
        final char = line[col];
        if (char == empty) continue;
        cells.putIfAbsent(char, () => <(int, int)>[]).add((row, col));
      }
    }
    if (!cells.containsKey(targetId)) {
      throw const FormatException('Izgarada hedef metro (R) yok');
    }

    final ids = cells.keys.toList()
      ..sort((String a, String b) {
        if (a == targetId) return -1;
        if (b == targetId) return 1;
        return a.compareTo(b);
      });

    final pieces = <EscapePiece>[];
    final start = <int>[];
    for (final id in ids) {
      final spots = cells[id]!;
      final rows = spots.map(((int, int) c) => c.$1).toSet();
      final cols = spots.map(((int, int) c) => c.$2).toSet();
      final horizontal = rows.length == 1;
      if (!horizontal && cols.length != 1) {
        throw FormatException('$id düz bir çizgi değil');
      }
      if (spots.length < 2 || spots.length > 3) {
        throw FormatException('$id uzunluğu ${spots.length}: 2 ya da 3 olmalı');
      }
      final along = (horizontal ? cols : rows).toList()..sort();
      for (var i = 1; i < along.length; i++) {
        if (along[i] != along[i - 1] + 1) {
          throw FormatException('$id hücreleri bitişik değil');
        }
      }
      pieces.add(
        EscapePiece(
          id: id,
          axis: horizontal ? EscapeAxis.horizontal : EscapeAxis.vertical,
          length: spots.length,
          lane: horizontal ? rows.first : cols.first,
          isTarget: id == targetId,
        ),
      );
      start.add(along.first);
    }

    return (EscapeLayout(width: width, height: height, pieces: pieces), start);
  }

  /// Izgara metninin parmak izi: satırlar `/` ile birleşir, FNV-1a (32 bit),
  /// sekiz haneli onaltılık. Platformdan ve oturumdan bağımsız, kararlı.
  static String fingerprintOf(List<String> grid) {
    var hash = 0x811c9dc5;
    for (final unit in grid.join('/').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Tahtayı ızgara metnine geri yazar — araçlar ve hata iletileri için.
  static List<String> render(EscapeLayout layout, List<int> positions) {
    final rows = List<List<String>>.generate(
      layout.height,
      (_) => List<String>.filled(layout.width, empty),
    );
    for (var i = 0; i < layout.pieceCount; i++) {
      final piece = layout.pieces[i];
      for (final (row, col) in piece.cellsAt(positions[i])) {
        rows[row][col] = piece.id;
      }
    }
    return <String>[for (final row in rows) row.join()];
  }

  @override
  String toString() => 'EscapeLevel($number, en iyi $optimalMoves)';
}
