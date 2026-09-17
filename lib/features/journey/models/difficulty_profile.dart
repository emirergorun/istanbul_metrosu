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
/// **[trayCandidates] hedef varış oranlarına göre ayarlandı.** Durakta
/// kalabalık satırların boşalması kaldırılınca (oyuncuya tahta her durakta
/// sıfırlanıyormuş gibi görünüyordu) uzun yolculuklarda varış oranı %5'e
/// düştü. Tahtaya dokunmadan, yalnızca haksız tepsiyi eleyerek dengelendi.
///
/// Arcade parça seti (3x3 kare, 2x3/3x2 dikdörtgen, 5'li çubuk, S/Z)
/// eklendikten sonra yeniden ölçüldü: büyük parçalar tahtayı hızlı
/// doldurduğu için aday sayısı ve yolculuk kazancı birlikte artırıldı.
/// `balance_report_test`, 150 oyun, 7 sn hamle aralığı:
///
/// | Profil | Aday | Varış% | Erken% |
/// |---|---|---|---|
/// | Mini | 2 | %99 | %19 |
/// | Kısa | 4 | %55 | %21 |
/// | Standart | 8 | %44 | %20 |
/// | Uzun | 9 | %21 | %15 |
/// | Maraton | 9 | %11 | %12 |
///
/// Erken% = yolculuğun iyi oyunla kazanılan payı. Hızlı oynayanda (4 sn
/// hamle aralığı) varış oranları düşer, erken varış payı artar: Standart
/// %29, Uzun %7, Maraton %3. Hızlı oynamak tahtayı hızlı doldurur; bu
/// ceza değil, oyunun kendi mantığı.

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
    trayCandidates: 2,
  );

  static const DifficultyProfile short = DifficultyProfile(
    id: 'short',
    label: 'Kısa',
    minMinutes: 6,
    maxMinutes: 10,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.1,
    undoCount: 1,
    trayCandidates: 4,
  );

  static const DifficultyProfile standard = DifficultyProfile(
    id: 'standard',
    label: 'Standart',
    minMinutes: 11,
    maxMinutes: 20,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.12,
    undoCount: 2,
    trayCandidates: 8,
  );

  static const DifficultyProfile long = DifficultyProfile(
    id: 'long',
    label: 'Uzun',
    minMinutes: 21,
    maxMinutes: 35,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.08,
    undoCount: 3,
    trayCandidates: 9,
  );

  static const DifficultyProfile marathon = DifficultyProfile(
    id: 'marathon',
    label: 'Maraton',
    minMinutes: 36,
    maxMinutes: null,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.05,
    undoCount: 4,
    trayCandidates: 9,
  );

  static const List<DifficultyProfile> all = <DifficultyProfile>[
    mini,
    short,
    standard,
    long,
    marathon,
  ];
}
