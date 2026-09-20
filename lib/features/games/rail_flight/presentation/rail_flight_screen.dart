import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/metro_train.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_host.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/result_overlay.dart';
import '../application/rail_flight_controller.dart';
import '../domain/rail_flight_state.dart';

class RailFlightScreen extends StatefulWidget {
  const RailFlightScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<RailFlightScreen> createState() => _RailFlightScreenState();
}

class _RailFlightScreenState extends State<RailFlightScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  RailFlightController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenLineLevel = 1;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'RailFlightControls');

  late final AnimationController _bannerAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final scope = AppScope.of(context);
    _audio = scope.audio;
    final controller = RailFlightController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Yolculuk ortak: süren bir yolculuk varsa oyun onun içine girer —
      // puan, kalan süre ve geçilen duraklar oradan devam eder.
      session: JourneyScope.sessionOf(context),
    );
    // Sayaç tabanları koşudan okunur: yolculuk ekranlardan uzun yaşıyor,
    // sıfırdan başlanırsa yolculuğun ortasında açılan ekran geçmiş durak
    // bildirimlerini yeniden oynatır.
    _seenStationPulse = controller.stationBonusPulse;
    _seenLineLevel = controller.lineLevel;
    controller.addListener(_onControllerChanged);
    _controller = controller;
    controller.start();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    if (controller.stationBonusPulse != _seenStationPulse) {
      _seenStationPulse = controller.stationBonusPulse;
      _haptic(HapticFeedback.selectionClick);
      _sound(GameSound.station);
      _showBanner('Durak bonusu +${controller.lastStationBonus}');
    }

    if (controller.lineLevel != _seenLineLevel) {
      _seenLineLevel = controller.lineLevel;
      _haptic(HapticFeedback.mediumImpact);
      _showBanner('${controller.lineLabel} trenine geçtin');
    }

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      // "Tekrar oyna" aynı ekranı yeniden kullanır; bayrak sıfırlanmazsa
      // ikinci varışta kapı sesi çalmıyordu.
      _playedArrivalSound = false;
    }

    _syncMusic();
    // Not: burada bilerek setState() çağrılmıyor. Fizik ~60 kez/sn
    // notifyListeners() çağırıyor; tüm ekranı (Scaffold/PopScope/HUD/
    // ilerleme çubuğu dahil) her tikte yeniden kurmak zayıf bir telefonda
    // gerçek kare düşmesine yol açabiliyordu. Ekranın canlı kalması
    // gereken kısmı build()'deki ListenableBuilder hallediyor; bu metodun
    // işi yalnızca tek seferlik yan etkiler (ses, titreşim, banner).
  }

  void _syncMusic() {
    final status = _controller?.status;
    if (status == null || status == _musicSyncedFor) return;
    _musicSyncedFor = status;

    final audio = _audio;
    if (audio == null) return;
    if (status == GameStatus.playing) {
      audio.resumeMusic();
    } else if (status.isFinished || status == GameStatus.abandoned) {
      audio.stopMusic();
    } else {
      audio.pauseMusic();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
      _audio?.pauseMusic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio?.stopMusic();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _bannerTimer?.cancel();
    _bannerAnimation.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  void _sound(GameSound sound) => AppScope.of(context).audio.play(sound);

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    _bannerText = text;
    _bannerAnimation.forward();
    _bannerTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) _bannerAnimation.reverse();
    });
  }

  void _flap() {
    _controller?.flap();
    _haptic(HapticFeedback.lightImpact);
    _sound(GameSound.place);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _flap();
    }
  }

  void _exitToHome() {
    _controller?.abandon();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final journey = controller.journey;
    final line = AppScope.of(context).metro.lineById(journey.lineId);
    final accent = line == null
        ? AppColors.success
        : LineTheme.from(line.color).accent;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller?.abandon();
      },
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          // Yalnızca bu içerik controller'ı dinler ve her fizik tikinde
          // yeniden kurulur; PopScope/KeyboardListener/Scaffold sarmalayıcıları
          // hiç değişmediği için bir kez kurulup öyle kalır. Eskiden
          // controller her tikte State.setState() tetikliyordu ve bu
          // sarmalayıcılar da dahil tüm ağaç saniyede ~60 kez yeniden
          // kuruluyordu — zayıf bir telefonda gerçek kare düşmesine yol
          // açan asıl sebeplerden biri buydu.
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Stack(
              children: <Widget>[
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      children: <Widget>[
                        _FlightHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _FlightPlayArea(
                            controller: controller,
                            onFlap: _flap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        JourneyStatusBar(
                          run: controller,
                          lineStations: AppScope.of(
                            context,
                          ).metro.stationsOfLine(journey.lineId),
                          accent: accent,
                          isMoving: controller.status == GameStatus.playing,
                        ),
                      ],
                    ),
                  ),
                ),
                _Banner(
                  animation: _bannerAnimation,
                  text: _bannerText,
                  accent: accent,
                ),
                if (controller.status == GameStatus.paused)
                  PauseOverlay(
                    accent: accent,
                    score: controller.score,
                    remainingSeconds: controller.remainingSeconds,
                    onResume: controller.resume,
                    onRestart: controller.restart,
                    onSettings: () => AppRoutes.openSettings(context),
                    onExit: _exitToHome,
                  ),
                if (controller.status == GameStatus.arrived)
                  ArrivalSequence(
                    accent: accent,
                    // Sahne atlanınca tören sesi de sussun.
                    onSkipped: () => AppScope.of(context).audio.stopLongForm(),
                    lineId: journey.lineId,
                    stationName: journey.destination.name,
                    child: _buildResult(
                      controller,
                      accent,
                      showBackdrop: false,
                    ),
                  )
                else if (controller.status == GameStatus.gameOver)
                  _buildResult(controller, accent),
                // Sprint başladığında bir kez geçer; oyunu durdurmaz.
                SprintBanner(pulse: controller.sprintPulse),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(
    RailFlightController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      isArrival: controller.status == GameStatus.arrived,
      // Yolculuk ortaksa oyun bitişi bir ara duraktır, yolculuğun sonu değil.
      journeyContinues:
          controller.sharesJourney && controller.status != GameStatus.arrived,
      remainingSeconds: controller.remainingSeconds,
      destinationName: controller.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      isNewBest: controller.isNewBest,
      extraStats: <Widget>[
        // Varışta yolculuğun dağılımı: hangi oyunda ne kadar süre geçti,
        // ne kazandırdı. Oyunun kendi sayıları bunun altında.
        if (controller.status == GameStatus.arrived)
          ...journeyBreakdownRows(controller.journeySession),
        StatRow(label: 'Geçilen tünel', value: '${controller.gatesPassed}'),
        StatRow(label: 'Tren hattı', value: controller.lineLabel),
      ],
      gameOverTitle: 'Raya çarptın',
      gameOverSubtitle: 'Tren tünel aralığından çıkınca yolculuk yarıda kaldı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _FlightHud extends StatelessWidget {
  const _FlightHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final RailFlightController controller;
  final Color accent;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return JourneyHud(
      run: controller,
      accent: accent,
      onPause: onPause,
      gameScore: controller.scoreThisGame,
      chips: <Widget>[
        _HudChip(
          label: 'Tren',
          value: '${controller.lineLabel} · ${controller.gatesPassed}',
          accent: _railFlightLineColor(controller.lineLevel),
        ),
      ],
    );
  }
}

/// Oyuna özgü küçük gösterge; ortak HUD'un yanında durur.
class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: AppText.micro.copyWith(color: accent),
          ),
          Text(
            value,
            maxLines: 1,
            style: AppText.captionStrong.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightPlayArea extends StatelessWidget {
  const _FlightPlayArea({required this.controller, required this.onFlap});

  final RailFlightController controller;
  final VoidCallback onFlap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onFlap(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: CustomPaint(
          painter: _RailFlightPainter(controller),
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Dokun, tıkla veya Space ile treni uçur',
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailFlightPainter extends CustomPainter {
  const _RailFlightPainter(this.controller);

  final RailFlightController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = _railFlightLineColor(controller.lineLevel);
    _drawTunnelBackground(canvas, size, accent);
    _drawObstacles(canvas, size);
    _drawTrain(canvas, size, accent);
  }

  /// Düz gri zemin yerine metro tüneli hissi veren, yalnızca basit
  /// şekillerden kurulu bir sahne: kesit gradyanı, aktif hattın rengiyle
  /// boyanmış tavan ışıkları ve ray tabanı, kaydıran tünel kemerleri, kenarlarda
  /// hafif bir vinyet.
  ///
  /// Renk tamamen nötr (gri) bırakılmıyor — [accent] (o an geçilmekte olan
  /// hattın rengi) tavan ışıklarına ve rayın hemen üstüne çok düşük alfa ile
  /// karışıyor. Bu, uygulamanın kendi renk hiyerarşisiyle de tutarlı ("hat
  /// rengi: rozet, tren, RAY, ilerleme" — bkz. AppColors dokümantasyonu) ve
  /// tünelin jenerik/şablon değil, o an oynanan hatta ait hissetmesini
  /// sağlıyor.
  ///
  /// Gerçek bir istasyon fotoğrafı bilinçli olarak kullanılmıyor — bu
  /// oyunun tüm görselleri (bkz. README "Tasarım Dili") özgün ve basit
  /// şekillerden kurulu; lisanssız bir fotoğraf hem bu ilkeyi bozar hem de
  /// her karede yeniden boyanan bir bitmap, zayıf telefonlarda tam da
  /// düzelttiğimiz akıcılık sorununu geri getirebilir.
  void _drawTunnelBackground(Canvas canvas, Size size, Color accent) {
    final rect = Offset.zero & size;
    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.brandNavyDeep,
          Color.lerp(AppColors.boardBackground, AppColors.surfaceHigh, 0.45)!,
          AppColors.boardBackground,
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, gradient);

    _drawTunnelRibs(canvas, size);
    _drawCeilingLights(canvas, size, accent);
    _drawTrackGlow(canvas, size, accent);
    _drawTrackBed(canvas, size);
    _drawVignette(canvas, size);
  }

  /// Ekranın sol/sağ kenarlarını hafifçe koyultan basit bir vinyet — bir
  /// bakışta "düz doldurulmuş dikdörtgen" hissini kırıp sahneye derinlik
  /// katan ucuz bir dokunuş (blur yok, tek bir gradyanlı dikdörtgen).
  void _drawVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final vignette = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          AppColors.background.withValues(alpha: 0.55),
          Colors.transparent,
          Colors.transparent,
          AppColors.background.withValues(alpha: 0.55),
        ],
        stops: const <double>[0.0, 0.18, 0.82, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  /// Mesafeye göre kayan (paralaks) düzenli aralıklı tünel kemerleri.
  void _drawTunnelRibs(Canvas canvas, Size size) {
    const period = 0.24;
    final phase = _scrollPhase(period, speedFactor: 0.45);
    final rib = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var wx = -phase; wx < 1.08; wx += period) {
      final x = wx * size.width;
      final bow = size.width * 0.035;
      final path = Path()
        ..moveTo(x, size.height * 0.05)
        ..quadraticBezierTo(x - bow, size.height * 0.5, x, size.height * 0.95);
      canvas.drawPath(path, rib);
    }
  }

  /// Tavanda kayan lamba dizisi — sodyum buharlı tünel aydınlatmasını
  /// anımsatan sıcak bir ton (düz beyaz yerine), üstüne çok hafif [accent]
  /// karışımıyla o hattın ışığı gibi okunuyor.
  void _drawCeilingLights(Canvas canvas, Size size, Color accent) {
    const period = 0.32;
    final phase = _scrollPhase(period, speedFactor: 0.7);
    final warmWhite = Color.lerp(Colors.white, const Color(0xFFFFE1A8), 0.4)!;
    final tint = Color.lerp(warmWhite, accent, 0.18)!;
    final halo = Paint()..color = tint.withValues(alpha: 0.10);
    final core = Paint()..color = tint.withValues(alpha: 0.62);
    for (var wx = -phase; wx < 1.08; wx += period) {
      final center = Offset(wx * size.width, size.height * 0.07);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * 0.11,
          height: size.height * 0.028,
        ),
        halo,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * 0.055,
          height: size.height * 0.014,
        ),
        core,
      );
    }
  }

  /// Rayın hemen üstünde, [accent] renginde çok hafif bir zemin parıltısı —
  /// tünelin o an oynanan hatta ait olduğunu hissettiren, ucuz (blur'suz)
  /// bir gradyan dikdörtgeni.
  void _drawTrackGlow(Canvas canvas, Size size, Color accent) {
    final rect = Rect.fromLTWH(
      0,
      size.height * 0.72,
      size.width,
      size.height * 0.28,
    );
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.14),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glow);
  }

  /// Alt kenarda, obstacle'larla aynı hızda kayan ray + travers şeridi.
  void _drawTrackBed(Canvas canvas, Size size) {
    final y = size.height * 0.985;
    final rail = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), rail);

    const period = 0.09;
    final phase = _scrollPhase(period, speedFactor: 1.0);
    final tie = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.4)
      ..strokeWidth = 3;
    for (var wx = -phase; wx < 1.05; wx += period) {
      final x = wx * size.width;
      canvas.drawLine(
        Offset(x, y - size.height * 0.012),
        Offset(x, y + size.height * 0.012),
        tie,
      );
    }
  }

  /// Oyun süresine ve tünel hızına göre 0..period aralığında döngüsel bir
  /// kaydırma fazı. `speedFactor` < 1 daha yakın/yavaş (uzak) katmanlar,
  /// 1.0 travers gibi tam hızda ön-plan katmanları için.
  double _scrollPhase(double period, {required double speedFactor}) {
    final distance =
        controller.elapsedSeconds * controller.config.speed * speedFactor;
    return distance % period;
  }

  void _drawObstacles(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.55)
      ..strokeWidth = 3;
    for (final obstacle in controller.obstacles) {
      final x = obstacle.x * size.width;
      final width = railFlightObstacleWidth * size.width;
      final gapTop =
          (obstacle.gapCenter - obstacle.gapHeight / 2) * size.height;
      final gapBottom =
          (obstacle.gapCenter + obstacle.gapHeight / 2) * size.height;

      _drawObstaclePanel(canvas, Rect.fromLTWH(x, 0, width, gapTop));
      _drawObstaclePanel(
        canvas,
        Rect.fromLTWH(x, gapBottom, width, size.height - gapBottom),
      );

      final railX = x + width / 2;
      canvas.drawLine(Offset(railX, 0), Offset(railX, gapTop), railPaint);
      canvas.drawLine(
        Offset(railX, gapBottom),
        Offset(railX, size.height),
        railPaint,
      );
    }
  }

  /// Düz dolgu yerine tünel duvar panelini anımsatan hafif kabartmalı bir
  /// blok: soldan aydınlatılmış gibi bir gradyan taban (yuvarlak bir sütun
  /// hissi) ve üst üste dizilmiş, her biri ince bir parlama/gölge çiftiyle
  /// ayrılmış yatay paneller — tuğla örgüsü değil, gerçek metro tünellerinde
  /// olduğu gibi düz istiflenmiş beton segmentler (bkz. gerçek tünel
  /// halkaları). Blur yok, yalnızca gradyan + birkaç çizgi — ucuz.
  void _drawObstaclePanel(Canvas canvas, Rect rect) {
    if (rect.height <= 1) return;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          Color.lerp(AppColors.surfaceHigh, Colors.white, 0.12)!,
          AppColors.surfaceHigh,
          Color.lerp(AppColors.surfaceHigh, Colors.black, 0.3)!,
        ],
        stops: const <double>[0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, base);

    canvas.save();
    canvas.clipRRect(rrect);
    const panelHeight = 26.0;
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.12);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.24);
    for (var y = rect.top + panelHeight; y < rect.bottom; y += panelHeight) {
      canvas.drawLine(
        Offset(rect.left, y - 1),
        Offset(rect.right, y - 1),
        highlight,
      );
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), shadow);
    }
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.background.withValues(alpha: 0.6),
    );
  }

  /// Oynadığımız karakteri çizer — alt ilerleme çubuğunda ve varış
  /// sahnesinde kullanılan [MetroTrainPainter] ile TAM AYNI çizim kodu.
  ///
  /// Önceki sürüm bu ekrana özel, elle çizilmiş ayrı bir tren şekliydi;
  /// uygulamanın geri kalanındaki (2 vagonlu, yuvarlak burunlu, pencere
  /// sıralı) tren diliyle tutarsız durup "üretilmiş" hissediyordu. Artık
  /// oynanan karakter ile alttaki sayaçtaki tren birebir aynı çizim —
  /// tutarlılık, ayrı bir "oyun karakteri" tasarımından daha güçlü.
  void _drawTrain(Canvas canvas, Size size, Color accent) {
    final center = Offset(
      railFlightTrainX * size.width,
      controller.trainY * size.height,
    );
    // Görsel ölçek çarpanı çarpışma yarıçapından (railFlightTrainRadius)
    // ayrı: tren biraz büyük çizilse bile oyuncu boşluktan geçebiliyordu
    // (gerçek hitbox zaten daha küçük). 2.3 yerine 1.85 — biraz daha küçük
    // çizilince boşluklara sığdığı hissi de gerçeğe daha yakın oluyor.
    final trainHeight = railFlightTrainRadius * size.shortestSide * 1.85;
    final trainWidth = MetroTrain.widthFor(height: trainHeight);

    canvas.save();
    canvas.translate(center.dx - trainWidth / 2, center.dy - trainHeight / 2);
    MetroTrainPainter(
      color: accent,
    ).paint(canvas, Size(trainWidth, trainHeight));
    canvas.restore();

    _drawLineBadge(canvas, center, trainHeight, accent);
  }

  /// Trenin üstünde, gerçek bir peron tabelası gibi hat etiketini gösteren
  /// küçük bir rozet.
  void _drawLineBadge(
    Canvas canvas,
    Offset trainCenter,
    double trainHeight,
    Color accent,
  ) {
    final onAccent = LineTheme.readableOn(accent);
    final textPainter = TextPainter(
      text: TextSpan(
        text: controller.lineLabel,
        // Rozet tren boyuna göre ölçeklenir; aile ve stil ortak tipografiden.
        style: AppText.lead.copyWith(
          fontSize: trainHeight * 0.38,
          fontWeight: FontWeight.w900,
          color: onAccent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = trainHeight * 0.14;
    final badgeCenter = trainCenter.translate(
      0,
      -trainHeight / 2 - textPainter.height / 2 - trainHeight * 0.16,
    );
    final badgeRect = Rect.fromCenter(
      center: badgeCenter,
      width: textPainter.width + padding * 2,
      height: textPainter.height + padding,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(badgeRect.height / 2)),
      Paint()..color = accent,
    );
    textPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - textPainter.width / 2,
        badgeCenter.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _RailFlightPainter oldDelegate) {
    return true;
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.animation,
    required this.text,
    required this.accent,
  });

  final Animation<double> animation;
  final String? text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          if (t == 0 || text == null) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -18),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          ),
          child: Text(
            text ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong.copyWith(
              fontWeight: FontWeight.w800,
              color: LineTheme.readableOn(accent),
            ),
          ),
        ),
      ),
    );
  }
}

Color _railFlightLineColor(int lineLevel) {
  const colors = <Color>[
    Color(0xFFE30613),
    Color(0xFF009A44),
    Color(0xFF00AEEF),
    Color(0xFFE6007E),
    Color(0xFF6A2C91),
    Color(0xFFB58500),
    Color(0xFFF05A8A),
    Color(0xFF0067B1),
    Color(0xFFFFD300),
    Color(0xFFF7941D),
  ];
  return colors[(lineLevel - 1).clamp(0, colors.length - 1)];
}
