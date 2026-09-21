import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/telemetry/analytics.dart';
import '../domain/discovery_catalog.dart';

/// Bir keşif yazımının sonucu.
///
/// Sayaçların kendisi değil, **geçişler** taşınır: arayüz yalnızca yeni olanı
/// kutlar, zaten bilineni değil.
@immutable
class DiscoveryResult {
  const DiscoveryResult({required this.stations, required this.completedLines});

  static const DiscoveryResult empty = DiscoveryResult(
    stations: <CanonicalStation>[],
    completedLines: <String>[],
  );

  /// Bu yazımda **ilk kez** keşfedilen duraklar, uğranılan sırayla.
  final List<CanonicalStation> stations;

  /// Bu yazımla eksikten tama geçen hatlar.
  final List<String> completedLines;

  bool get isEmpty => stations.isEmpty;
  bool get isNotEmpty => stations.isNotEmpty;
}

/// İstanbul keşfinin **tek** kalıcı durumu.
///
/// Saklanan tek şey keşfedilen fiziksel durak kimlikleridir. Yüzdeler,
/// sayaçlar ve "hat tamamlandı" bilgisi türetilir; hiçbiri diske yazılmaz.
/// Aksi hâlde metro.json'a bir hat eklendiğinde kayıtlı yüzdeler yalan
/// söylerdi.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.catalog,
    this.store,
    this.analytics = const NoopAnalytics(),
    this.onDiscovered,
  }) {
    _restore();
  }

  final DiscoveryCatalog catalog;
  final LocalStore? store;
  final Analytics analytics;

  /// Yeni durak keşfedildiğinde haber verilecek yer.
  ///
  /// Keşif kaydı "yeni durak" sorusunun **tek** doğru cevabıdır: çağrıya
  /// yalnızca ömründe ilk kez açılan duraklar ulaşır. Günlük görevler bunu
  /// dinliyor; kendi sayacını tutsaydı aynı rota tekrar oynandığında
  /// ilerleme üretir ve keşif kaydından ayrı düşerdi.
  ///
  /// Bu sınıf dinleyenin kim olduğunu bilmez ve dönüşüne bakmaz.
  final ValueChanged<DiscoveryResult>? onDiscovered;

  final Set<String> _discovered = <String>{};

  /// Hat başına keşfedilen durak sayısı.
  ///
  /// Türetilmiş ama **önbelleğe alınmış** değer: keşif ekranı her karede on
  /// hattın durak listesini baştan tarıyordu (kart başına üç tarama, artı
  /// küresel özet için bir tarama daha). Sayaç yazma anında güncellenince
  /// okuma O(1)'e düşüyor.
  ///
  /// Diske **yazılmaz**: kalıcı olan yalnız [_discovered]. Bu harita her
  /// açılışta ondan yeniden kurulur, dolayısıyla metro.json değişse bile
  /// bayatlayamaz.
  final Map<String, int> _lineDiscovered = <String, int>{};

  /// Keşfedilen **aktarma** durağı sayısı.
  ///
  /// [_lineDiscovered] ile aynı gerekçe: pasaport başarımı bunu okuyor ve
  /// her keşif bildiriminde 143 durağı baştan taramak gereksizdi. Yazma
  /// anında güncelleniyor, okuma O(1). Diske yazılmaz; her açılışta
  /// [_discovered] kümesinden yeniden kurulur.
  int _interchangeDiscovered = 0;

  void _restore() {
    final saved = store?.discoveredStationIds;
    if (saved != null) {
      for (final id in saved) {
        // Katalogda olmayan kimlik yok sayılır: veri dosyasından bir hat
        // kalkarsa uygulama çökmemeli, yalnızca o durak sayılmamalı.
        if (catalog.stationById(id) != null) _discovered.add(id);
      }
    }
    _recountLines();
  }

  /// Hat sayaçlarını [_discovered] kümesinden baştan kurar.
  void _recountLines() {
    _lineDiscovered.clear();
    _interchangeDiscovered = 0;
    for (final id in _discovered) {
      final station = catalog.stationById(id);
      if (station == null) continue;
      if (station.isInterchange) _interchangeDiscovered++;
      for (final lineId in station.lineIds) {
        _lineDiscovered[lineId] = (_lineDiscovered[lineId] ?? 0) + 1;
      }
    }
  }

  // --- Türetilen görünüm ---

  bool isDiscovered(String canonicalId) => _discovered.contains(canonicalId);

  /// Keşfedilen fiziksel durak sayısı.
  int get discoveredCount => _discovered.length;

  /// Keşfedilebilir toplam durak sayısı — veriden gelir, sabit yazılmaz.
  int get totalCount => catalog.totalCount;

  /// Henüz keşfedilmemiş durak sayısı.
  ///
  /// Günlük keşif görevi bunu okuyor: kalan durak hedeften azsa hedef
  /// kırpılıyor, hiç kalmadıysa görev hiç üretilmiyor.
  int get undiscoveredCount => totalCount - discoveredCount;

  /// Keşfedilen aktarma durağı sayısı — önbellekten, O(1).
  int get interchangeDiscoveredCount => _interchangeDiscovered;

  /// 0.0 – 1.0. Payda 0 ise (veri yok) 0 döner.
  double get progress =>
      totalCount == 0 ? 0 : (discoveredCount / totalCount).clamp(0.0, 1.0);

  /// Gösterilecek tam sayı yüzde.
  ///
  /// `round` değil `floor`: 142/143 oyuncuya %100 diye görünürse son durak
  /// keşfedilmemişken keşif bitmiş sanılır.
  int get percent => (progress * 100).floor();

  int lineDiscoveredCount(String lineId) => _lineDiscovered[lineId] ?? 0;

  int lineTotalCount(String lineId) => catalog.lineTotalCount(lineId);

  double lineProgress(String lineId) {
    final total = lineTotalCount(lineId);
    if (total == 0) return 0;
    return (lineDiscoveredCount(lineId) / total).clamp(0.0, 1.0);
  }

  bool isLineComplete(String lineId) {
    final total = lineTotalCount(lineId);
    return total > 0 && lineDiscoveredCount(lineId) == total;
  }

  /// Keşfi tamamlanan hat sayısı.
  int completedLineCount(Iterable<String> lineIds) =>
      lineIds.where(isLineComplete).length;

  bool get isComplete => totalCount > 0 && discoveredCount == totalCount;

  // --- Yazma ---

  /// Verilen durakları keşfedilmiş işaretler ve geçişleri döndürür.
  ///
  /// Zaten keşfedilmiş bir durak sessizce yok sayılır: aynı rotayı tekrar
  /// oynamak sayacı artırmaz, bildirim üretmez, diske yazmaz. Aynı durağı
  /// iki kez vermek de tek keşif sayılır.
  DiscoveryResult discoverAll(Iterable<String> canonicalIds, {String? gameId}) {
    final fresh = <CanonicalStation>[];
    final touchedLines = <String>{};

    for (final id in canonicalIds) {
      if (_discovered.contains(id)) continue;
      final station = catalog.stationById(id);
      if (station == null) continue;
      _discovered.add(id);
      fresh.add(station);
      if (station.isInterchange) _interchangeDiscovered++;
      for (final lineId in station.lineIds) {
        _lineDiscovered[lineId] = (_lineDiscovered[lineId] ?? 0) + 1;
        touchedLines.add(lineId);
      }
    }
    if (fresh.isEmpty) return DiscoveryResult.empty;

    // Tamamlanma **sonradan** bakılır: aynı yazımda bir hattın son iki
    // durağı birden gelebilir, o hat tek seferde tamamlanır.
    //
    // "Daha önce duyurdum mu" diye bakmaya gerek yok ve bir zamanlar duran
    // o kontrol ölü koddu: [touchedLines] yalnızca **yeni** keşfedilen
    // durakların hatlarını taşır, yani o hat bu çağrıdan önce zorunlu
    // olarak eksikti. Tamamlanma her hat için ömründe bir kez üretilebilir.
    final completed = <String>[
      for (final lineId in touchedLines)
        if (isLineComplete(lineId)) lineId,
    ]..sort();

    for (final station in fresh) {
      analytics.log(
        AnalyticsEvent.stationDiscovered,
        params: <String, String>{
          'line_id': station.lineIds.join('/'),
          'game_id': ?gameId,
        },
      );
    }
    for (final lineId in completed) {
      analytics.log(
        AnalyticsEvent.lineCompleted,
        params: <String, String>{'line_id': lineId, 'game_id': ?gameId},
      );
    }

    // Tek yazma: on durak birden geçilse bile diske bir kez gidilir.
    unawaited(_persist());
    _notifyCoalesced();
    final result = DiscoveryResult(stations: fresh, completedLines: completed);
    onDiscovered?.call(result);
    return result;
  }

  // --- Bildirim ---

  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Kare başına **tek** bildirim gönderir.
  ///
  /// İki gerekçesi var ve ikisi de tek başına yeterli:
  ///
  /// 1. **Doğruluk.** Biniş durağı, oyun ekranı `didChangeDependencies`
  ///    içinde `start()` çağırdığı anda keşfedilir — yani build sırasında.
  ///    O anda doğrudan `notifyListeners` çağırmak ana ekrandaki keşif
  ///    şeridini build sırasında yeniden çizmeye zorlar; Flutter bunu hata
  ///    sayar ("setState() called during build").
  /// 2. **Verim.** Tek karede dört durak birden geçilebilir (ilerleme
  ///    sıçraması). Her biri ayrı bildirim üretseydi keşif ekranı tek
  ///    karede dört kez yeniden çizilirdi.
  ///
  /// Mikro görev kuyruğu kare tamamlanmadan işlenmez; bildirim bir sonraki
  /// güvenli anda ve **bir kez** gider. `SchedulerBinding` kullanılmadı:
  /// saf birim testinde binding kurulu olmayabilir.
  ///
  /// Daha derin çözüm yedi oyun ekranının `start()` çağrısını build'in
  /// dışına (`addPostFrameCallback`) almak olurdu; bu, ilk karenin anlamını
  /// ve ona bakan mevcut testleri değiştirir. Birleştirme hem bugünkü
  /// hatayı kapatıyor hem de kendi başına doğru davranış.
  void _notifyCoalesced() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  // --- Kalıcılık ---

  Future<void> _persist() async {
    try {
      await store?.saveDiscoveredStations(_discovered);
    } catch (error, stack) {
      debugPrint('Keşif kaydı yazılamadı: $error\n$stack');
    }
  }

  /// Bekleyen yazımı tamamlar.
  ///
  /// Keşif yazımı oyun karesini bekletmemek için beklenmeden bırakılıyor.
  /// iOS arka plandaki uygulamayı haber vermeden sonlandırabildiği için
  /// uygulama arka plana düşerken bu çağrı bir kez daha, **beklenerek**
  /// yapılır; aksi hâlde son durak, yazımı tamamlanmadan öldürülen bir
  /// oturumda kaybolur.
  ///
  /// Kümenin tamamı yazıldığı için ikinci yazım zararsız: aynı içerik
  /// ikinci kez diske gider.
  Future<void> flush() => _persist();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Testte temiz bir başlangıç için.
  @visibleForTesting
  void debugReset() {
    _discovered.clear();
    _recountLines();
    _notifyCoalesced();
  }
}
