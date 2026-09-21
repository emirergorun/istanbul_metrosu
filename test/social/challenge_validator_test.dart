import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/discovery/domain/discovery_catalog.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge_validator.dart';

import '../helpers/metro_fixture.dart';

/// Çözülmüş bir yükün **bu cihazda oynanabilirliği**.
///
/// Kodlayıcı metnin biçimine bakıyor; bu katman veriye bakıyor. Ayrımın
/// testi de ayrı: burada her senaryo metro verisiyle ilgili.
void main() {
  final metro = MetroFixture.load();
  final catalog = DiscoveryCatalog.fromRepository(metro);
  final validator = ChallengeValidator(
    metro: metro,
    catalog: catalog,
    routes: RouteService(metro),
  );

  Challenge build({
    String gameId = 'blocks',
    String lineId = 'M2',
    String originId = 'taksim',
    String destinationId = 'levent',
    int seconds = 300,
    String code = 'ABCD1234',
  }) => Challenge(
    id: 'abc123',
    gameId: gameId,
    lineId: lineId,
    originId: originId,
    destinationId: destinationId,
    estimatedSeconds: seconds,
    targetScore: 5000,
    seed: 1234,
    creatorCode: code,
    creatorName: 'Berke',
    createdOnEpochDay: 20719,
  );

  test('geçerli meydan okuma oynanabilir yolculuğa çevriliyor', () {
    final real = RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;
    final resolution = validator.resolve(
      build(seconds: real.estimatedSeconds),
    );

    expect(resolution.isValid, isTrue);
    expect(resolution.journey!.origin.id, 'm2_taksim');
    expect(resolution.journey!.destination.id, 'm2_levent');
    expect(resolution.game!.id, 'blocks');
    // Süre **karekodtan** geliyor: meydan okuyan ne kadar oynadıysa kabul
    // eden de o kadar oynuyor.
    expect(resolution.journey!.estimatedSeconds, real.estimatedSeconds);
  });

  test('tanınmayan oyun reddediliyor', () {
    expect(
      validator.resolve(build(gameId: 'yok_boyle_bir_oyun')).error,
      ChallengeError.unknownGame,
    );
  });

  test('kilitli oyun reddediliyor', () {
    // Yer tutucu oyunlar oynanamaz; karekod onları açtıramaz.
    expect(
      validator.resolve(build(gameId: 'transfer')).error,
      ChallengeError.unknownGame,
    );
  });

  test('tanınmayan hat reddediliyor', () {
    expect(
      validator.resolve(build(lineId: 'M99')).error,
      ChallengeError.unknownRoute,
    );
  });

  test('hatta olmayan durak reddediliyor', () {
    expect(
      validator.resolve(build(originId: 'yok_boyle_durak')).error,
      ChallengeError.unknownRoute,
    );
  });

  test('başka hattın durağı reddediliyor', () {
    // Kadıköy M4'te; M2 rotasında yeri yok. Aktarmasız oynanamaz.
    expect(
      validator.resolve(build(originId: 'kadikoy')).error,
      ChallengeError.unknownRoute,
    );
  });

  test('gerçekle uyuşmayan süre reddediliyor', () {
    // Elle şişirilmiş süre oyunu uzatıp hedefi kolaylaştırırdı.
    expect(
      validator.resolve(build(seconds: 7000)).error,
      ChallengeError.unknownRoute,
    );
  });

  test('küçük süre farkı kabul ediliyor', () {
    final real = RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;
    // Veri dosyasındaki bir kenar süresi düzeltilirse eski meydan
    // okumalar geçersiz olmamalı.
    expect(
      validator.resolve(build(seconds: real.estimatedSeconds + 60)).isValid,
      isTrue,
    );
  });

  test('kendi karen reddediliyor', () {
    expect(
      validator.resolve(build(code: 'ABCD1234'), ownCode: 'ABCD1234').error,
      ChallengeError.ownChallenge,
    );
  });

  test('başkasının karesi kabul ediliyor', () {
    final real = RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;
    expect(
      validator
          .resolve(
            build(code: 'ABCD1234', seconds: real.estimatedSeconds),
            ownCode: 'ZZZZ9999',
          )
          .isValid,
      isTrue,
    );
  });

  test('yolculuktan kanonik kimlik okunuyor', () {
    final real = RouteService(metro).estimate('m2_taksim', 'm2_levent').journey!;
    final pair = ChallengeValidator.canonicalPair(real);
    // Karekoda hat kapsamlı `m2_taksim` değil fiziksel `taksim` giriyor.
    expect(pair.origin, 'taksim');
    expect(pair.destination, 'levent');
  });
}
