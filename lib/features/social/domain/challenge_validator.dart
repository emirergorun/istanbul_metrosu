import '../../discovery/domain/discovery_catalog.dart';
import '../../games/catalog/mini_game.dart';
import '../../journey/models/journey.dart';
import '../../journey/models/station.dart';
import '../../journey/services/route_service.dart';
import '../../../data/metro/metro_repository.dart';
import 'challenge.dart';

/// Çözülmüş bir meydan okumanın **bu cihazda oynanabilir** olduğunu
/// doğrular ve gerçek bir [Journey]'e çevirir.
///
/// [ChallengeCodec] metnin biçimine bakar; bu sınıf veriye bakar. Ayrım
/// bilinçli: kodlayıcı saf ve metro verisi olmadan test edilebilir,
/// doğrulayıcı ise depoya bağlı.
///
/// Karekod kullanıcı denetimindeki veri. Buradan geçmeyen hiçbir alan
/// oyuna, rotaya ya da kayda ulaşmaz.
class ChallengeValidator {
  const ChallengeValidator({
    required this.metro,
    required this.catalog,
    required this.routes,
  });

  final MetroRepository metro;
  final DiscoveryCatalog catalog;
  final RouteService routes;

  /// Meydan okumayı oynanabilir bir yolculuğa çevirir.
  ///
  /// [ownCode] verilirse oyuncunun kendi karesini kabul etmesi engellenir:
  /// kendi hedefini geçmek bir meydan okuma değil.
  ChallengeResolution resolve(Challenge challenge, {String? ownCode}) {
    if (!challenge.hasSaneFields) {
      return const ChallengeResolution.failure(ChallengeError.outOfBounds);
    }
    if (ownCode != null && challenge.creatorCode == ownCode) {
      return const ChallengeResolution.failure(ChallengeError.ownChallenge);
    }

    final game = MiniGames.byId(challenge.gameId);
    if (game == null || !game.isAvailable) {
      return const ChallengeResolution.failure(ChallengeError.unknownGame);
    }

    // Hat verisi bu sürümde var mı?
    if (metro.lineById(challenge.lineId) == null) {
      return const ChallengeResolution.failure(ChallengeError.unknownRoute);
    }

    // Kanonik durak kimliğinden **bu hattaki** durak kaydına in.
    //
    // Karekod fiziksel durağı taşıyor (Yenikapı), rota ise hat kapsamlı
    // kaydı istiyor (M2'deki Yenikapı). Çeviri burada yapılıyor ve iki
    // durağın da aynı hatta olması bir yan etki değil, doğrulamanın
    // kendisi: farklı hatlardan iki durak aktarmasız oynanamaz.
    final origin = _stationOnLine(challenge.lineId, challenge.originId);
    final destination = _stationOnLine(
      challenge.lineId,
      challenge.destinationId,
    );
    if (origin == null || destination == null) {
      return const ChallengeResolution.failure(ChallengeError.unknownRoute);
    }

    final result = routes.estimate(origin.id, destination.id);
    final journey = result.journey;
    if (journey == null) {
      return const ChallengeResolution.failure(ChallengeError.unknownRoute);
    }

    // Süre **karekodtan** alınır, yerel hesaptan değil.
    //
    // İki cihazın metro verisi farklı sürümde olabilir ve yolculuğun
    // uzunluğu adaletin parçası: meydan okuyan 14 dakika oynadıysa kabul
    // eden de 14 dakika oynamalı. Yerel süre yalnızca akla yatkınlık
    // denetimi için kullanılıyor.
    final drift = (journey.estimatedSeconds - challenge.estimatedSeconds).abs();
    if (drift > _maxDriftSeconds) {
      return const ChallengeResolution.failure(ChallengeError.unknownRoute);
    }

    return ChallengeResolution.success(
      challenge: challenge,
      game: game,
      journey: Journey(
        origin: origin,
        destination: destination,
        estimatedSeconds: challenge.estimatedSeconds,
        stopCount: journey.stopCount,
        difficulty: journey.difficulty,
        lineId: journey.lineId,
      ),
    );
  }

  /// İki cihazın süre hesabı arasındaki kabul edilebilir en büyük fark.
  ///
  /// Sıfır olamaz: veri dosyasındaki bir kenar süresi düzeltilirse eski
  /// meydan okumalar geçersiz olurdu. Çok büyük de olamaz, yoksa elle
  /// yazılmış bir süre oyunu uzatıp hedefi kolaylaştırır. Beş dakika,
  /// veri düzeltmelerini kapsayıp kötüye kullanıma yer bırakmıyor.
  static const int _maxDriftSeconds = 300;

  Station? _stationOnLine(String lineId, String canonicalId) {
    for (final station in metro.stationsOfLine(lineId)) {
      if (station.canonicalId == canonicalId) return station;
    }
    return null;
  }

  /// Bir yolculuktan kanonik durak kimliklerini okur.
  ///
  /// Meydan okuma üretirken kullanılır: karekoda hat kapsamlı kimlik değil
  /// fiziksel durak girer, böylece karşı taraf aynı durağı başka bir hat
  /// kaydından da bulabilir.
  static ({String origin, String destination}) canonicalPair(Journey journey) =>
      (
        origin: journey.origin.canonicalId,
        destination: journey.destination.canonicalId,
      );
}

/// Doğrulama sonucu.
class ChallengeResolution {
  const ChallengeResolution.success({
    required this.challenge,
    required this.game,
    required this.journey,
  }) : error = null;

  const ChallengeResolution.failure(this.error)
    : challenge = null,
      game = null,
      journey = null;

  final Challenge? challenge;
  final MiniGame? game;
  final Journey? journey;
  final ChallengeError? error;

  bool get isValid => challenge != null && journey != null && game != null;
}
