import '../../../data/metro/metro_repository.dart';
import '../../games/catalog/mini_game.dart';
import '../../journey/models/journey.dart';
import '../../journey/models/station.dart';
import '../../journey/services/route_service.dart';
import 'daily_mission.dart';
import 'daily_plan.dart';
import 'daily_seed.dart';
import 'day_stamp.dart';

/// Günün yolculuğunu, oyununu ve görevlerini üretir.
///
/// Üretimin tamamı takvim gününden türer: aynı gün her zaman aynı planı
/// verir, uygulama kaç kez açılırsa açılsın. Plan diske yazılmaz — yazılsaydı
/// iki kaynak (kayıt ve üretim) olur ve biri bayatlardı.
class DailyGenerator {
  const DailyGenerator({required this.metro, required this.routes});

  final MetroRepository metro;
  final RouteService routes;

  /// Günün rotasının en az ve en çok kaç durak olacağı.
  ///
  /// Alt sınır 3: iki duraklık bir yolculuk birkaç dakika sürüyor ve
  /// "günün yolculuğu" demeye değmiyor. Üst sınır 8: uçtan uca bir hat
  /// yarım saati buluyor, günlük bir alışkanlık için fazla uzun.
  static const int minStops = 3;
  static const int maxStops = 8;

  /// [day] için planı üretir. Metro verisi oynanabilir rota vermiyorsa `null`.
  ///
  /// [undiscoveredStations] verilirse keşif görevi oyuncunun gerçekten
  /// keşfedebileceği kadarını ister; bkz. [missionsFor].
  DailyPlan? planFor(DayStamp day, {int? undiscoveredStations}) {
    final journey = _journeyFor(day);
    if (journey == null) return null;
    return DailyPlan(
      day: day,
      journey: journey,
      gameId: gameIdFor(day),
      missions: missionsFor(day, undiscoveredStations: undiscoveredStations),
    );
  }

  /// Günün rotası. Hiçbir hat oynanabilir rota vermezse `null`.
  Journey? _journeyFor(DayStamp day) {
    final lines = metro.lines();
    if (lines.isEmpty) return null;

    final seed = DailySeed.forDay(day, salt: 'route');
    final start = seed.nextInt(lines.length);
    final originOffset = seed.nextInt(1 << 20);
    final stopsOffset = seed.nextInt(1 << 20);
    final reversed = seed.nextInt(2) == 1;

    // Seçilen hattan başlayıp **sırayla** tüm hatlar denenir. Bir hat veri
    // eksikliği yüzünden rota vermezse gün boş kalmaz; deneme sırası
    // tohumdan geldiği için sonuç yine deterministiktir.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[(start + i) % lines.length];
      final stations = metro.stationsOfLine(line.id);
      if (stations.length < minStops + 1) continue;

      final maxSpan = stations.length - 1;
      final span = maxStops < maxSpan ? maxStops : maxSpan;
      final stops = minStops + stopsOffset % (span - minStops + 1);
      final originIndex = originOffset % (stations.length - stops);

      final first = stations[originIndex];
      final second = stations[originIndex + stops];
      final Station origin = reversed ? second : first;
      final Station destination = reversed ? first : second;

      final result = routes.estimate(origin.id, destination.id);
      final journey = result.journey;
      if (journey != null) return journey;
    }
    return null;
  }

  /// Günün oyunu.
  ///
  /// Gün sayısı üzerinden **sabit adımla** ilerler: adım oyun sayısıyla
  /// aralarında asal seçildiği için tüm oyunlar sırayla gelir ve arka arkaya
  /// iki gün aynı oyun düşmez. Rastgele seçim ikisini de garanti etmezdi.
  String gameIdFor(DayStamp day) {
    final games = MiniGames.playable;
    if (games.isEmpty) return MiniGames.blocks.id;
    final step = _coprimeStep(games.length);
    final index = (day.epochDay * step) % games.length;
    return games[index < 0 ? index + games.length : index].id;
  }

  /// [count] ile aralarında asal, 1'den büyük en küçük adım.
  ///
  /// 1'den büyük olması arka arkaya iki günün farklı oyun almasını sağlar;
  /// aralarında asal olması her oyunun sıraya girmesini. İkisi birden
  /// sağlanamıyorsa (iki oyun kaldığında) 1'e düşer ve sıra yine döner.
  static int _coprimeStep(int count) {
    for (var step = 3; step < count; step++) {
      if (_gcd(step, count) == 1) return step;
    }
    return 1;
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// Günün üç görevi.
  ///
  /// İlki her zaman günün yolculuğu: gün bunun üzerine kurulu ve seri de
  /// buna bakıyor. Kalan ikisi diğer türlerden çekilir, tekrar etmez.
  /// [undiscoveredStations]: oyuncunun keşfetmediği durak sayısı.
  ///
  /// `null` ise keşif durumu bilinmiyor demektir ve görev havuzu olduğu gibi
  /// kullanılır (saf üretim; testler ve plan önizlemesi bu yoldan geçer).
  ///
  /// Verilirse iki kural işler ve ikisi de **tek yönlü**: keşif hiç geri
  /// gitmediği için bir gün içinde görevi zorlaştıracak bir değişim mümkün
  /// değil.
  ///
  /// 1. Keşfedilmemiş durak kalmadıysa keşif görevi havuzdan düşer.
  ///    İstanbul'un tamamını gezmiş oyuncuya "4 yeni istasyon keşfet"
  ///    demek, 0/4'te sonsuza kadar duran bir görev üretiyordu.
  /// 2. Kalan durak hedeften azsa hedef ona kırpılır. Kırpma yalnız
  ///    kolaylaştırır; tamamlanmış bir ilerlemeyi geçersizleştiremez.
  List<DailyMission> missionsFor(DayStamp day, {int? undiscoveredStations}) {
    final seed = DailySeed.forDay(day, salt: 'missions');
    final exhausted =
        undiscoveredStations != null && undiscoveredStations <= 0;
    final pool = <DailyMissionType>[
      DailyMissionType.completeJourney,
      DailyMissionType.playGames,
      DailyMissionType.playDistinctGames,
      if (!exhausted) DailyMissionType.discoverStations,
    ];

    final missions = <DailyMission>[
      const DailyMission(type: DailyMissionType.dailyJourney, target: 1),
    ];
    for (var i = 0; i < 2 && pool.isNotEmpty; i++) {
      final type = pool.removeAt(seed.nextInt(pool.length));
      var target = _targetFor(type, seed);
      if (type == DailyMissionType.discoverStations &&
          undiscoveredStations != null &&
          undiscoveredStations < target) {
        target = undiscoveredStations;
      }
      missions.add(DailyMission(type: type, target: target));
    }
    return List<DailyMission>.unmodifiable(missions);
  }

  /// Görev hedefleri **kısa bir oturumda** bitecek kadar küçük.
  ///
  /// Günlük görev bir alışkanlık kancasıdır, bir iş değil: yirmi oyun ya da
  /// olağanüstü bir skor isteyen görev oyuncuyu geri getirmez, kaçırır.
  static int _targetFor(DailyMissionType type, DailySeed seed) =>
      switch (type) {
        DailyMissionType.dailyJourney => 1,
        DailyMissionType.completeJourney => 1,
        DailyMissionType.playGames => 2 + seed.nextInt(2),
        DailyMissionType.playDistinctGames => 2,
        DailyMissionType.discoverStations => 3 + seed.nextInt(3),
      };
}
