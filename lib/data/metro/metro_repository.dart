import '../../features/journey/models/edge.dart';
import '../../features/journey/models/station.dart';
import 'edges.dart';
import 'stations.dart';

/// Metro datasına tek erişim noktası.
///
/// UI ve oyun kodu doğrudan `stations.dart` / `edges.dart` dosyalarını
/// bilmez; sadece bu arayüzü bilir. Production data katmanı geldiğinde
/// yalnızca bu sınıfın implementasyonu değişir.
abstract class MetroRepository {
  List<Station> stations();
  List<Edge> edges();
  Station? stationById(String id);
  MetroLine? lineById(String id);
}

/// Uygulama paketine gömülü (offline) implementasyon.
class BundledMetroRepository implements MetroRepository {
  const BundledMetroRepository();

  @override
  List<Station> stations() => MetroData.stations;

  @override
  List<Edge> edges() => MetroEdges.all;

  @override
  Station? stationById(String id) {
    for (final station in MetroData.stations) {
      if (station.id == id) return station;
    }
    return null;
  }

  @override
  MetroLine? lineById(String id) {
    for (final line in MetroData.lines) {
      if (line.id == id) return line;
    }
    return null;
  }
}
