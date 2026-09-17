import 'package:flutter/foundation.dart';

/// Yolculuk süresinden türeyen oyun zorluk profili.
///
/// Profil **hedef skor içermez**: oyunun amacı o rotadaki kendi rekorunu
/// geçmektir. Profil yalnızca tahtanın ne kadar sıkışık başladığını, hangi
/// parçaların geldiğini ve geri alma hakkını belirler.
///
/// Bu değerler tuning başlangıç değerleridir, nihai denge değildir.
@immutable
class DifficultyProfile {
  const DifficultyProfile({
    required this.id,
    required this.label,
    required this.minMinutes,
    required this.maxMinutes,
    required this.initialBlockerRatio,
    required this.hardPieceWeight,
    required this.undoCount,
    this.trayCandidates = 1,
  });

  final String id;
  final String label;
  final int minMinutes;

  /// `null` => üst sınır yok (maraton).
  final int? maxMinutes;

  /// Oyun başında rastgele dolu (engel) hücre oranı. 0.0 - 1.0
  final double initialBlockerRatio;

  /// Zor parça havuzundan seçilme olasılığı. 0.0 - 1.0
  final double hardPieceWeight;

  /// Kullanıcıya verilen geri alma hakkı.
  final int undoCount;

  /// Tahta sıkışıkken denenecek aday tepsi sayısı.
  ///
  /// 1 ise tepsi tek seferde üretilir (eski davranış). Daha büyük değerlerde
  /// generator birkaç aday üretip **en çok hamle imkânı sunanı** seçer.
  ///
  /// Oyunu kolaylaştırmak için değil, **haksız diziyi elemek** için var:
  /// tahta doluyken rastgele üç parçanın hiçbirinin işe yaramaması sık
  /// oluyor ve oyun oyuncunun hatasından değil şanssızlıktan bitiyordu.
  /// Uzun yolculuk daha çok hamle gerektirdiği için şanssızlığa daha çok
  /// maruz kalır; bu yüzden değer yolculuk uzadıkça artar — zorluğun
  /// yolculuk uzunluğuyla ters orantılı olması kararıyla aynı yönde.
  final int trayCandidates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DifficultyProfile && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DifficultyProfile($id)';
}

/// Zorluk konfigürasyonu.
///
/// **Zorluk yolculuk uzunluğuyla ters orantılıdır.** İlk sürümde tersiydi:
/// uzun yolculuğa daha çok engel ve daha zor parça veriliyordu. Oysa uzun
/// yolculukta zaten hayatta kalmak zor — ölçüm, 14 dakikanın üstünde varış
/// oranının %0'a düştüğünü gösterdi. Artık yolculuk uzadıkça parçalar
/// kolaylaşır ve geri alma hakkı artar.
///
/// **Başlangıç engelleri tamamen kaldırıldı** (tüm profillerde 0). Tahtayı
/// baştan daraltmak yalnızca hayatta kalma süresini kısaltıyordu; ölçümde
/// engelsiz Maraton medyanı 160'tan 275'e çıkmıştı. Mekanizma
/// `applyInitialBlockers` içinde duruyor, ileride bir "zor mod" istenirse
/// yeniden açılabilir.
///
/// **Denge kurtarıcı parçayla birlikte yeniden kuruldu.** Tahtada az
/// kalmış bir hat varken tepsinin onu kapatabilen parçayı vermesi
/// (`PieceGenerator.rescueChance`) hayatta kalmayı belirgin şekilde
/// uzattı: varış oranları hedefin çok üstüne çıktı. Üç koldan geri
/// çekildi — yolculuk kazancı düşürüldü, aday tepsi sayısı azaltıldı ve
/// uzun yolculuklarda zor parça oranı yükseltildi.
///
/// Zor parça oranındaki artış eski "zorluk yolculuk uzadıkça azalır"
/// kararıyla çelişmiyor, onu tamamlıyor: o karar uzun yolculuklarda varış
/// oranı %0-3 iken alınmıştı. Bugün oyuncuyu ayakta tutan iş kurtarıcı
/// parçada; parça havuzu artık zorluğu geri getirmek için kullanılıyor.
///
/// `balance_report_test`, 150 oyun, 7 sn hamle aralığı:
///
/// | Profil | Zor oran | Aday | Varış% | Erken% |
/// |---|---|---|---|---|
/// | Mini | 0,05 | 1 | %100 | %8 |
/// | Kısa | 0,10 | 1 | %80 | %13 |
/// | Standart | 0,14 | 2 | %41 | %12 |
/// | Uzun | 0,105 | 3 | %23 | %9 |
/// | Maraton | 0,088 | 4 | %9 | %7 |
///
/// Erken% = yolculuğun iyi oyunla kazanılan payı. Hızlı oynayanda (4 sn
/// hamle aralığı) varış oranları düşer: Standart %19, Uzun %7, Maraton %1.
/// Hızlı oynamak tahtayı hızlı doldurur; bu ceza değil, oyunun mantığı.

class DifficultyProfiles {
  const DifficultyProfiles._();

  static const DifficultyProfile mini = DifficultyProfile(
    id: 'mini',
    label: 'Mini',
    minMinutes: 0,
    maxMinutes: 5,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.05,
    undoCount: 1,
    trayCandidates: 1,
  );

  static const DifficultyProfile short = DifficultyProfile(
    id: 'short',
    label: 'Kısa',
    minMinutes: 6,
    maxMinutes: 10,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.1,
    undoCount: 1,
    trayCandidates: 1,
  );

  static const DifficultyProfile standard = DifficultyProfile(
    id: 'standard',
    label: 'Standart',
    minMinutes: 11,
    maxMinutes: 20,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.14,
    undoCount: 2,
    trayCandidates: 2,
  );

  static const DifficultyProfile long = DifficultyProfile(
    id: 'long',
    label: 'Uzun',
    minMinutes: 21,
    maxMinutes: 35,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.105,
    undoCount: 3,
    trayCandidates: 3,
  );

  static const DifficultyProfile marathon = DifficultyProfile(
    id: 'marathon',
    label: 'Maraton',
    minMinutes: 36,
    maxMinutes: null,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.088,
    undoCount: 4,
    trayCandidates: 4,
  );

  static const List<DifficultyProfile> all = <DifficultyProfile>[
    mini,
    short,
    standard,
    long,
    marathon,
  ];
}
