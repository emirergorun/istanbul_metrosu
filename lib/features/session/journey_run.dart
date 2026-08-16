import 'package:flutter/foundation.dart';

import 'journey_status.dart';
import '../journey/models/journey.dart';

export 'journey_status.dart';

/// Bir oyunun yolculuk katmanına sunduğu görünüm.
///
/// [JourneyScaffold] yalnızca bu arayüzü bilir; hangi oyunun oynandığını
/// bilmez. Yeni bir oyun bunu uygularsa ilerleme çubuğu, duraklatma paneli,
/// varış sahnesi, **kapı sesi** ve müzik kendiliğinden gelir — hiçbir şeyi
/// yeniden yazmak gerekmez.
///
/// Oyuna özgü hiçbir şey (tahta, parça, combo…) burada yer almaz.
abstract class JourneyRun implements Listenable {
  /// Oynanan rota. Süre ve durak sayısı buradan gelir.
  Journey get journey;

  GameStatus get status;

  /// Oyuncunun bu oturumdaki puanı. Nasıl kazanıldığı oyunun bileceği iş.
  int get score;

  /// Bu rotada geçilmesi gereken rekor. 0 ise rotada ilk yolculuk.
  int get recordToBeat;

  /// Rekor bu oturumda geçildi mi?
  bool get recordBeaten;

  /// Rotada daha önce oynanmadıysa kıyaslanacak rekor yok.
  bool get isFirstRun;

  /// Oyun bittikten sonra skor yeni rekor olarak kaydedildi mi?
  bool get isNewBest;

  /// Yolculuk ilerlemesi, 0.0 – 1.0.
  double get progress;

  /// Rekora göre doluluk, 0.0 – 1.0.
  double get recordProgress;

  int get remainingSeconds;

  /// Kazanılan son durak bonusu ve onu tetikleyen sayaç.
  ///
  /// Sayaç her bonusta artar; kabuk değişimi görüp kısa bir bildirim gösterir.
  int get lastStationBonus;
  int get stationBonusPulse;

  void start();
  void pause();
  void resume();
  void restart();
  void abandon();
}
