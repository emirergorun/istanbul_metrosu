import 'dart:isolate';

import '../domain/escape_board.dart';
import '../domain/escape_solver.dart';

/// İpucu için sıradaki faydalı hamleyi bulan işlev.
///
/// Oyun ekranı bunu enjekte edilmiş bir işlev olarak görür: uygulamada
/// arama arka plandaki bir isolate'te çalışır, testlerde aynı iş parçacığında.
typedef EscapeHintSolver =
    Future<EscapeMove?> Function(EscapeLayout layout, List<int> positions);

/// Aramayı **ayrı bir isolate'te** yapar.
///
/// Zor bir bölümde oyuncu çözümden uzaklaşmışsa arama birkaç yüz bin durum
/// açabilir; bunu arayüz iş parçacığında yapmak sürüklemeyi kesik kesik
/// yapardı. Isolate'e yalnız geometri ve konumlar (düz sayılar) gidiyor,
/// sonuç tek bir hamle olarak dönüyor.
Future<EscapeMove?> solveHintInBackground(
  EscapeLayout layout,
  List<int> positions,
) {
  final copy = List<int>.of(positions);
  return Isolate.run(() => EscapeSolver(layout).nextMove(copy));
}

/// Aynı iş parçacığında çözer — testler ve küçük tahtalar için.
Future<EscapeMove?> solveHintImmediately(
  EscapeLayout layout,
  List<int> positions,
) async => EscapeSolver(layout).nextMove(positions);
