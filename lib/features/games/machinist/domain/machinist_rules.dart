import 'dart:math' as math;

/// Makinist'in saf kuralları: tren fiziği, durak dizilimi, duruş notu.
///
/// Flutter içe aktarmaz; controller bunları çağırır, çizici yalnız okur.
/// Uzunluklar metre, hızlar m/s, süreler saniye.
class MachinistRules {
  const MachinistRules._();

  /// Azami hız: 20 m/s = 72 km/sa. İstanbul metrolarında işletme hızı
  /// 70-80 km/sa bandında; oyunda fren mesafesi okunur kalsın diye alt uç.
  static const double maxSpeed = 20;

  /// Tam gazda kalkış ivmesi. Hız arttıkça azalır ([throttleAt]).
  static const double throttleAccel = 1.3;

  /// Tam frende yavaşlama. 20 m/s'den durmak ~100 m sürer: "3" uyarısı
  /// (150 m) geldiğinde hâlâ tam hızdaysan frene basmanın zamanı gelmiştir.
  static const double brakeDecel = 2.0;

  /// Pedal bırakıldığında trenin kendi kendine yavaşlaması (sürtünme).
  static const double coastDrag = 0.06;
  static const double airDrag = 0.0011;

  /// Pedallar anında tam güce çıkmaz; basınç kısa sürede dolar. Kısa
  /// dokunuşla ince ayar yapılabilsin diye.
  /// Kumanda kolunun her yöndeki kademe sayısı: P1–P4 ve B1–B4.
  static const int leverNotches = 4;

  static const double throttleRampSeconds = 0.3;
  static const double brakeRampSeconds = 0.35;

  /// Tren: iki vagon. Kamera arkadan baktığı için uzun tren durak
  /// işaretini ekranda küçültüyordu.
  static const double carLength = 18.5;
  static const double carGap = 0.8;
  static const int carCount = 2;
  static const double trainLength = carCount * carLength + carGap;

  /// Peron boyu ve durak işaretinin peron sonuna uzaklığı.
  static const double platformLength = 70;
  static const double stopMarkerFromPlatformEnd = 5;

  /// İstasyon holünün peronun iki ucundan taşan payı.
  static const double hallMargin = 6;

  /// Durak işaretinden bu kadar uzakta durulursa duruş sayılır.
  static const double stopTolerance = 6;

  /// Durak işaretini bu kadar geçen tren durağı kaçırmış sayılır.
  static const double missDistance = 14;

  /// Oyun bu kadar kaçırılan durakta biter.
  static const int maxMisses = 3;

  /// Sarı ışık ve "istasyon yaklaşıyor" uyarısı bu mesafede başlar.
  static const double approachWarning = 320;

  /// 3-2-1 geri sayımının eşikleri (durak işaretine kalan metre).
  static const double countdown3 = 150;
  static const double countdown2 = 90;
  static const double countdown1 = 40;
  static const double countdownStop = 6;

  /// Kapıların açılması, yolcu binişi ve kapanması.
  static const double doorOpenSeconds = 0.8;
  static const double boardingSeconds = 2.2;
  static const double doorCloseSeconds = 0.8;
  static const double dwellSeconds =
      doorOpenSeconds + boardingSeconds + doorCloseSeconds;

  /// İki durak işareti arası mesafe aralığı.
  static const double minStationGap = 460;
  static const double maxStationGap = 640;

  /// Verilen hızda tam gazın ivmesi: hız arttıkça motor gücü azalır.
  static double throttleAt(double speed) =>
      throttleAccel * (1 - 0.65 * (speed / maxSpeed).clamp(0.0, 1.0));

  /// Pedal bırakılınca etkiyen yavaşlama.
  static double dragAt(double speed) =>
      speed <= 0 ? 0 : coastDrag + airDrag * speed * speed;

  /// Tam frenle durma mesafesi.
  static double brakingDistance(double speed) =>
      speed * speed / (2 * brakeDecel);

  /// Durak işaretine [distance] metre kala 3-2-1 sayacının değeri.
  ///
  /// `null`: sayaç yok. `0`: "DUR" anı.
  static int? countdownFor(double distance) {
    if (distance > countdown3 || distance < -stopTolerance) return null;
    if (distance > countdown2) return 3;
    if (distance > countdown1) return 2;
    if (distance > countdownStop) return 1;
    return 0;
  }
}

/// Duruşun notu: durak işaretine uzaklığa göre.
enum StopGrade {
  perfect('MÜKEMMEL', 60, 0.5),
  great('ÇOK İYİ', 44, 1.5),
  good('İYİ', 28, 3),
  fair('İDARE EDER', 14, MachinistRules.stopTolerance);

  const StopGrade(this.label, this.points, this.maxError);

  final String label;

  /// Ham puan; yolcu ve seri bonusu ayrıca eklenir.
  final int points;

  /// Bu nota giren en büyük sapma (m).
  final double maxError;

  /// Sapmanın notu; tolerans dışıysa `null`.
  static StopGrade? forError(double error) {
    final e = error.abs();
    for (final grade in values) {
      if (e <= grade.maxError) return grade;
    }
    return null;
  }

  /// Seriyi sürdüren duruş mu?
  bool get keepsStreak => this == perfect || this == great;
}

enum StationState { pending, served, missed }

/// Hat üstündeki bir istasyon. Konumlar trenin **ön ucu** cinsinden.
class MachinistStation {
  MachinistStation({
    required this.index,
    required this.name,
    required this.stopPos,
    required this.passengers,
    required this.curve,
    this.state = StationState.pending,
  });

  final int index;
  final String name;

  /// Trenin ön ucunun durması gereken nokta.
  final double stopPos;

  /// Peronda bekleyen yolcu.
  final int passengers;

  /// Bu istasyondan sonraki tünelin yanal kıvrımı (m, işaretli).
  final double curve;

  StationState state;

  double get platformEnd => stopPos + MachinistRules.stopMarkerFromPlatformEnd;
  double get platformStart => platformEnd - MachinistRules.platformLength;
  double get hallStart => platformStart - MachinistRules.hallMargin;
  double get hallEnd => platformEnd + MachinistRules.hallMargin;
}

/// Tünelin yanal kıvrımı: iki istasyon arasında yumuşak bir S.
///
/// İstasyonlarda düz (0), aralarda `(1 - cos)/2` tümseği. Türevi uçlarda
/// sıfır, yani ray kırılmadan döner.
double trackOffsetAt(List<MachinistStation> stations, double z) {
  for (var i = 0; i + 1 < stations.length; i++) {
    final a = stations[i];
    final b = stations[i + 1];
    if (z < a.hallEnd) return 0;
    if (z < b.hallStart) {
      final t = (z - a.hallEnd) / (b.hallStart - a.hallEnd);
      return a.curve * (1 - math.cos(2 * math.pi * t)) / 2;
    }
  }
  return 0;
}
