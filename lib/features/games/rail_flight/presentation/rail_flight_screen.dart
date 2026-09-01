import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_progress.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
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
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: RailFlightController.id,
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
    }

    _syncMusic();
    setState(() {});
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
          body: Stack(
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
                      JourneyProgressBar(
                        lineId: journey.lineId,
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
                  child: _buildResult(controller, accent, showBackdrop: false),
                )
              else if (controller.status == GameStatus.gameOver)
                _buildResult(controller, accent),
              // Sprint başladığında bir kez geçer; oyunu durdurmaz.
              SprintBanner(pulse: controller.sprintPulse),
            ],
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
      destinationName: controller.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      isNewBest: controller.isNewBest,
      extraStats: <Widget>[
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

  String? _nextStopName(RailFlightController controller) {
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
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: accent,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
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
          child: const SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Dokun, tıkla veya Space ile treni uçur',
                  style: TextStyle(
                    fontSize: 12,
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
    final bg = Paint()..color = AppColors.boardBackground;
    canvas.drawRect(Offset.zero & size, bg);

    _drawGrid(canvas, size);
    _drawObstacles(canvas, size);
    _drawTrain(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    for (var y = size.height * 0.16; y < size.height; y += size.height * 0.16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rail);
    }
  }

  void _drawObstacles(Canvas canvas, Size size) {
    final obstaclePaint = Paint()..color = AppColors.surfaceHigh;
    final railPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.7)
      ..strokeWidth = 3;
    for (final obstacle in controller.obstacles) {
      final x = obstacle.x * size.width;
      final width = railFlightObstacleWidth * size.width;
      final gapTop =
          (obstacle.gapCenter - obstacle.gapHeight / 2) * size.height;
      final gapBottom =
          (obstacle.gapCenter + obstacle.gapHeight / 2) * size.height;

      final top = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, width, gapTop),
        const Radius.circular(10),
      );
      final bottom = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, gapBottom, width, size.height - gapBottom),
        const Radius.circular(10),
      );
      canvas.drawRRect(top, obstaclePaint);
      canvas.drawRRect(bottom, obstaclePaint);

      final railX = x + width / 2;
      canvas.drawLine(Offset(railX, 0), Offset(railX, gapTop), railPaint);
      canvas.drawLine(
        Offset(railX, gapBottom),
        Offset(railX, size.height),
        railPaint,
      );
    }
  }

  void _drawTrain(Canvas canvas, Size size) {
    final color = _railFlightLineColor(controller.lineLevel);
    final onColor = LineTheme.readableOn(color);
    final center = Offset(
      railFlightTrainX * size.width,
      controller.trainY * size.height,
    );
    final radius = railFlightTrainRadius * size.shortestSide * 1.35;

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: radius * 2.8,
        height: radius * 1.65,
      ),
      Radius.circular(radius * 0.45),
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.72),
    );

    final windowPaint = Paint()..color = onColor.withValues(alpha: 0.88);
    final windowRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(radius * 0.08, -radius * 0.18),
        width: radius * 1.35,
        height: radius * 0.42,
      ),
      Radius.circular(radius * 0.15),
    );
    canvas.drawRRect(windowRect, windowPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: controller.lineLabel,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: radius * 0.52,
          fontWeight: FontWeight.w900,
          color: onColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center.translate(-textPainter.width / 2, radius * 0.07),
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
            style: TextStyle(
              fontSize: 14,
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
