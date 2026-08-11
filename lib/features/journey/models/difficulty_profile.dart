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

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DifficultyProfile && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DifficultyProfile($id)';
}

/// Prototip zorluk konfigürasyonu — `01 - MVP` tablosundan.
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
  );

  static const DifficultyProfile short = DifficultyProfile(
    id: 'short',
    label: 'Kısa',
    minMinutes: 6,
    maxMinutes: 10,
    initialBlockerRatio: 0.0,
    hardPieceWeight: 0.10,
    undoCount: 1,
  );

  static const DifficultyProfile standard = DifficultyProfile(
    id: 'standard',
    label: 'Standart',
    minMinutes: 11,
    maxMinutes: 20,
    initialBlockerRatio: 0.04,
    hardPieceWeight: 0.18,
    undoCount: 1,
  );

  static const DifficultyProfile long = DifficultyProfile(
    id: 'long',
    label: 'Uzun',
    minMinutes: 21,
    maxMinutes: 35,
    initialBlockerRatio: 0.08,
    hardPieceWeight: 0.25,
    undoCount: 0,
  );

  static const DifficultyProfile marathon = DifficultyProfile(
    id: 'marathon',
    label: 'Maraton',
    minMinutes: 36,
    maxMinutes: null,
    initialBlockerRatio: 0.12,
    hardPieceWeight: 0.32,
    undoCount: 0,
  );

  static const List<DifficultyProfile> all = <DifficultyProfile>[
    mini,
    short,
    standard,
    long,
    marathon,
  ];
}
