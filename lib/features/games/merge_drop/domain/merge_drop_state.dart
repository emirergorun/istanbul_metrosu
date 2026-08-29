import 'package:flutter/foundation.dart';

const int mergeDropMinLevel = 1;
const int mergeDropMaxLevel = 7;

/// Tehlike çizgisi tepeye biraz daha yakın: havuzun kullanılabilir boyu
/// azaldı, oyun daha çabuk biter.
const double mergeDropDangerLine = 0.15;

const List<String> mergeDropLabels = <String>[
  'M1',
  'M2',
  'M3',
  'M4',
  'M5',
  'M6',
  'M7',
];

const List<double> mergeDropRadii = <double>[
  0.045,
  0.055,
  0.067,
  0.080,
  0.094,
  0.110,
  0.128,
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
    this.landed = false,
  });

  final int id;
  final int level;
  final double x;
  final double y;
  final double vx;
  final double vy;

  /// Top zemine ya da başka bir topa hiç değdi mi?
  ///
  /// Bırakılan bir top, havuzun en üstünde (tehlike çizgisinin de üstünde)
  /// doğar ve düşerek çizgiyi geçer — bu yüzden "tehlike çizgisine değme"
  /// kontrolü yalnızca **oturmuş** (en az bir kez temas etmiş) toplara
  /// uygulanmalı; yoksa her bırakışta anında kaybedilir.
  final bool landed;

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
    bool? landed,
  }) {
    return DropBall(
      id: id ?? this.id,
      level: level ?? this.level,
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      landed: landed ?? this.landed,
    );
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
