import '../domain/rail_lay_state.dart';
import 'rail_lay_level_grids.dart';

export 'rail_lay_level_grids.dart' show railLayLevelGrids;

/// Araçla üretilmiş bir bölümün ham verisi.
///
/// Ölçüler (`optimal`, `decisions`, `traps`) araçta çözücüyle bulundu;
/// oyunda yeniden hesaplanmaz, testler bir kısmını doğrular.
class RailLayLevelData {
  const RailLayLevelData({
    required this.number,
    required this.optimal,
    required this.decisions,
    required this.traps,
    required this.solution,
    required this.grid,
  });

  final int number;
  final int optimal;
  final int decisions;
  final int traps;

  /// En kısa çözüm: `U` yukarı, `D` aşağı, `L` sol, `R` sağ.
  final String solution;
  final List<String> grid;
}

/// Ray Döşe bölümleri.
///
/// Bölümler çalışma anında üretilmiyor, `tool/rail_lay/generate_levels.dart`
/// ile önceden üretilip çözücüyle ölçülüyor ve seçiliyor (Tünele Kaç'ın
/// yöntemi). Böylece her bölümün zorluğu biliniyor ve rampa elle
/// denetlenebiliyor.
class RailLayLevels {
  const RailLayLevels._();

  /// Aracın üretmeye çalıştığı bölüm sayısı.
  static const int target = 150;

  /// Son bölümden sonra dönülen aralığın uzunluğu: en zor bölümler.
  static const int loopLength = 50;

  static int get count => railLayLevelGrids.length;

  /// [number]. bölüm. Son bölümden sonra en zor [loopLength] bölüm döner;
  /// bölüm numarası artmaya devam eder ki oyuncu ilerlediğini görsün.
  ///
  /// Dönüş kolay bölümde puan kasmak sayılmaz: dönen bölümler en zorları.
  static RailLayLevel byNumber(int number) {
    final safe = number < 1 ? 1 : number;
    final data = railLayLevelGrids[dataIndexFor(safe)];
    return RailLayLevel.parse(
      data.grid,
      number: safe,
      solution: decodeSolution(data.solution),
    );
  }

  /// [number]. bölümün veri sırası (0'dan).
  static int dataIndexFor(int number) {
    if (number <= count) return number - 1;
    final loop = loopLength < count ? loopLength : count;
    final first = count - loop;
    return first + (number - count - 1) % loop;
  }

  static List<RailLayDirection> decodeSolution(String moves) =>
      <RailLayDirection>[
        for (final char in moves.split(''))
          switch (char) {
            'U' => RailLayDirection.up,
            'D' => RailLayDirection.down,
            'L' => RailLayDirection.left,
            _ => RailLayDirection.right,
          },
      ];
}
