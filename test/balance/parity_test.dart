import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/scoring/game_score_profile.dart';

import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';

import '../helpers/metro_fixture.dart';
import 'bots.dart';

/// Ortak puanlamanın bekçisi.
///
/// Rota rekoru artık tek ve yolculuk boyunca hangi oyun oynanırsa oynansın
/// aynı kovaya yazılıyor. Bir oyunun puanlaması sessizce cömertleşirse
/// rekor "en kolay puan veren oyunu açan kazanır"a döner. Bu test tam da
/// onu yakalar: her oyun orta seviye oyuncuya dakikada yaklaşık aynı puanı
/// vermeli.
///
/// Ayrıntılı tablo (acemi/orta/usta, yüzdelikler) etiketli raporda:
/// `flutter test test/balance/points_per_minute_test.dart --tags balance`
void main() {
  final journey = RouteService(
    MetroFixture.load(),
  ).estimate('m2_taksim', 'm2_levent').journey!;

  // Az tohum: bu test normal koşuda her seferinde çalışıyor. Botlar
  // tohumlu, yani sonuç tekrarlanabilir; geniş dağılım raporun işi.
  const seeds = 5;
  const target = GameScoreProfiles.targetPointsPerMinute;
  const tolerance = GameScoreProfiles.parityTolerance;
  const expertCeiling = GameScoreProfiles.expertCeiling;

  setUp(() {
    // Blok Metro'nun dengeleme günlüğü test çıktısını boğuyor.
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = debugPrintThrottled);
  });

  for (final entry in botFactories.entries) {
    test('${entry.key}: dakikada ~$target puan', () {
      final sample = measure(
        entry.value,
        journey: journey,
        skill: GameBot.midSkill,
        runs: seeds,
      );
      expect(
        sample.median,
        inInclusiveRange(target * (1 - tolerance), target * (1 + tolerance)),
        reason:
            '${entry.key} orta seviyede dakikada ${sample.median.round()} '
            'puan veriyor. Ölçeği '
            '`GameScoreProfiles.profiles[\'${entry.value.id}\']` içinde '
            'güncelle ya da oyunun ham puanını düzelt.',
      );
    });

    // Rekor iyi oynayan tarafından kurulur: asıl "rekor kasma" riski usta
    // seviyede. Metro Bilgi bir zamanlar burada dakikada 429 puan
    // veriyordu (diğerleri 123-149) — bu sınır onu yakalar.
    test('${entry.key}: usta seviyede tavanı aşmıyor', () {
      final sample = measure(
        entry.value,
        journey: journey,
        skill: GameBot.highSkill,
        runs: 4,
      );
      expect(
        sample.median,
        lessThanOrEqualTo(target * expertCeiling),
        reason:
            '${entry.key} usta seviyede dakikada ${sample.median.round()} '
            'puan veriyor; bu oyun rota rekorunun kestirme yolu olur.',
      );
    });
  }

  // Asıl soru bu: "1000 puanın 800'ü Blok Metro'dan geldi" şikâyeti, ya
  // süre dağılımındandır ya da puanlama hatasıdır. Eşit süre oynanınca
  // haneler de eşit olmalı — bu test onu her koşuda doğruluyor.
  test('eşit süre oynanan iki oyun skoru yarı yarıya paylaşır', () {
    final shares = <double>[];
    for (var seed = 0; seed < 3; seed++) {
      final session = JourneySession(journey: journey)
        ..setStatus(GameStatus.playing);

      // Yolculuğun ilk yarısı Blok Metro (çıpa), ikinci yarısı en cömert
      // ham puana sahip oyun.
      playInto(
        session,
        botFactories['Blok Metro']!,
        journey: journey,
        seed: seed,
        untilElapsed: journey.estimatedSeconds / 2,
      );
      final blocks = session.scoreOf('blocks');
      playInto(
        session,
        botFactories['Hat Düşür']!,
        journey: journey,
        seed: seed,
        untilElapsed: journey.estimatedSeconds.toDouble(),
      );

      expect(session.scoreOf('merge_drop'), greaterThan(0));
      shares.add(blocks / session.score);
    }
    shares.sort();

    expect(
      shares[1],
      inInclusiveRange(0.35, 0.65),
      reason:
          'Blok Metro yolculuğun yarısında skorun %'
          '${(100 * shares[1]).round()}\'ini aldı; iki oyun eşit süre '
          'oynandığında pay da eşit olmalı.',
    );
  });

  test('her oyunun bir ölçek profili var', () {
    for (final entry in botFactories.entries) {
      expect(
        GameScoreProfiles.profiles.containsKey(entry.value.id),
        isTrue,
        reason: '${entry.key} (${entry.value.id}) ölçek tablosunda yok',
      );
    }
  });
}
