@Tags(<String>['balance'])
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';

import '../helpers/metro_fixture.dart';

/// Hat Düşür'ün doğum dağılımı raporu — hangi ağırlık daha iyi bir oyun?
///
/// Aynı oyuncu modeli her dağılımla [_runs] kez oynar; yolculuk sınırı yok,
/// koşu taşmayla biter. Oyuncu modeli dengeleme botuyla aynı: aynı
/// seviyeden oturmuş bir parçanın üstüne nişan alır, bazen yanılır, her
/// bırakış arasında 0,7-1,2 saniye düşünür.
///
///   flutter test test/balance/merge_drop_spawn_report_test.dart
///
/// Test olarak şunu şart koşuyor: gönderilen ağırlık eşit dağılımdan
/// belirgin biçimde uzun yaşatıyor ve en yükseğe ulaşmayı bozmuyor.
///
/// Ölçüm (1 Eki 2026, 24 koşu, 8 dk sınır):
///
/// | dağılım | sn | birleşme | en büyük | M8 | M9 |
/// |---|---|---|---|---|---|
/// | eşit 1:1:1:1 | 126 | 110 | 8,3 | %96 | %29 |
/// | 4:3:2:1 | 169 | 156 | 8,2 | %92 | %29 |
/// | 6:4:2:1 | 190 | 179 | 8,2 | %92 | %29 |
///
/// 6:4:2:1 koşuyu daha da uzatıyor ama hiçbir yüksekliğe katkısı yok,
/// yalnız kolaylaştırıyor; 4:3:2:1 seçildi.
void main() {
  const runs = 24;

  /// Bir koşunun ölçüleri.
  ({double seconds, int merges, int maxLevel, int bestChain, double fill}) play(
    List<int> weights,
    int seed,
  ) {
    final metro = MetroFixture.load();
    // Uzun bir rota: koşu varışla değil taşmayla bitsin.
    final journey = RouteService(
      metro,
    ).estimate('m1a_yenikapi', 'm1a_ataturk_havalimani').journey!;
    final controller = MergeDropController(
      journey: journey,
      recordToBeat: 0,
      random: Random(seed),
      spawnWeights: weights,
      tick: const Duration(hours: 1),
    )..start();
    // Ekrandaki oyun alanının oranı (yükseklik / genişlik).
    controller.setPoolAspect(mergeDropPoolAspect);
    final player = Random(seed * 7919 + 1);
    const dt = 1 / 60;
    var wait = 0.0;
    var seconds = 0.0;
    while (controller.status == GameStatus.playing && seconds < 480) {
      wait -= dt;
      if (wait <= 0 && controller.canDrop) {
        wait = 0.7 + player.nextDouble() * 0.5;
        final same = controller.balls
            .where((b) => b.level == controller.currentLevel && b.settled)
            .toList();
        final aim = same.isEmpty || player.nextDouble() < 0.3
            ? player.nextDouble()
            : same[player.nextInt(same.length)].x;
        controller
          ..moveAim(aim)
          ..drop();
      }
      controller.debugAdvance(dt);
      seconds += dt;
    }
    final area = controller.balls.fold<double>(
      0,
      (double sum, b) => sum + pi * b.radius * b.radius,
    );
    final fill =
        area / (MergeDropController.worldWidth * controller.worldHeight);
    controller.dispose();
    return (
      seconds: seconds,
      merges: controller.merges,
      maxLevel: controller.maxLevel,
      bestChain: controller.bestChain,
      fill: fill,
    );
  }

  Map<String, double> summarize(List<int> weights) {
    final results = [
      for (var seed = 1; seed <= runs; seed++) play(weights, seed),
    ];
    double avg(num Function(dynamic r) of) =>
        results.map(of).fold<double>(0, (a, b) => a + b) / results.length;
    double rate(int level) =>
        results.where((r) => r.maxLevel >= level).length / results.length;
    return <String, double>{
      'saniye': avg((r) => r.seconds),
      'birleşme': avg((r) => r.merges),
      'en büyük': avg((r) => r.maxLevel),
      'zincir': avg((r) => r.bestChain),
      'doluluk': avg((r) => r.fill),
      'M8': rate(8),
      'M9': rate(9),
      'M10': rate(10),
      'M11': rate(11),
      'Z≥4': results.where((r) => r.bestChain >= 4).length / results.length,
      'Z≥6': results.where((r) => r.bestChain >= 6).length / results.length,
      'Z≥8': results.where((r) => r.bestChain >= 8).length / results.length,
    };
  }

  test('doğum dağılımı raporu', () {
    final candidates = <String, List<int>>{
      'eşit 1:1:1:1': const <int>[1, 1, 1, 1],
      'gönderilen ${mergeDropSpawnWeights.join(':')}': mergeDropSpawnWeights,
      'sık küçük 6:4:2:1': const <int>[6, 4, 2, 1],
    };
    final reports = <String, Map<String, double>>{};
    for (final entry in candidates.entries) {
      reports[entry.key] = summarize(entry.value);
    }
    final header = reports.values.first.keys.join(' | ');
    // ignore: avoid_print
    print('DAĞILIM | $header');
    for (final entry in reports.entries) {
      final row = entry.value.entries
          .map(
            (e) =>
                e.key.startsWith('M') ||
                    e.key.startsWith('Z') ||
                    e.key == 'doluluk'
                ? '%${(e.value * 100).round()}'
                : e.value.toStringAsFixed(1),
          )
          .join(' | ');
      // ignore: avoid_print
      print('${entry.key} | $row');
    }

    final equal = reports['eşit 1:1:1:1']!;
    final shipped = reports.entries
        .firstWhere((e) => e.key.startsWith('gönderilen'))
        .value;
    // Ağırlık oyuncuyu daha uzun yaşatmalı ve en yükseğe ulaşmayı
    // bozmamalı (simülasyon gürültüsü için yarım seviye pay).
    expect(shipped['saniye']!, greaterThan(equal['saniye']! * 1.15));
    expect(shipped['en büyük']!, greaterThan(equal['en büyük']! - 0.5));
  });
}
