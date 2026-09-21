import 'package:flutter/foundation.dart';

import '../journey/models/journey.dart';
import 'journey_status.dart';

/// Biten bir koşunun özeti.
///
/// Oyuna özgü hiçbir şey taşımaz: skor nasıl kazanıldı, kaç satır temizlendi,
/// kaç soru bilindi — hiçbiri. Yolculuk katmanının dışarıya söylediği tek
/// cümle "şu rotada, şu oyunla, şöyle bitti".
@immutable
class RunReport {
  const RunReport({
    required this.gameId,
    required this.journey,
    required this.status,
    required this.score,
    this.stationsPassed = 0,
  });

  /// Oynanan oyunun kalıcı kimliği.
  final String gameId;

  final Journey journey;

  /// Koşunun nasıl bittiği.
  final GameStatus status;

  final int score;

  /// Koşu boyunca geçilen durak sayısı.
  final int stationsPassed;

  /// Yolculuk sonuna kadar götürüldü mü?
  bool get arrived => status == GameStatus.arrived;

  /// Koşu kendi sonuna geldi mi? Yarıda bırakılan oyun sayılmaz.
  bool get isFinished =>
      status == GameStatus.arrived || status == GameStatus.gameOver;

  /// Koşu **sayılacak kadar oynandı mı?**
  ///
  /// Bitmiş olmak yetmiyor: Ray Uçuşu'nu açıp iki saniyede duvara çarpmak
  /// da teknik olarak "biten" bir koşu. "İki oyun bitir" görevi bu şekilde
  /// yirmi saniyede kırılabiliyordu.
  ///
  /// Eşik **bir durak**. Yolculuğun ölçüsü zaten durak; kısa günlük
  /// rotalarda bir durak yolun beşte biri kadar, yani oyuncu gerçekten
  /// oynamış oluyor. Varış her hâlükârda sayılır.
  bool get isMeaningful => isFinished && (arrived || stationsPassed >= 1);
}

/// Biten koşuları dinleyen taraf.
///
/// Yolculuk motoru bunu **çağırır ve unutur**; kimin dinlediğini, raporla ne
/// yapıldığını bilmez. Günlük görevler bugün bu arayüzü uyguluyor; yarın
/// başka bir sistem de uygulayabilir.
abstract class RunReporter {
  /// Yeni bir koşu başladı.
  ///
  /// Bekleyen kutlamaları temizlemek için: oyuncu görevi tamamlayıp oyunu
  /// yarıda bırakırsa sonuç paneli hiç açılmıyor ve "görev tamamlandı"
  /// satırı kuyrukta kalıp **bir sonraki** koşunun panelinde çıkıyordu.
  void reportRunStarted();

  /// Bir koşu sona erdi.
  void reportRun(RunReport report);
}
