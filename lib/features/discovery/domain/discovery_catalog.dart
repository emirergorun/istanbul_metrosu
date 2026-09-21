import 'package:flutter/foundation.dart';

import '../../../data/metro/metro_repository.dart';
import '../../journey/models/journey.dart';
import '../../journey/models/station.dart';

/// Keşfedilebilir **fiziksel** durak.
///
/// [Station] hat kapsamlıdır: Yenikapı üç kez geçer, çünkü M1A, M1B ve M2
/// üzerindeki sırası farklıdır. Keşif ise fiziksel durağı sayar, o yüzden
/// burada Yenikapı bir kez vardır ve üç hattı birden taşır.
@immutable
class CanonicalStation {
  const CanonicalStation({
    required this.id,
    required this.name,
    required this.lineIds,
  });

  /// [Station.canonicalId].
  final String id;

  final String name;

  /// Bu durağın hizmet verdiği hatlar, veri dosyasındaki sırayla.
  ///
  /// Birden fazlaysa durak bir aktarma noktasıdır ve keşfedildiğinde
  /// **hepsinin** tamamlanma oranına sayılır.
  final List<String> lineIds;

  bool get isInterchange => lineIds.length > 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CanonicalStation && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CanonicalStation($id, $name, ${lineIds.join("/")})';
}

/// Metro verisinden türetilen keşif kataloğu.
///
/// Toplam durak sayısı **hiçbir yerde sabit yazılmaz**; metro.json'a bir hat
/// eklendiğinde keşif hedefi kendiliğinden büyür. Katalog uygulama açılışında
/// bir kez kurulur, oyun sırasında JSON'a dönülmez.
// Alanlar private, parametreler public: `this._stations` dışarıdan
// çağrılamayacak bir ad üretirdi.
// ignore_for_file: prefer_initializing_formals
class DiscoveryCatalog {
  DiscoveryCatalog._({
    required List<CanonicalStation> stations,
    required Map<String, List<CanonicalStation>> byLine,
    required Map<String, CanonicalStation> byId,
    required Map<String, List<Station?>> byOrder,
  }) : _stations = stations,
       _byLine = byLine,
       _byId = byId,
       _byOrder = byOrder;

  /// Depodaki hatları tarayıp fiziksel durakları tekilleştirir.
  factory DiscoveryCatalog.fromRepository(MetroRepository repository) {
    final byId = <String, CanonicalStation>{};
    final order = <String>[];
    final lineMembers = <String, List<String>>{};
    final byOrder = <String, List<Station?>>{};

    for (final line in repository.lines()) {
      final members = <String>[];
      final lineStations = repository.stationsOfLine(line.id);
      if (lineStations.isNotEmpty) {
        // Rota çözümü `order` ile indekslenir, liste sırasıyla değil: veri
        // dosyasında bir gün boşluk kalırsa rota sessizce kaymasın.
        final maxOrder = lineStations
            .map((Station s) => s.order)
            .reduce((int a, int b) => a > b ? a : b);
        final slots = List<Station?>.filled(maxOrder + 1, null);
        for (final station in lineStations) {
          slots[station.order] = station;
        }
        byOrder[line.id] = slots;
      }
      for (final station in lineStations) {
        final existing = byId[station.canonicalId];
        if (existing == null) {
          byId[station.canonicalId] = CanonicalStation(
            id: station.canonicalId,
            name: station.name,
            lineIds: <String>[line.id],
          );
          order.add(station.canonicalId);
        } else if (!existing.lineIds.contains(line.id)) {
          byId[station.canonicalId] = CanonicalStation(
            id: existing.id,
            name: existing.name,
            lineIds: <String>[...existing.lineIds, line.id],
          );
        }
        // Aynı hatta aynı fiziksel durak iki kez geçmez; geçse bile
        // tamamlanma oranı bozulmasın diye listeye bir kez yazılır.
        if (!members.contains(station.canonicalId)) {
          members.add(station.canonicalId);
        }
      }
      lineMembers[line.id] = members;
    }

    final stations = <CanonicalStation>[for (final id in order) byId[id]!];
    final byLine = <String, List<CanonicalStation>>{
      for (final entry in lineMembers.entries)
        entry.key: <CanonicalStation>[for (final id in entry.value) byId[id]!],
    };

    return DiscoveryCatalog._(
      stations: List<CanonicalStation>.unmodifiable(stations),
      byLine: Map<String, List<CanonicalStation>>.unmodifiable(byLine),
      byId: Map<String, CanonicalStation>.unmodifiable(byId),
      byOrder: Map<String, List<Station?>>.unmodifiable(byOrder),
    );
  }

  final List<CanonicalStation> _stations;
  final Map<String, List<CanonicalStation>> _byLine;
  final Map<String, CanonicalStation> _byId;
  final Map<String, List<Station?>> _byOrder;

  /// Keşfedilebilir tüm duraklar.
  List<CanonicalStation> get stations => _stations;

  /// Keşif hedefinin paydası.
  int get totalCount => _stations.length;

  /// Katalogdaki hat kimlikleri, veri dosyasındaki sırayla.
  ///
  /// Hat listesini metro deposundan ayrıca istemek gerekmesin diye burada:
  /// keşfin paydası da, tamamlanan hat sayısı da aynı kaynaktan çıkmalı.
  Iterable<String> get lineIds => _byLine.keys;

  CanonicalStation? stationById(String canonicalId) => _byId[canonicalId];

  /// Hattın durakları, hat üzerindeki sırayla.
  List<CanonicalStation> stationsOfLine(String lineId) =>
      _byLine[lineId] ?? const <CanonicalStation>[];

  int lineTotalCount(String lineId) => stationsOfLine(lineId).length;

  /// Rotanın **sırayla** uğradığı fiziksel durak kimlikleri.
  ///
  /// İlk eleman biniş durağı, son eleman iniş durağıdır. Yön veriden değil
  /// rotadan okunur: iniş durağı biniş durağından önce geliyorsa liste ters
  /// çevrilmiş olarak döner.
  ///
  /// `index` ile `stationsPassed` birebir örtüşür: `routeStationIds(j)[n]`,
  /// n durak geçildiğinde varılan duraktır.
  List<String> routeStationIds(Journey journey) {
    final lineStations = _lineStationsOrdered(journey.lineId);
    if (lineStations.isEmpty) return const <String>[];

    final origin = journey.origin.order;
    final destination = journey.destination.order;
    final step = destination >= origin ? 1 : -1;

    final ids = <String>[];
    for (var order = origin; ; order += step) {
      if (order < 0 || order >= lineStations.length) break;
      final station = lineStations[order];
      if (station == null) break;
      ids.add(station.canonicalId);
      if (order == destination) break;
      if (order + step < 0 || order + step >= lineStations.length) break;
    }
    return ids;
  }

  List<Station?> _lineStationsOrdered(String lineId) =>
      _byOrder[lineId] ?? const <Station?>[];
}
