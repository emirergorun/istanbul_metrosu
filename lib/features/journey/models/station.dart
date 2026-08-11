import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Tek bir metro istasyonu.
///
/// [order] istasyonun **kendi hattı üzerindeki** sırasıdır; şehir genelinde
/// global bir sıra değildir. Aynı fiziksel durak birden fazla hatta hizmet
/// veriyorsa (ör. Yenikapı) her hat için ayrı bir [Station] kaydı vardır.
@immutable
class Station {
  const Station({
    required this.id,
    required this.name,
    required this.lineId,
    required this.order,
  });

  final String id;
  final String name;
  final String lineId;
  final int order;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Station && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Station($id, $name, $lineId#$order)';
}

/// Bir metro hattı.
@immutable
class MetroLine {
  const MetroLine({
    required this.id,
    required this.name,
    required this.color,
    required this.oneWayMinutes,
    required this.stationCount,
  });

  /// Hat kodu: `M2`, `M1A` ...
  final String id;

  /// `Yenikapı – Hacıosman`
  final String name;

  /// Hattın resmi rengi (Metro İstanbul ağ haritasından).
  ///
  /// Bu renk **kimlik** taşır: rozet, tren, ray ve ilerleme göstergesi.
  /// Arayüzün aksiyon rengi değildir — o sabittir.
  /// TODO(PROD): Resmi hat renklerinin ticari kullanımı için marka incelemesi.
  final Color color;

  /// Resmi tek yön sefer süresi (dakika).
  final int oneWayMinutes;

  final int stationCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MetroLine && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MetroLine($id, $name)';
}
