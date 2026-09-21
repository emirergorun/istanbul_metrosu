import 'package:flutter/foundation.dart';

/// En yüksek hat. 2048'in kazanma karosu 2048 = 2^11, yani M11.
/// Uygulamadaki diğer oyunlar da M1-M11 merdivenini kullanıyor.
const int metroMergeMaxRank = 11;

/// 2048'in klasik tahtası 4×4'tür ve oyunun zorluk dengesi buna göre
/// kurulmuştur: daha büyük tahtada taşlar neredeyse hiç sıkışmaz, oyun
/// bitmez ve gerilim kaybolur. Eskiden yolculuk zorluğuna göre 4/5/6
/// değişiyordu; "birebir 2048" istendiği için sabitlendi.
const int metroMergeGridSize = 4;

const List<String> metroMergeLineLabels = <String>[
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

@immutable
class MetroTile {
  const MetroTile({required this.rank});

  /// 1 = M1 (2048'deki "2"), 2 = M2 ("4") … 11 = M11 ("2048").
  final int rank;

  /// 2048'deki sayısal değer: M1=2, M2=4, M3=8 … M11=2048.
  /// Puanlama bunu kullanır (2048'de birleşen karonun değeri kadar puan
  /// yazılır).
  int get value => 1 << rank;

  int get lineIndex => (rank - 1).clamp(0, metroMergeLineLabels.length - 1);
  String get lineLabel => metroMergeLineLabels[lineIndex];
}

enum MetroMoveDirection { left, up, right, down }

/// Bir kaydırmada tek bir karonun yolculuğu: nereden nereye.
///
/// Tahta yalnızca hamle **sonrasını** bilseydi karolar yeni yerlerine
/// ışınlanırdı. 2048'in hissi, karoların eski hücrelerinden yenilerine
/// kaymasından geliyor; çizim bunun için her karonun iki ucunu bilmeli.
/// Birleşen iki karo aynı hedefe gider.
@immutable
class MetroTileMove {
  const MetroTileMove({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    required this.rank,
  });

  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;

  /// Kayarken taşıdığı hat (birleşmeden **önceki** değer).
  final int rank;

  @override
  bool operator ==(Object other) =>
      other is MetroTileMove &&
      other.fromRow == fromRow &&
      other.fromCol == fromCol &&
      other.toRow == toRow &&
      other.toCol == toCol &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(fromRow, fromCol, toRow, toCol, rank);

  @override
  String toString() => 'M$rank ($fromRow,$fromCol)→($toRow,$toCol)';
}

@immutable
class MetroMergeConfig {
  const MetroMergeConfig({this.gridSize = metroMergeGridSize});

  final int gridSize;
}

@immutable
class MetroMoveOutcome {
  const MetroMoveOutcome({
    required this.accepted,
    this.gainedPoints = 0,
    this.merges = 0,
    this.highestRank = 0,
    this.reachedTarget = false,
    this.beatRecord = false,
  });

  const MetroMoveOutcome.rejected() : this(accepted: false);

  /// Hamle tahtayı değiştirdi mi? 2048'de değiştirmeyen hamle **hamle
  /// sayılmaz**: yeni karo doğmaz, puan yazılmaz.
  final bool accepted;

  final int gainedPoints;
  final int merges;

  /// Bu hamleden sonra tahtadaki en yüksek hat.
  final int highestRank;

  /// Bu hamlede ilk kez M11'e (2048) ulaşıldı mı?
  final bool reachedTarget;

  final bool beatRecord;
}
