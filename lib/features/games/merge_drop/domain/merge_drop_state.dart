import 'dart:math';

import 'package:flutter/foundation.dart';

const int mergeDropMinLevel = 1;
const int mergeDropMaxLevel = 11;

/// Tehlike çizgisi tepeye biraz daha yakın: havuzun kullanılabilir boyu
/// azaldı, oyun daha çabuk biter. Önce 0.15 → 0.18 (11 seviyeye çıkarken),
/// sonra 0.18 → 0.20 (genel zorluk artışı) olarak sıkılaştırıldı.
const double mergeDropDangerLine = 0.20;

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

  /// Çizimde kullanılacak yarıçap: hafif bir aşma ile şişer, sonra oturur.
  double get drawRadius {
    if (pop >= 1) return radius;
    final t = pop.clamp(0.0, 1.0);
    // 0.62'den başlayıp 1.08'e kadar aşar, sonra 1'e iner.
    final eased = t < 0.6
        ? 0.62 + (1.08 - 0.62) * (t / 0.6)
        : 1.08 - 0.08 * ((t - 0.6) / 0.4);
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
