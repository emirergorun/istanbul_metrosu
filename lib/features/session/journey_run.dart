import 'package:flutter/foundation.dart';

import 'journey_status.dart';
import '../discovery/application/journey_discovery.dart';
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

  /// Bu yolculuğun keşif defteri. Keşif kapalıysa `null`.
  ///
  /// Arayüz katmanı bunu **okur**, yazmaz: durak şeridi "bu durak yeni mi"
  /// diye sorar, sonuç paneli koşunun yeni keşiflerini listeler. Keşfi
  /// güncelleyen tek yer yolculuk motorudur.
  JourneyDiscovery? get discovery;

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

  /// Yolculuğun son diliminde miyiz? Puanlar iki katı.
  ///
  /// Yalnızca yeterince uzun yolculuklarda açılır; iki duraklık bir
  /// yolculukta "son durak sprinti" diye bir şey yok.
  bool get isSprint;

  /// Sprint **bu anda** başladıysa artan sayaç. UI bir kez animasyon gösterir.
  int get sprintPulse;

  /// Kazanılan son durak bonusu ve onu tetikleyen sayaç.
  ///
  /// Sayaç her bonusta artar; kabuk değişimi görüp kısa bir bildirim gösterir.
  int get lastStationBonus;
  int get stationBonusPulse;

  /// Her durak geçişinde artan sayaç — bonus kazanılmasa da.
  ///
  /// [stationBonusPulse]'dan farkı: bonus yalnızca o duraktan beri kayda
  /// değer bir şey yapıldıysa gelir, oysa durağın kendisi her hâlükârda
  /// geçilir. Yolculuğun ilerlediği oyuncuya bu sayaçla gösterilir.
  int get stationPulse;

  void start();
  void pause();
  void resume();
  void restart();
  void abandon();
}
