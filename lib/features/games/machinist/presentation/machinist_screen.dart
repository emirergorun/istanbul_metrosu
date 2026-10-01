import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../journey/models/journey.dart';
import '../../../journey/models/station.dart';
import '../../../session/journey_host.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/hud_widgets.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/machinist_controller.dart';
import '../domain/machinist_rules.dart';
import 'machinist_controls.dart';
import 'machinist_scene_painter.dart';
import 'machinist_textures.dart';

/// Makinist: trenin arkasından bakan kamerayla metro sürme.
///
/// Sağ altta iki pedal: İLERİ ve köşede FREN. Durak işaretinde durursan
/// kapılar açılır, yolcular biner, puan yazılır.
class MachinistScreen extends StatefulWidget {
  const MachinistScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<MachinistScreen> createState() => _MachinistScreenState();
}

class _MachinistScreenState extends State<MachinistScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  MachinistController? _controller;
  MachinistScenePainter? _painter;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenResultPulse = 0;
  int _seenHintPulse = 0;
  int? _seenCountdown;
  Timer? _bannerTimer;
  String? _bannerText;
  Color? _bannerColor;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MachinistControls');

  /// Testler sürüşü doğrudan yönetebilsin diye.
  @visibleForTesting
  MachinistController? get debugController => _controller;

  late final AnimationController _bannerAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Her vsync karesinde bir artar; sahne bununla boyanır.
  ///
  /// Fizik motorun `Timer`'ında ilerliyor ve o ekran yenilemesine hizalı
  /// değil. Sahne controller'ı dinleseydi kare başına ya hiç ya da iki
  /// fizik adımı görür, tren kasarak giderdi. Ticker her kareyi yakalar,
  /// çizici de konumu son adımdan bu yana geçen süreyle ileri kestirir.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker((_) => _frame.value++);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Dokular açılışta, kare kaçırmadan dilim dilim üretilir; hazır olana
    // dek düz renk. Hazır olunca sahne bir kez görünmez çizilip GPU
    // ısıtılır: ilk saniyelerdeki takılma oyundan önceye kayar.
    MachinistTextures.load().then((_) {
      if (!mounted) return;
      final painter = _painter;
      if (painter == null) return;
      final warm = painter.warmUp(MediaQuery.sizeOf(context));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final image in warm) {
          image.dispose();
        }
      });
    });
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final scope = AppScope.of(context);
    _audio = scope.audio;
    final journey = widget.journey;
    final controller = MachinistController(
      journey: journey,
      stationNames: _stationNames(scope.metro.stationsOfLine(journey.lineId)),
      store: scope.store,
      discovery: scope.discoveryFor(journey, MachinistController.id),
      random: scope.challengeRandomFor(journey, MachinistController.id),
      recordToBeat: scope.store.bestJourneyScore(
        journey.origin.id,
        journey.destination.id,
      ),
      session: JourneyScope.sessionFor(context, journey),
    );
    controller.reporter = scope.runReporter;
    _seenStationPulse = controller.stationBonusPulse;
    controller.addListener(_onControllerChanged);
    _controller = controller;

    final line = scope.metro.lineById(journey.lineId);
    _painter =
        MachinistScenePainter(
            controller: controller,
            lineColor: line?.color ?? AppColors.success,
            lineCode: line?.id ?? journey.lineId.toUpperCase(),
            destination: journey.destination.name,
            frame: _frame,
          )
          ..camera = scope.store.machinistCabView
              ? MachinistCamera.cab
              : MachinistCamera.chase;
    controller.start();
  }

  /// Binişten varışa doğru, sonra hat sonuna kadar istasyon adları.
  List<String> _stationNames(List<Station> line) {
    final journey = widget.journey;
    final from = line.indexWhere((s) => s.id == journey.origin.id);
    final to = line.indexWhere((s) => s.id == journey.destination.id);
    if (from < 0 || to < 0) {
      return <String>[journey.origin.name, journey.destination.name];
    }
    final ordered = to >= from ? line : line.reversed.toList();
    final start = to >= from ? from : line.length - 1 - from;
    return ordered.skip(start).map((s) => s.name).toList();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    if (controller.stationBonusPulse != _seenStationPulse) {
      _seenStationPulse = controller.stationBonusPulse;
      _sound(GameSound.station);
    }

    if (controller.resultPulse != _seenResultPulse) {
      _seenResultPulse = controller.resultPulse;
      final result = controller.lastResult;
      if (result != null) _announce(result, controller);
    }

    if (controller.hintPulse != _seenHintPulse) {
      _seenHintPulse = controller.hintPulse;
      _showBanner('Biraz daha ilerle — işarete gelmedin', AppColors.gameBlocks);
    }

    final countdown = controller.countdown;
    if (countdown != _seenCountdown) {
      _seenCountdown = countdown;
      if (countdown != null && controller.status == GameStatus.playing) {
        _haptic(HapticFeedback.selectionClick);
        _sound(GameSound.place);
      }
    }

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      _playedArrivalSound = false;
    }
    _syncMusic();
  }

  void _announce(StopResult result, MachinistController controller) {
    if (result.missed) {
      _haptic(HapticFeedback.heavyImpact);
      _sound(GameSound.invalid);
      final left = MachinistRules.maxMisses - controller.misses;
      _showBanner(
        left > 0
            ? '${result.station} kaçtı · $left hakkın kaldı'
            : '${result.station} de kaçtı',
        MachinistPalette.stop,
      );
      return;
    }
    final grade = result.grade!;
    _haptic(HapticFeedback.mediumImpact);
    _sound(grade == StopGrade.perfect ? GameSound.combo : GameSound.clear);
    final streak = result.streak > 1 ? ' · ${result.streak} seri' : '';
    _showBanner(
      '${grade.label} +${result.points} · ${result.passengers} yolcu$streak',
      grade.keepsStreak ? MachinistPalette.go : AppColors.gameBlocks,
    );
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
    _ticker.dispose();
    _frame.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  void _sound(GameSound sound) => AppScope.of(context).audio.play(sound);

  void _showBanner(String text, Color color) {
    _bannerTimer?.cancel();
    setState(() {
      _bannerText = text;
      _bannerColor = color;
    });
    _bannerAnimation.forward(from: 0);
    _bannerTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) _bannerAnimation.reverse();
    });
  }

  /// ↑/W kolu bir kademe yukarı (çekiş), ↓/S bir kademe aşağı (fren)
  /// oynatır; basılı tutunca kademe kademe ilerler. Boşluk tam fren, C
  /// kamerayı değiştirir.
  void _handleKeyEvent(KeyEvent event) {
    final controller = _controller;
    if (controller == null || event is KeyUpEvent) return;
    final key = event.logicalKey;
    final before = controller.leverNotch;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      controller.stepLever(1);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      controller.stepLever(-1);
    } else if (key == LogicalKeyboardKey.space) {
      controller.setLever(-1);
    } else if (key == LogicalKeyboardKey.keyC && event is KeyDownEvent) {
      _toggleCamera();
    }
    if (controller.leverNotch != before) {
      _haptic(HapticFeedback.selectionClick);
    }
  }

  bool get _cabView => _painter?.camera == MachinistCamera.cab;

  void _toggleCamera() {
    final painter = _painter;
    if (painter == null) return;
    final cab = !_cabView;
    setState(() {
      painter.camera = cab ? MachinistCamera.cab : MachinistCamera.chase;
    });
    AppScope.of(context).store.saveMachinistCabView(cab);
    _haptic(HapticFeedback.lightImpact);
  }

  void _exitToHome() {
    _controller?.abandon();
    AppRoutes.exitToGallery(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final painter = _painter;
    if (controller == null || painter == null) {
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
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              // Sahne controller'ı `repaint` ile dinler: her karede yalnız
              // boyanır, widget ağacı yeniden kurulmaz.
              Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: painter)),
              ),
              // Üst ve alt karartma: HUD okunur kalsın.
              const Positioned.fill(child: IgnorePointer(child: _Scrims())),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _buildHud(context, controller, accent),
              ),
              _Banner(
                animation: _bannerAnimation,
                text: _bannerText,
                color: _bannerColor ?? accent,
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) =>
                    _buildOverlays(context, controller, accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud(
    BuildContext context,
    MachinistController controller,
    Color accent,
  ) {
    final journey = controller.journey;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          children: <Widget>[
            JourneyHud(
              run: controller,
              accent: accent,
              onPause: controller.pause,
              gameScore: controller.scoreThisGame,
              chips: <Widget>[
                HudStat.value(
                  label: 'YOLCU',
                  value: '${controller.passengersTotal}',
                  semanticLabel: '${controller.passengersTotal} yolcu',
                ),
                HudLivesStat(
                  left: MachinistRules.maxMisses - controller.misses,
                  total: MachinistRules.maxMisses,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _StationCard(controller: controller, accent: accent),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: _Countdown(controller: controller)),
                  Positioned(
                    left: 0,
                    top: AppSpacing.sm,
                    child: _CameraButton(
                      cab: _cabView,
                      onPressed: _toggleCamera,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                MachinistSpeedometer(
                  kmh: controller.speedKmh,
                  throttle: controller.throttleLevel,
                  brake: controller.brakeLevel,
                ),
                const Spacer(),
                MachinistMasterLever(
                  value: controller.lever,
                  onChanged: controller.setLever,
                  onNotch: (_) => _haptic(HapticFeedback.selectionClick),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            JourneyStatusBar(
              gameId: MachinistController.id,
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
    );
  }

  Widget _buildOverlays(
    BuildContext context,
    MachinistController controller,
    Color accent,
  ) {
    final journey = controller.journey;
    return Stack(
      children: <Widget>[
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
            onSkipped: () => AppScope.of(context).audio.stopLongForm(),
            lineId: journey.lineId,
            stationName: journey.destination.name,
            child: _buildResult(controller, accent, showBackdrop: false),
          )
        else if (controller.status == GameStatus.gameOver)
          _buildResult(controller, accent),
        SprintBanner(pulse: controller.sprintPulse),
      ],
    );
  }

  Widget _buildResult(
    MachinistController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      journey: controller.journey,
      gameId: MachinistController.id,
      isArrival: controller.status == GameStatus.arrived,
      discovery: controller.discovery,
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
        if (controller.status == GameStatus.arrived)
          ...journeyBreakdownRows(controller.journeySession),
        StatRow(label: 'Yanaşılan durak', value: '${controller.served}'),
        StatRow(label: 'Taşınan yolcu', value: '${controller.passengersTotal}'),
        StatRow(label: 'Kaçırılan durak', value: '${controller.misses}'),
      ],
      gameOverTitle: 'Yolcular peronda kaldı',
      gameOverSubtitle:
          'Üç durağı kaçırdın. Frene daha erken bas: "3" levhasında yavaşlamaya başla.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[0, 0.24, 0.62, 1],
          colors: <Color>[
            Color(0xE6000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xDD000000),
          ],
        ),
      ),
    );
  }
}

/// Sonraki istasyon, kalan mesafe ve sarı yaklaşma ışığı.
class _StationCard extends StatelessWidget {
  const _StationCard({required this.controller, required this.accent});

  final MachinistController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dwelling = controller.dwellStation;
    final String title;
    final String name;
    final String detail;
    Color light = MachinistPalette.go;
    if (dwelling != null) {
      title = 'KAPILAR AÇIK';
      name = dwelling.name;
      final boarded = (dwelling.passengers * controller.boardingProgress)
          .round();
      detail = '$boarded/${dwelling.passengers} yolcu';
      light = MachinistPalette.stop;
    } else {
      final d = controller.distanceToStop;
      final approaching = controller.approaching;
      final blink = (controller.clockSeconds * 2.2).floor().isEven;
      title = approaching ? 'İSTASYON YAKLAŞIYOR' : 'SONRAKİ İSTASYON';
      name = controller.target.name;
      detail = d >= 0 ? '${d.round()} m' : 'geçtin';
      if (approaching) {
        light = blink
            ? MachinistPalette.caution
            : MachinistPalette.caution.withValues(alpha: 0.25);
      }
    }
    final showMeter =
        dwelling == null &&
        controller.distanceToStop < MachinistStopMeter.range;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      // Düz, koyu panel; hat rengi yalnız soldaki şeritte. Yarı saydam
      // lacivert ve renkli çerçeve açık tünel duvarında bulanıyordu.
      decoration: BoxDecoration(
        color: MachinistPalette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Sinyal lambası: düz renk, koyu yuva. Parlama yok.
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: light,
                  border: Border.all(color: Colors.black54, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppText.micro),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.lead.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
              Text(detail, style: AppText.stat.copyWith(color: Colors.white)),
            ],
          ),
          if (showMeter) ...<Widget>[
            const SizedBox(height: 6),
            MachinistStopMeter(distance: controller.distanceToStop),
          ],
        ],
      ),
    );
  }
}

/// Ortadaki büyük 3-2-1 / DUR sayacı ve hız uyarıları.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.controller});

  final MachinistController controller;

  @override
  Widget build(BuildContext context) {
    final n = controller.countdown;
    final String? warning;
    if (controller.status != GameStatus.playing) {
      warning = null;
    } else if (controller.isDwelling) {
      warning = null;
    } else if (controller.tooFast) {
      warning = 'Çok hızlı, fren yap';
    } else if (controller.shouldBrake && !controller.braking) {
      warning = 'Kolu aşağı çek, fren yap';
    } else if (controller.speed == 0 && controller.lever <= 0) {
      warning = controller.served == 0 && controller.misses == 0
          ? 'Kalkmak için kolu yukarı it'
          : null;
    } else {
      warning = null;
    }
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 1.6, end: 1).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: n == null
                  ? const SizedBox(key: ValueKey<String>('none'), height: 1)
                  : _CountdownBadge(key: ValueKey<int>(n), value: n),
            ),
            if (warning != null) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: controller.tooFast
                      ? MachinistPalette.stop
                      : MachinistPalette.panel,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  warning,
                  style: AppText.captionStrong.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (value) {
      // Sarıdan kırmızıya tek bir rampa: 3 yavaşla, DUR dur.
      3 => ('3', MachinistPalette.caution),
      2 => (
        '2',
        Color.lerp(MachinistPalette.caution, MachinistPalette.stop, 0.35)!,
      ),
      1 => (
        '1',
        Color.lerp(MachinistPalette.caution, MachinistPalette.stop, 0.7)!,
      ),
      _ => ('DUR', MachinistPalette.stop),
    };
    return Container(
      width: value == 0 ? 116 : 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MachinistPalette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 3),
      ),
      child: Text(
        text,
        style: AppText.display.copyWith(color: color, fontSize: 40, height: 1),
      ),
    );
  }
}

/// Kamera düğmesi: takip ↔ kabin. Duraklat düğmesiyle aynı aile — düz
/// zemin, 44 piksel, 12 köşe; yarı saydam hap yok.
class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.cab, required this.onPressed});

  final bool cab;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: cab ? 'Takip kamerasına geç' : 'Kabin kamerasına geç',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  cab ? 'Kabin' : 'Takip',
                  style: AppText.captionStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.animation,
    required this.text,
    required this.color,
  });

  final Animation<double> animation;
  final String? text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, 0.1),
          child: FadeTransition(
            opacity: animation,
            child: HudToast(text: text ?? '', accent: color),
          ),
        ),
      ),
    );
  }
}
