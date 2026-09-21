import 'package:flutter/material.dart';

import '../../journey/models/station.dart';
import '../../social/presentation/widgets/challenge_hud_badge.dart';
import '../../journey/models/station_progress.dart';
import '../journey_run.dart';
import 'journey_progress.dart';
import 'station_banner.dart';

/// Yolculuk şeridinin **akıllı** sarmalayıcısı — altı oyun için ortak.
///
/// [JourneyProgressBar] bilinçli olarak aptal bir widget: ne oyunu bilir ne
/// metro verisini, kendisine verilen adları ve oranları çizer. Onu
/// besleyecek hesap ise her ekranda ayrı ayrı yazılıydı; "bir sonraki
/// durak" fonksiyonu beş oyun ekranına kelimesi kelimesine kopyalanmıştı ve
/// yalnızca Blok Metro'da düzeltilmişti.
///
/// Bu sarmalayıcı hesabı tek yere alır: koşuyu ve hattın istasyonlarını
/// verirsin, gerisini o çözer.
class JourneyStatusBar extends StatelessWidget {
  const JourneyStatusBar({
    super.key,
    required this.run,
    required this.lineStations,
    required this.accent,
    this.arrivalPulse = 0,
    this.isMoving = true,
    this.showStationBanner = true,
    this.gameId,
  });

  final JourneyRun run;

  /// Hattın sıraya dizilmiş istasyonları (`MetroRepository.stationsOfLine`).
  final List<Station> lineStations;

  final Color accent;

  /// Durağa varış kutlaması, 0.0 – 1.0.
  final double arrivalPulse;

  /// Tren hareket ediyor mu? Duraklatmada durur.
  final bool isMoving;

  /// Durak geçişinde adı bildiren şerit gösterilsin mi?
  final bool showStationBanner;

  /// Oynanan oyunun kimliği.
  ///
  /// Verilirse meydan okuma modunda çubuğun üstünde küçük bir hedef
  /// rozeti çıkar. Verilmezse HUD bugünkü hâlinde kalır.
  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final journey = run.journey;
    final stations = stationProgressFor(
      journey: journey,
      lineStations: lineStations,
      progress: run.progress,
    );

    final progress = JourneyProgressBar(
      lineId: journey.lineId,
      stopCount: journey.stopCount,
      originName: journey.origin.name,
      destinationName: journey.destination.name,
      progress: run.progress,
      remainingSeconds: run.remainingSeconds,
      nextStopName: stations?.approaching?.name,
      stationProgress: stations,
      arrivalPulse: arrivalPulse,
      accent: accent,
      isMoving: isMoving,
    );

    // Meydan okuma rozeti çubuğun **üstünde**, sağa yaslı: oyun alanından
    // yer almıyor ve ilerleme çubuğunun okunmasını engellemiyor. Meydan
    // okuma modunda değilse hiç çizilmiyor.
    final bar = gameId == null
        ? progress
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ChallengeHudBadge(
                journey: journey,
                gameId: gameId!,
                score: run.score,
              ),
              progress,
            ],
          );

    if (!showStationBanner) return bar;

    // Şerit çubuğun **üstünde yüzer**, yer kaplamaz.
    //
    // Yer ayrılsaydı her oyunda kalıcı olarak 30 piksel giderdi ve şerit
    // gelip gidince oyun alanı büyüyüp küçülürdü. Kısa süre görünen bir
    // bildirim için ikisi de fazla bedel.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        bar,
        Positioned(
          top: -_bannerLift,
          left: 0,
          right: 0,
          child: StationBanner(
            run: run,
            lineStations: lineStations,
            accent: accent,
          ),
        ),
      ],
    );
  }

  /// Şeridin çubuğun üstünde durduğu yükseklik.
  static const double _bannerLift = 30;
}
