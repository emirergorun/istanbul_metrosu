import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

const int mergeDropMinLevel = 1;
const int mergeDropMaxLevel = 11;

/// Tehlike çizgisi tepeye biraz daha yakın: havuzun kullanılabilir boyu
/// azaldı, oyun daha çabuk biter. Önce 0.15 → 0.18 (11 seviyeye çıkarken),
/// sonra 0.18 → 0.20 (genel zorluk artışı) olarak sıkılaştırıldı.
const double mergeDropDangerLine = 0.20;

/// Havuzun en/boy oranı (yükseklik / genişlik) — **sabit**.
///
/// Havuz eskiden sahne görselinin (PNG) içindeki elle ölçülmüş bir
/// dikdörtgendi ve oranı ~1,03 çıkıyordu. Artık Flutter çiziyor; oran
/// ekran boyundan bağımsız sabit tutuluyor çünkü oran zorluğun kendisi:
/// uzun havuz daha geç taşar. Değer eski ölçüme yakın seçildi ki oyunun
/// zorluğu değişmesin; meydan okumada iki cihaz aynı havuzda oynar.
const double mergeDropPoolAspect = 1.04;

const List<String> mergeDropLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
  'M8',
  'M9',
  'M10',
  'M11',
];

/// Geometrik oranla büyüyen yarıçap dizisi (~×1.16 her seviyede) — M1-M7
/// arası önceki değerlerle birebir aynı, M8-M11 aynı oranla devam eder.
const List<double> mergeDropRadii = <double>[
  0.045,
  0.055,
  0.067,
  0.080,
  0.094,
  0.110,
  0.128,
  0.148,
  0.172,
  0.200,
  0.232,
];

/// Doğan parçanın seviye ağırlıkları (M1, M2, M3, M4).
///
/// Simülasyonla seçildi (`test/balance/merge_drop_spawn_report_test.dart`).
/// Eşit dağılım (1:1:1:1) havuza erken M4 yığıyordu: büyük parçalar
/// boşluğu doldurduğu için ortalama koşu kısa, M8+ nadirdi. Küçük
/// parçaların daha sık gelmesi oyuncuya birleştirme malzemesi veriyor;
/// M4 hâlâ geliyor ama sürpriz olarak.
const List<int> mergeDropSpawnWeights = <int>[4, 3, 2, 1];

/// Bir birleşmenin ham puanı: yeni parçanın seviyesiyle **katlanarak** artar.
///
/// Mantık: bir üst seviye, iki alt seviyeden doğar. M8'i kurmak 64 tane
/// M2'lik emek demek; doğrusal puan (eski `seviye × 10`) M8'i M2'nin yalnız
/// dört katı sayıyordu. Şimdi her seviye bir öncekinin iki katı:
/// M2 10, M5 80, M8 640, M11 5120. Zincirin her halkası çarpanı
/// [mergeDropChainStep] kadar büyütür, [mergeDropChainCap]'te durur.
int mergeDropMergePoints(int level, {int chain = 1}) {
  final base = 10 * (1 << (level - 2).clamp(0, 30));
  final multiplier = min(
    1 + mergeDropChainStep * (chain - 1),
    mergeDropChainCap,
  );
  return (base * multiplier).round();
}

/// Zincirin her ek halkasının puan çarpanına katkısı.
const double mergeDropChainStep = 0.25;

/// Zincir çarpanının tavanı.
const double mergeDropChainCap = 2.0;

/// Birleşmeden doğan bir parçanın zincire bağlanabileceği süre (saniye).
///
/// Ölçümle: birleşen parça ortalama 0,1-0,6 saniyede komşusuna değiyor.
/// 0,9 saniye, yuvarlanıp duran bir parçayı da sayıyor; ondan sonraki
/// birleşme oyuncunun yeni bıraktığı parçanın işi, zincir değil.
const double mergeDropChainWindow = 0.9;

/// Tehlike durumu: çizim ve ses buna bakar.
enum MergeDropDanger {
  /// Yığın çizgiden uzak.
  calm,

  /// Oturmuş bir parça çizgiye yaklaştı.
  near,

  /// Oturmuş bir parça çizgiyi aştı; bekleme sayacı işliyor.
  critical,
}

/// Bir birleşmenin çizim için gereken her şeyi.
@immutable
class MergeDropEvent {
  const MergeDropEvent({
    required this.level,
    required this.x,
    required this.y,
    required this.parentA,
    required this.parentB,
    required this.points,
    required this.chain,
    required this.newRunMax,
  });

  /// Doğan parçanın seviyesi.
  final int level;

  /// Doğduğu yer (dünya birimi).
  final double x;
  final double y;

  /// Birleşen iki parçanın merkezleri (dünya birimi) — çizim onları
  /// birleşme noktasına doğru çekip söndürür.
  final (double, double) parentA;
  final (double, double) parentB;

  /// Yolculuğa yazılan puan (ölçek uygulanmış, ekrandaki birim).
  final int points;

  /// Zincir halkası: 1 = tek birleşme, 2+ = zincir.
  final int chain;

  /// Bu koşunun yeni en büyük hattı mı?
  final bool newRunMax;
}

@immutable
class DropBall {
  const DropBall({
    required this.id,
    required this.level,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.settled = false,
    this.pop = 1,
    this.chain = 0,
    this.bornAt = 0,
  });

  final int id;
  final int level;
  final double x;
  final double y;
  final double vx;
  final double vy;

  /// Top gerçekten **oturdu** mu: altında bir dayanak (zemin ya da merkezi
  /// daha aşağıda olan başka bir top) var ve neredeyse duruyor.
  ///
  /// Her karede yeniden hesaplanır; yapışkan bir bayrak değildir.
  ///
  /// Bu ayrım kritik: eskiden bu alan "herhangi bir şeye değdi" anlamına
  /// geliyordu ve çarpışma çözücüsü havada birbirine sürten iki topa bile
  /// bunu basıyordu. Doğum noktası tehlike çizgisinin üstünde olduğu için,
  /// arka arkaya bırakılan iki top doğarken birbirine değince oyun yarım
  /// saniyede bitiyordu. Kaybetme koşulu artık yalnızca gerçekten yığına
  /// oturmuş toplara bakıyor.
  final bool settled;

  /// Bu parçayı doğuran birleşmenin zincir halkası; bırakılan parçada 0.
  final int chain;

  /// Doğduğu an (koşu saati, saniye) — zincir penceresi buna bakar.
  final double bornAt;

  String get label => mergeDropLabelForLevel(level);
  double get radius => mergeDropRadiusForLevel(level);

  /// Alanla orantılı kütle (düzgün 2B yoğunluk varsayımı).
  ///
  /// Çarpışma çözümü bunu kullanır: büyük bir top küçük bir topla
  /// çarpıştığında eşit değil, kütleyle ters orantılı ölçüde yer değiştirir
  /// — aksi hâlde M1 bir top M7'yi kendisiyle aynı miktarda itebilir, bu da
  /// "ağırlık" hissini tamamen ortadan kaldırır.
  double get mass => radius * radius;

  DropBall copyWith({
    int? id,
    int? level,
    double? x,
    double? y,
    double? vx,
    double? vy,
    bool? settled,
    double? pop,
    int? chain,
    double? bornAt,
  }) {
    return DropBall(
      id: id ?? this.id,
      level: level ?? this.level,
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      settled: settled ?? this.settled,
      pop: pop ?? this.pop,
      chain: chain ?? this.chain,
      bornAt: bornAt ?? this.bornAt,
    );
  }

  /// Hız büyüklüğü — oturma kararında kullanılır.
  double get speed => sqrt(vx * vx + vy * vy);

  /// Birleşme "yutma" animasyonunun ilerlemesi: 0 = yeni doğdu, 1 = bitti.
  ///
  /// Yalnızca **çizim** için; fizik her zaman tam [radius] ile çalışır.
  /// agar.io'da bir hücre bir diğerini yuttuğunda anında yer değiştirmez,
  /// gözle görülür biçimde şişer — bu alan o hissi verir. Fizik yarıçapını
  /// da büyütmek yığını her birleşmede iteklerdi.
  final double pop;

  /// Çizimde kullanılacak yarıçap: 0,9'dan doğar, 1,08'e aşar, oturur.
  ///
  /// Eskiden 0,62'den başlıyordu: yeni parça önce küçülüp sonra büyüyor,
  /// birleşme "söndü, sonra şişti" gibi okunuyordu. 0,9 başlangıç yeni
  /// parçanın iki eskisinden **büyük** doğduğunu hissettiriyor.
  double get drawRadius {
    if (pop >= 1) return radius;
    final t = pop.clamp(0.0, 1.0);
    final eased = t < 0.55
        ? 0.9 + (1.08 - 0.9) * Curves.easeOutCubic.transform(t / 0.55)
        : 1.08 - 0.08 * Curves.easeInOutCubic.transform((t - 0.55) / 0.45);
    return radius * eased;
  }
}

String mergeDropLabelForLevel(int level) {
  final index = (level - 1).clamp(0, mergeDropLabels.length - 1);
  return mergeDropLabels[index];
}

double mergeDropRadiusForLevel(int level) {
  final index = (level - 1).clamp(0, mergeDropRadii.length - 1);
  return mergeDropRadii[index];
}
