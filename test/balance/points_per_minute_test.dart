@Tags(<String>['balance'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/scoring/game_score_profile.dart';

import '../helpers/metro_fixture.dart';
import 'bots.dart';

/// Oyunların **dakikada kaç puan** verdiğini ölçen rapor.
///
/// Ürün kodu değil, ölçüm aracıdır: kurallar gerçek controller'lardan gelir,
/// burada yalnızca oyuncu modellenir. `GameScoreProfiles` ölçekleri bu
/// tablodan çıktı; bir oyunun puanlaması değişince tablo yeniden alınmalı.
///
/// Çalıştırmak için:
///   flutter test test/balance/points_per_minute_test.dart --tags balance
void main() {
  final routes = RouteService(MetroFixture.load());

  /// Kısa ve uzun rota: bazı oyunların zorluğu yolculuk süresine bağlı
  /// (Ray Uçuşu'nun boşluk yüksekliği gibi), ölçek ikisinde de tutmalı.
  final journeys = <Journey>[
    routes.estimate('m2_taksim', 'm2_levent').journey!,
    routes.estimate('m4_kadikoy', 'm4_sabiha_gokcen_havalimani').journey!,
  ];

  for (final journey in journeys) {
    test('oyun başına puan/dk — ${journey.origin.name} → '
        '${journey.destination.name}', () {
      // Blok Metro'nun hamle günlüğü tabloyu boğuyor.
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = debugPrintThrottled);

      // Uzun rotada bir koşu 52 dakikalık oyun demek; aynı tohum sayısı
      // raporu yarım saate çıkarıyordu.
      final runs = journey.estimatedMinutes > 20 ? 8 : 25;
      final lines = <String>[
        '',
        'Rota: ${journey.origin.name} → ${journey.destination.name} '
            '(${journey.estimatedMinutes} dk, ${journey.estimatedSeconds} sn)',
        'Hedef: ${GameScoreProfiles.targetPointsPerMinute} puan/dk '
            '(±%${(GameScoreProfiles.parityTolerance * 100).round()}), '
            '$runs tohum, medyan',
        '',
        '${'Oyun'.padRight(15)}${'Acemi'.padLeft(8)}${'Orta'.padLeft(8)}'
            '${'Usta'.padLeft(8)}${'U/A'.padLeft(7)}'
            '${'p10'.padLeft(8)}${'p90'.padLeft(8)}'
            '${'Can'.padLeft(7)}',
      ];

      for (final entry in botFactories.entries) {
        final mid = measure(
          entry.value,
          journey: journey,
          skill: GameBot.midSkill,
          runs: runs,
        );
        final low = measure(
          entry.value,
          journey: journey,
          skill: GameBot.lowSkill,
          runs: runs,
        );
        final high = measure(
          entry.value,
          journey: journey,
          skill: GameBot.highSkill,
          runs: runs,
        );
        lines.add(
          '${entry.key.padRight(15)}'
          '${low.median.round().toString().padLeft(8)}'
          '${mid.median.round().toString().padLeft(8)}'
          '${high.median.round().toString().padLeft(8)}'
          '${(high.median / low.median).toStringAsFixed(1).padLeft(7)}'
          '${mid.p10.round().toString().padLeft(8)}'
          '${mid.p90.round().toString().padLeft(8)}'
          '${mid.medianLives.round().toString().padLeft(7)}',
        );
      }

      // ignore: avoid_print
      print(lines.join('\n'));
    });
  }
}
