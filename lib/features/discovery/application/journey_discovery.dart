import 'package:flutter/foundation.dart';

import '../../journey/models/journey.dart';
import '../domain/discovery_catalog.dart';
import 'discovery_controller.dart';

/// Tek bir yolculuğun keşif defteri.
///
/// Yolculuk motoru ile kalıcı keşif durumu arasındaki **tek** köprüdür.
/// Oyunlar buraya bakmaz; motor "kaç durak geçildi" der, gerisini bu sınıf
/// çözer. Böylece yedi oyunun hiçbirinde durak kimliği, kalıcı depo veya
/// keşif kuralı geçmez.
///
/// Rotanın sırası veriden okunur: `Kadıköy → Ayrılık Çeşmesi → ...`. Ters
/// yönde oynanan rota ters listedir, ayrı bir kural gerekmez.
class JourneyDiscovery extends ChangeNotifier {
  JourneyDiscovery({
    required this.journey,
    required this.discovery,
    required this.gameId,
  }) : _routeIds = discovery.catalog.routeStationIds(journey) {
    // Boş rota, keşfin o yolculukta **sessizce ölmesi** demek: oyun normal
    // oynanır, hiçbir durak keşfedilmez, hiçbir hata da görünmez. Tek
    // sebebi metro verisindeki bir tutarsızlık olabilir (hattın kendisi
    // yok, ya da `order` alanları boşluklu), o yüzden geliştirme
    // derlemesinde yüksek sesle düşer.
    assert(
      _routeIds.length >= 2,
      'Rota çözülemedi: ${journey.lineId} ${journey.origin.id} -> '
      '${journey.destination.id}. Metro verisinde hat ya da durak sırası '
      'eksik olabilir.',
    );
  }

  final Journey journey;
  final DiscoveryController discovery;
  final String gameId;

  /// Rotanın uğradığı fiziksel duraklar, biniş durağından iniş durağına.
  final List<String> _routeIds;

  /// Şu ana kadar **ulaşıldığı bildirilen** en büyük durak indeksi.
  ///
  /// −1: henüz oyun başlamadı, biniş durağı bile sayılmadı. Rota seçmek
  /// keşif üretmez; bu alanın −1'de durması o kuralın kendisidir.
  int _reachedIndex = -1;

  final List<CanonicalStation> _newStations = <CanonicalStation>[];
  final List<String> _completedLines = <String>[];
  final Set<String> _newIds = <String>{};

  /// Bu **defter** açıldığından beri keşfedilenler; [reset] silmez.
  ///
  /// Oyuncu yolculuğu yarıda yeniden başlatırsa önceki denemede kazandığı
  /// duraklar kalıcı kalır ama [newStations] listesinden düşer — sonuç
  /// paneli "bu koşuda" derken doğru söyler, oysa oyuncunun oturduğu
  /// oturumda kazandığı toplam daha fazladır. Panel ikisi farklıysa
  /// oturum toplamını da yazar.
  final List<CanonicalStation> _sessionStations = <CanonicalStation>[];

  /// Bu yolculukta **ilk kez** keşfedilen duraklar, uğranılan sırayla.
  List<CanonicalStation> get newStations =>
      List<CanonicalStation>.unmodifiable(_newStations);

  /// Bu yolculukta tamamlanan hatlar.
  List<String> get completedLines => List<String>.unmodifiable(_completedLines);

  int get newStationCount => _newStations.length;

  /// Bu ekranda, yeniden başlatmalar dahil keşfedilen toplam durak.
  int get sessionStationCount => _sessionStations.length;

  /// Yeniden başlatma yüzünden sonuç panelinde görünmeyen keşif var mı?
  bool get hasHiddenSessionDiscoveries => sessionStationCount > newStationCount;

  /// Bu durak **bu koşuda** mı keşfedildi?
  ///
  /// Kalıcı duruma değil koşuya bakar: şerit yalnızca oyuncunun az önce
  /// kazandığı durağı "yeni" diye gösterir, üç gün önce keşfedileni değil.
  bool isNewInRun(String canonicalId) => _newIds.contains(canonicalId);

  /// Her yeni keşifte artan sayaç — arayüz bunu bir kez görür.
  int pulse = 0;

  /// Rotanın toplam durak sayısı (biniş durağı dahil).
  int get routeLength => _routeIds.length;

  /// [stationsPassed] durak geçilmiş hâle gelindiğini bildirir.
  ///
  /// Sıçramaya dayanıklıdır: ilerleme %21'den %49'a atlarsa aradaki **tüm**
  /// duraklar tek çağrıda işlenir. Geriye gitmez; aynı indeks iki kez
  /// bildirilirse ikincisi hiçbir şey yapmaz.
  ///
  /// Son durak buradan keşfedilemez: [reportArrival] çağrılmadıkça indeks
  /// rotanın sondan bir öncesinde durur. Yuvarlama yüzünden %99,6'da varış
  /// durağının açılmasını engelleyen sınır budur.
  void reportReached(int stationsPassed) {
    // İki duraktan kısa rota yok; olsaydı `clamp` alt sınırı üst sınırın
    // üstünde kalırdı.
    if (_routeIds.length < 2) return;
    _advanceTo(stationsPassed.clamp(0, _routeIds.length - 2));
  }

  /// Yolculuk gerçekten tamamlandı: son durak da keşfedilir.
  void reportArrival() {
    if (_routeIds.isEmpty) return;
    _advanceTo(_routeIds.length - 1);
  }

  void _advanceTo(int index) {
    if (index <= _reachedIndex) return;
    final reached = <String>[
      for (var i = _reachedIndex + 1; i <= index; i++) _routeIds[i],
    ];
    _reachedIndex = index;

    final result = discovery.discoverAll(reached, gameId: gameId);
    if (result.isEmpty) return;

    _newStations.addAll(result.stations);
    _sessionStations.addAll(result.stations);
    _newIds.addAll(result.stations.map((CanonicalStation s) => s.id));
    _completedLines.addAll(result.completedLines);
    pulse++;
    notifyListeners();
  }

  /// Yeniden oynanınca koşu defteri temizlenir.
  ///
  /// Kalıcı keşif **silinmez** — bu yalnızca "bu koşuda kaç yeni durak"
  /// sayacıdır. Yeniden başlayan oyuncu aynı durakları tekrar kazanmaz.
  void reset() {
    _reachedIndex = -1;
    _newStations.clear();
    _newIds.clear();
    _completedLines.clear();
    notifyListeners();
  }
}
