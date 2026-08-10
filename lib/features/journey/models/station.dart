import 'package:flutter/foundation.dart';

/// Tek bir metro istasyonu.
///
/// MVP'de tek hat (M2) kullanılır; [order] hat üzerindeki sıradır.
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

/// Bir metro hattı. MVP'de sadece M2 var.
@immutable
class MetroLine {
  const MetroLine({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  final String id;
  final String name;

  /// Hattın accent rengi (ARGB). Resmi marka görseli/logosu kullanılmaz;
  /// yalnızca nötr bir accent rengi tutulur.
  /// TODO(PROD): Resmi hat renklerini kullanmadan önce marka/kullanım hakkı incelemesi yapılmalı.
  final int colorValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MetroLine && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
