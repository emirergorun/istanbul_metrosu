import 'dart:math';

/// Simit Kap'ın saf kuralları: martı fiziği, simit geometrisi, zorluk.
///
/// Flutter içe aktarmaz. Dünya birimi **sahne yüksekliği**: 0 tepe, 1 dip.
/// Yatayda aynı birim kullanılıyor; böylece sahne kartının eni telefona
/// göre değişse de fizik, simit aralığı ve puan temposu değişmiyor — dar
/// ekranda yalnız ileriyi biraz daha az görürsün.

/// Martının sahnenin sol kenarından uzaklığı.
///
/// Telefonda sahne kartı ~0,68 birim genişliğinde: martı soldan üçte bir
/// içeride. Önünde ~0,45 birim kalıyor, simitler arası mesafeden fazla —
/// sıradaki simit her zaman ekranda, bir sonrakinin ucu da görünüyor.
const double simitCatchBirdX = 0.22;

/// Martının çarpışma yarıçapı.
///
/// Çizilen gövdeden küçük: kanat ucunun kenara sürtmesi "çarptım" diye
/// okunmuyor, oyuncu yalnız gövdenin değdiğini çarpma sayıyor.
const double simitCatchBirdRadius = 0.028;

/// Simit kabuğunun (kenarının) kalınlık yarıçapı.
const double simitCatchRimRadius = 0.016;

/// Deniz yüzeyi: martının altı buraya değerse oyun biter.
const double simitCatchSeaLevel = 0.87;

/// Simitlerin dikeyde durabileceği bant.
///
/// Üstte kanat çırpacak, altta denize düşmeden simidin içinden süzülecek
/// pay kalsın.
const double simitCatchTopLane = 0.24;
const double simitCatchBottomLane = 0.70;

/// Simit sahneye martının bu kadar önünde girer — en geniş telefonda bile
/// sağ kenarın dışında doğsun diye.
const double simitCatchSpawnAhead = 1.15;

/// Kenara çarpınca dikey hızın ne kadarı geri döner.
///
/// Flappy Dunk'taki topun kenardan sekişi: tam sekme oyuncuyu fırlatıyor,
/// hiç sekmemek de çarpmayı yumuşak bir duvar gibi gösteriyordu.
const double simitCatchBounce = 0.45;

/// TAM İSABET serisinin puana katkısının üst sınırı.
///
/// Seri dört TAM İSABET'ten sonra büyümeyi bırakır: +2, +3, +4, +5, +5 …
/// Sınırsız seri usta oyuncuyu rota rekorunun kestirme yoluna çevirirdi
/// (ortak puanın usta tavanı, bkz. `GameScoreProfiles.expertCeiling`).
const int simitCatchMaxStreakBonus = 4;

/// Zorluğun tepe noktası: bu kadar simitten sonra oyun daha zorlaşmaz.
const int simitCatchHardenAfter = 40;

/// Martının ilk kanadı beklediği sırada sahne durur.
///
/// Flappy türünün alışkanlığı: oyuncu hazır olunca başlar. Yolculuğun
/// saati bu sırada da işler; beklemek puan getirmez.
enum SimitCatchPhase { waiting, flying }

/// Oyunu ne bitirdi — sonuç panelinin başlığı buna göre.
enum SimitCatchEnd { missed, sea }

/// Bir simidin akıbeti.
enum SimitState { ahead, passed, missed }

/// Zorluk ayarı: geçilen simit sayısıyla sertleşir.
///
/// Ray Uçuşu'ndaki ders burada da geçerli: zorluk yolculuğun uzunluğuna
/// değil oyuncunun ilerleyişine bağlı. Herkes kolaydan başlar; uzun rotayı
/// seçen oyuncu ilk simitten en zor ayarla cezalandırılmaz.
class SimitCatchConfig {
  const SimitCatchConfig({
    required this.gravity,
    required this.flapVelocity,
    required this.speed,
    required this.spacing,
    required this.halfWidth,
    required this.maxRise,
  });

  factory SimitCatchConfig.forSimits(int passed) {
    final t = (passed / simitCatchHardenAfter).clamp(0.0, 1.0);
    double lerp(double easy, double hard) => easy + (hard - easy) * t;
    return SimitCatchConfig(
      gravity: lerp(1.5, 1.62),
      flapVelocity: lerp(-0.56, -0.58),
      speed: lerp(0.27, 0.34),
      spacing: lerp(0.5, 0.42),
      halfWidth: lerp(0.105, 0.088),
      maxRise: lerp(0.14, 0.26),
    );
  }

  /// Aşağı ivme (birim/sn²).
  final double gravity;

  /// Kanat çırpınca atanan dikey hız (eksi yukarı).
  final double flapVelocity;

  /// Sahnenin sola akış hızı (birim/sn).
  final double speed;

  /// Ardışık iki simit arasındaki yatay mesafe.
  final double spacing;

  /// Simidin yarı genişliği (merkezden kenar halkasının ortasına).
  final double halfWidth;

  /// İki simit arasındaki en büyük yükseklik farkı.
  final double maxRise;
}

/// Sahnedeki bir simit. Konumu **dünya** koordinatında: `x` sahnenin
/// başından beri kat edilen yol cinsinden, kayma değil.
class Simit {
  Simit({
    required this.id,
    required this.x,
    required this.y,
    required this.halfWidth,
    required this.tilt,
  });

  /// Sırası; ilk simit 0.
  final int id;
  final double x;
  final double y;
  final double halfWidth;

  /// Görsel ve çarpışma eğimi (radyan, artı saat yönü). Simitler hafif
  /// yan yatık durur; düz bir halka sahnede çember yerine çizgi gibi
  /// görünüyordu.
  final double tilt;

  SimitState state = SimitState.ahead;

  /// Martı bu simidin kenarına değdi mi? Değmişse geçiş TAM İSABET
  /// sayılmaz.
  bool touched = false;

  /// Sol ve sağ kenar halkasının merkezi.
  Point<double> get leftRim =>
      Point<double>(x - halfWidth * cos(tilt), y - halfWidth * sin(tilt));
  Point<double> get rightRim =>
      Point<double>(x + halfWidth * cos(tilt), y + halfWidth * sin(tilt));

  /// Halkanın açıklığının (iki kenarı birleştiren çizginin) [atX]'teki
  /// yüksekliği.
  double lineYAt(double atX) => y + (atX - x) * tan(tilt);

  /// [atX] simidin açıklığının içinde mi (kenar halkaları hariç)?
  bool opensAt(double atX) =>
      (atX - x).abs() < (halfWidth - simitCatchRimRadius) * cos(tilt);

  /// Simit martının tamamen gerisinde kaldı mı?
  bool behind(double birdX) =>
      max(leftRim.x, rightRim.x) + simitCatchRimRadius <
      birdX - simitCatchBirdRadius;
}

/// Bir geçişin puanı (ölçeksiz).
///
/// TAM İSABET'te `1 + seri` (seri bu geçişle birlikte), kenara değen
/// geçişte 1.
int simitCatchPoints({required bool swish, required int streak}) =>
    swish ? 1 + min(streak, simitCatchMaxStreakBonus) : 1;
