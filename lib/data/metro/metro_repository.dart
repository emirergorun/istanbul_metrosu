import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../features/journey/models/edge.dart';
import '../../features/journey/models/station.dart';

/// Metro datasına tek erişim noktası.
///
/// UI ve oyun kodu veri dosyasını bilmez; sadece bu arayüzü bilir.
/// Kaynak değiştiğinde (uzak sunucu, SQLite, canlı API) yalnızca
/// implementasyon değişir.
abstract class MetroRepository {
  List<MetroLine> lines();
  List<Station> stations();
  List<Edge> edges();

  /// Yalnızca verilen hattın istasyonları, hat sırasına göre.
  List<Station> stationsOfLine(String lineId);

  Station? stationById(String id);
  MetroLine? lineById(String id);
}

/// `assets/data/metro.json` dosyasından okunan, bellekte tutulan veri.
///
/// Veri kaynağı: metro.istanbul hat sayfaları (istasyon sırası, resmi tek yön
/// sefer süresi) ve resmi ağ haritası (hat renkleri).
class MetroDataset implements MetroRepository {
  MetroDataset._({
    required List<MetroLine> lines,
    required List<Station> stations,
    required this.edgeList,
  }) : _lines = lines,
       _stations = stations,
       _stationsById = <String, Station>{for (final s in stations) s.id: s},
       _linesById = <String, MetroLine>{for (final l in lines) l.id: l},
       _stationsByLine = _groupByLine(stations);

  final List<MetroLine> _lines;
  final List<Station> _stations;
  final List<Edge> edgeList;
  final Map<String, Station> _stationsById;
  final Map<String, MetroLine> _linesById;
  final Map<String, List<Station>> _stationsByLine;

  static Map<String, List<Station>> _groupByLine(List<Station> stations) {
    final map = <String, List<Station>>{};
    for (final station in stations) {
      (map[station.lineId] ??= <Station>[]).add(station);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    return map;
  }

  /// Varsayılan veri dosyasını yükler.
  static Future<MetroDataset> load({
    AssetBundle? bundle,
    String assetPath = 'assets/data/metro.json',
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    return parse(raw);
  }

  /// JSON metnini ayrıştırır. Test'te dosyaya gitmeden çağrılabilir.
  static MetroDataset parse(String rawJson) {
    final root = jsonDecode(rawJson) as Map<String, dynamic>;
    final rawLines = root['lines'] as List<dynamic>;

    final lines = <MetroLine>[];
    final stations = <Station>[];
    final edges = <Edge>[];

    for (final entry in rawLines) {
      final line = entry as Map<String, dynamic>;
      final id = line['id'] as String;
      final rawStations = line['stations'] as List<dynamic>;
      final segmentSeconds = line['segmentSeconds'] as int;

      lines.add(
        MetroLine(
          id: id,
          name: line['name'] as String,
          color: _parseColor(line['color'] as String),
          oneWayMinutes: line['oneWayMinutes'] as int,
          stationCount: rawStations.length,
        ),
      );

      for (var i = 0; i < rawStations.length; i++) {
        final station = rawStations[i] as Map<String, dynamic>;
        stations.add(
          Station(
            id: station['id'] as String,
            name: station['name'] as String,
            lineId: id,
            order: i,
          ),
        );

        if (i > 0) {
          final previous = rawStations[i - 1] as Map<String, dynamic>;
          edges.add(
            Edge(
              from: previous['id'] as String,
              to: station['id'] as String,
              seconds: segmentSeconds,
            ),
          );
        }
      }
    }

    return MetroDataset._(
      lines: List<MetroLine>.unmodifiable(lines),
      stations: List<Station>.unmodifiable(stations),
      edgeList: List<Edge>.unmodifiable(edges),
    );
  }

  static Color _parseColor(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  @override
  List<MetroLine> lines() => _lines;

  @override
  List<Station> stations() => _stations;

  @override
  List<Edge> edges() => edgeList;

  @override
  List<Station> stationsOfLine(String lineId) =>
      _stationsByLine[lineId] ?? const <Station>[];

  @override
  Station? stationById(String id) => _stationsById[id];

  @override
  MetroLine? lineById(String id) => _linesById[id];
}
