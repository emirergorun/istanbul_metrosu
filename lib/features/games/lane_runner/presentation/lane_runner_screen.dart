import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/metro_train.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_progress.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../application/lane_runner_controller.dart';
import '../domain/lane_runner_state.dart';

class LaneRunnerScreen extends StatefulWidget {
  const LaneRunnerScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<LaneRunnerScreen> createState() => _LaneRunnerScreenState();
}

class _LaneRunnerScreenState extends State<LaneRunnerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  LaneRunnerController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenLineLevel = 1;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'LaneRunnerControls');

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
    final controller = LaneRunnerController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: LaneRunnerController.id,
        originId: widget.journey.origin.id,
        destinationId: widget.journey.destination.id,
      ),
    );
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
    // Not: bilerek setState() çağrılmıyor — fizik ~60 kez/sn
    // notifyListeners() çağırıyor; tüm ekranı her tikte yeniden kurmak
    // zayıf bir telefonda gerçek kare düşmesine yol açabiliyordu (bkz.
    // RailFlightScreen'de uygulanan aynı düzeltme). Canlı kalması gereken
    // kısmı build()'deki ListenableBuilder hallediyor.
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

  void _moveLeft() {
    _controller?.moveLeft();
    _haptic(HapticFeedback.lightImpact);
    _sound(GameSound.place);
  }

  void _moveRight() {
    _controller?.moveRight();
    _haptic(HapticFeedback.lightImpact);
    _sound(GameSound.place);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _moveLeft();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _moveRight();
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
          // hiç değişmediği için bir kez kurulup öyle kalır.
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
                        _RunnerHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _RunnerPlayArea(
                            controller: controller,
                            onLeft: _moveLeft,
                            onRight: _moveRight,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _LaneControls(onLeft: _moveLeft, onRight: _moveRight),
                        const SizedBox(height: AppSpacing.md),
                        JourneyProgressBar(
                          lineId: journey.lineId,
                          stopCount: journey.stopCount,
                          originName: journey.origin.name,
                          destinationName: journey.destination.name,
                          progress: controller.progress,
                          remainingSeconds: controller.remainingSeconds,
                          nextStopName: _nextStopName(controller),
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
    LaneRunnerController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      isArrival: controller.status == GameStatus.arrived,
      destinationName: controller.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      isNewBest: controller.isNewBest,
      extraStats: <Widget>[
        StatRow(label: 'Geçilen engel', value: '${controller.passes}'),
        StatRow(label: 'Tren hattı', value: controller.lineLabel),
      ],
      gameOverTitle: 'Kapalı raya girdin',
      gameOverSubtitle: 'Ray değiştirme zamanlaması kaçınca tren durdu.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }

  String? _nextStopName(LaneRunnerController controller) {
    final journey = controller.journey;
    final stops = journey.stopCount;
    if (stops <= 0) return null;
    final direction = journey.destination.order > journey.origin.order ? 1 : -1;
    final passed = (controller.progress * stops).floor();
    final nextIndex = math.min(passed + 1, stops);
    final targetOrder = journey.origin.order + direction * nextIndex;

    for (final station in AppScope.of(context).metro.stations()) {
      if (station.lineId == journey.lineId && station.order == targetOrder) {
        return station.name;
      }
    }
    return null;
  }
}

class _RunnerHud extends StatelessWidget {
  const _RunnerHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final LaneRunnerController controller;
  final Color accent;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return JourneyHud(
      run: controller,
      accent: accent,
      onPause: onPause,
      chips: <Widget>[
        _HudChip(
          label: 'Tren',
          value: '${controller.lineLabel} · ${controller.passes}',
          accent: _runnerLineColor(controller.lineLevel),
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

class _RunnerPlayArea extends StatelessWidget {
  const _RunnerPlayArea({
    required this.controller,
    required this.onLeft,
    required this.onRight,
  });

  final LaneRunnerController controller;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -80) {
          onLeft();
        } else if (velocity > 80) {
          onRight();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: CustomPaint(
          painter: _LaneRunnerPainter(controller),
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Sağa/sola kaydır ya da ok tuşlarıyla ray değiştir',
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

class _LaneControls extends StatelessWidget {
  const _LaneControls({required this.onLeft, required this.onRight});

  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: onLeft,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Sol ray'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: onRight,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Sağ ray'),
          ),
        ),
      ],
    );
  }
}

/// Ray Değiştir'in sahnesi: önden bakışla 3 metro rayı uzaklara doğru
/// daralıyor (basit bir güç-eğrisiyle taklit edilen pseudo-3B perspektif),
/// oyuncu ve gelen engeller artık soyut çizgi/kapsül değil gerçek
/// [MetroTrainPainter] trenleri — oyuncunun treni yukarı (gelen trafiğe
/// doğru), engel trenleri aşağı (oyuncuya doğru) bakıyor. Düz nötr zemin
/// yerine kesit gradyanlı bir tünel var.
class _LaneRunnerPainter extends CustomPainter {
  const _LaneRunnerPainter(this.controller);

  final LaneRunnerController controller;

  /// Uzaklık (0=ufuk, 1=oyuncu) sıkıştırma eğrisi. >1 değer, uzaktaki
  /// nesnelerin ufka doğru daha hızlı küçülüp yaklaşmasını sağlar — gerçek
  /// bir kameradan bakıyormuş hissi verir.
  static const double _perspectiveGamma = 1.65;
  static const double _vanishXFraction = 0.5;
  static const double _farSpreadFactor = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTunnelBackground(canvas, size);
    _drawTracks(canvas, size);
    _drawObstacles(canvas, size);
    _drawTrain(canvas, size);
  }

  double _perspective(double s) =>
      math.pow(s.clamp(0.0, 1.2), _perspectiveGamma).toDouble();

  /// `lane` kesirli olabilir — oyuncu iki ray arasında kayarken düzgün
  /// aradeğerleme için.
  double _laneXAtT(Size size, double lane, double t) {
    final nearX = size.width * (0.22 + lane * 0.28);
    final vanishX = size.width * _vanishXFraction;
    final farX = vanishX + (nearX - vanishX) * _farSpreadFactor;
    return farX + (nearX - farX) * t;
  }

  double _scaleAtT(double t) => 0.42 + 0.58 * t;

  double _scrollPhase(double step, double speedFactor) {
    final distance = controller.elapsedSeconds * speedFactor;
    return distance % step;
  }

  void _drawTunnelBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.brandNavyDeep,
          Color.lerp(AppColors.boardBackground, AppColors.surfaceHigh, 0.4)!,
          AppColors.boardBackground,
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, gradient);

    final vignette = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          AppColors.background.withValues(alpha: 0.5),
          Colors.transparent,
          Colors.transparent,
          AppColors.background.withValues(alpha: 0.5),
        ],
        stops: const <double>[0.0, 0.2, 0.8, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  /// Üç rayı da (iki ray çubuğu + traversler) ufka doğru daralan bir
  /// perspektifle çizer — düz dikey çizgiler yerine gerçek bir ray hattı.
  void _drawTracks(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (var lane = 0; lane < laneRunnerLaneCount; lane++) {
      canvas.drawPath(_railPath(size, lane.toDouble(), -1), railPaint);
      canvas.drawPath(_railPath(size, lane.toDouble(), 1), railPaint);
    }
    _drawTies(canvas, size);
  }

  Path _railPath(Size size, double lane, double side) {
    const steps = 12;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final s = i / steps;
      final t = _perspective(s);
      final centerX = _laneXAtT(size, lane, t);
      final gauge = size.width * 0.052 * _scaleAtT(t);
      final point = Offset(centerX + side * gauge, size.height * s);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }

  /// Kayan traversler — sahneye ileri hareket hissi katan, uzakta sık,
  /// yakında seyrek görünen çapraz çizgiler.
  void _drawTies(Canvas canvas, Size size) {
    const step = 0.09;
    final phase = _scrollPhase(step, 0.55);
    final tiePaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.5);

    for (var lane = 0; lane < laneRunnerLaneCount; lane++) {
      for (var s = -phase; s < 1.12; s += step) {
        if (s < 0) continue;
        final t = _perspective(s);
        final centerX = _laneXAtT(size, lane.toDouble(), t);
        final scale = _scaleAtT(t);
        final gauge = size.width * 0.052 * scale;
        final y = size.height * s;
        tiePaint.strokeWidth = 2.5 * scale;
        canvas.drawLine(
          Offset(centerX - gauge * 1.35, y),
          Offset(centerX + gauge * 1.35, y),
          tiePaint,
        );
      }
    }
  }

  void _drawObstacles(Canvas canvas, Size size) {
    for (final obstacle in controller.obstacles) {
      final s = obstacle.y;
      final t = _perspective(s);
      final center = Offset(
        _laneXAtT(size, obstacle.lane.toDouble(), t),
        size.height * s,
      );
      _drawTrainSprite(
        canvas,
        size: size,
        center: center,
        scale: _scaleAtT(t),
        color: AppColors.danger,
        // Burun aşağı: oyuncuya doğru gelen bir tren.
        rotation: math.pi / 2,
      );
    }
  }

  void _drawTrain(Canvas canvas, Size size) {
    const s = laneRunnerTrainY;
    final t = _perspective(s);
    final center = Offset(
      _laneXAtT(size, controller.trainLaneVisual, t),
      size.height * s,
    );
    _drawTrainSprite(
      canvas,
      size: size,
      center: center,
      scale: _scaleAtT(t),
      color: _runnerLineColor(controller.lineLevel),
      // Burun yukarı: gelen trafiğe doğru ilerleyen oyuncu.
      rotation: -math.pi / 2,
      label: controller.lineLabel,
    );
  }

  void _drawTrainSprite(
    Canvas canvas, {
    required Size size,
    required Offset center,
    required double scale,
    required Color color,
    required double rotation,
    String? label,
  }) {
    // 2 vagon: tek vagon (yalnızca yuvarlak burun + düz gövde) küçük
    // ölçekte kapsül/kalkan gibi okunuyordu; kuplajla ayrılmış iki parça
    // "tren" olarak çok daha net tanınıyor.
    final trainHeight = size.shortestSide * 0.075 * scale;
    final trainWidth = MetroTrain.widthFor(height: trainHeight, wagons: 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-trainWidth / 2, -trainHeight / 2);
    MetroTrainPainter(
      color: color,
      wagons: 2,
    ).paint(canvas, Size(trainWidth, trainHeight));
    canvas.restore();

    if (label == null) return;
    final onColor = LineTheme.readableOn(color);
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        // Rozet tren boyuna göre ölçeklenir; aile ve stil ortak tipografiden.
        style: AppText.lead.copyWith(
          fontSize: trainHeight * 0.4,
          fontWeight: FontWeight.w900,
          color: onColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final padding = trainHeight * 0.14;
    final badgeCenter = center.translate(
      0,
      -trainHeight / 2 - textPainter.height / 2 - trainHeight * 0.18,
    );
    final badgeRect = Rect.fromCenter(
      center: badgeCenter,
      width: textPainter.width + padding * 2,
      height: textPainter.height + padding,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(badgeRect.height / 2)),
      Paint()..color = color,
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
  bool shouldRepaint(covariant _LaneRunnerPainter oldDelegate) => true;
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
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.3),
                end: Offset.zero,
              ).animate(animation),
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.xl),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  text ?? '',
                  // Ray Uçuşu şeridiyle aynı: açık hat renklerinde beyaz
                  // yazı okunmuyordu, rengi hat renginden türetilir.
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w800,
                    color: LineTheme.readableOn(accent),
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

Color _runnerLineColor(int level) {
  const colors = <Color>[
    Color(0xFFE53935),
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF8E24AA),
    Color(0xFFEF6C00),
    Color(0xFF00897B),
    Color(0xFF5D4037),
  ];
  return colors[(level - 1).clamp(0, colors.length - 1)];
}
