import '../../features/journey/models/edge.dart';
import 'stations.dart';

/// Komşu istasyonlar arası yaklaşık dakikalar.
///
/// `01 - MVP` notundaki prototip değerleri:
/// 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 2
class MetroEdges {
  const MetroEdges._();

  /// stations[i] -> stations[i+1] süresi (dakika).
  static const List<int> neighborMinutes = <int>[
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    3,
    2,
    2,
    2,
  ];

  /// Edge listesi. Tek hat olduğu için sıra numarasından üretilir.
  static final List<Edge> all = List<Edge>.unmodifiable(<Edge>[
    for (var i = 0; i < neighborMinutes.length; i++)
      Edge(
        from: MetroData.stations[i].id,
        to: MetroData.stations[i + 1].id,
        minutes: neighborMinutes[i],
      ),
  ]);
}
