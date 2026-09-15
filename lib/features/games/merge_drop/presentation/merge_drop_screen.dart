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
import '../application/merge_drop_controller.dart';
import '../domain/merge_drop_state.dart';

class MergeDropScreen extends StatefulWidget {
  const MergeDropScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<MergeDropScreen> createState() => _MergeDropScreenState();
}

class _MergeDropScreenState extends State<MergeDropScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  MergeDropController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenMerges = 0;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MergeDropControls');

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
    final controller = MergeDropController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: MergeDropController.id,
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

    if (controller.merges != _seenMerges) {
      _seenMerges = controller.merges;
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.clear);
    }

    if (controller.stationBonusPulse != _seenStationPulse) {
      _seenStationPulse = controller.stationBonusPulse;
      _haptic(HapticFeedback.selectionClick);
      _sound(GameSound.station);
      _showBanner('Durak bonusu +${controller.lastStationBonus}');
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

  void _drop() {
    if (_controller?.drop() == true) {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.place);
    } else {
      _haptic(HapticFeedback.selectionClick);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    final controller = _controller;
    if (controller == null || event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      controller.moveAim(controller.aimX - 0.045);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      controller.moveAim(controller.aimX + 0.045);
    } else if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _drop();
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
                      _DropHud(
                        controller: controller,
                        accent: accent,
                        onPause: controller.pause,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        // Havuz daha dar: toplara daha az yanal alan kalır,
                        // yığın daha çabuk sıkışır — oyun biraz zorlaşır.
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.82,
                            heightFactor: 1,
                            child: _DropPlayArea(
                              controller: controller,
                              onDrop: _drop,
                            ),
                          ),
                        ),
                      ),
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
    MergeDropController controller,
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
        StatRow(label: 'Birleşme', value: '${controller.merges}'),
        StatRow(label: 'En büyük hat', value: controller.maxLabel),
      ],
      gameOverTitle: 'Alan doldu',
      gameOverSubtitle:
          'Hat rozetleri üst sınıra taştı, yolculuk yarıda kaldı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }

  String? _nextStopName(MergeDropController controller) {
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

class _DropHud extends StatelessWidget {
  const _DropHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final MergeDropController controller;
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
          label: 'Sıradaki',
          value: controller.currentLabel,
          accent: _mergeDropLineColor(controller.currentLevel),
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

class _DropPlayArea extends StatelessWidget {
  const _DropPlayArea({required this.controller, required this.onDrop});

  final MergeDropController controller;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fizik dünyası izotropik (1 birim = havuz genişliği); havuzun kaç
        // birim yüksekliğinde olduğunu yalnızca düzen bilir.
        final aspect = constraints.maxHeight / constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.setPoolAspect(aspect);
        });

        void aimFromLocal(Offset local) {
          final x = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          controller.moveAim(x);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => aimFromLocal(details.localPosition),
          onTapDown: (details) {
            aimFromLocal(details.localPosition);
            onDrop();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: CustomPaint(
              painter: _MergeDropPainter(controller),
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Sürükle, dokun ve aynı hatları birleştir',
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
      },
    );
  }
}

class _MergeDropPainter extends CustomPainter {
  const _MergeDropPainter(this.controller);

  final MergeDropController controller;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.boardBackground,
    );
    _drawDangerLine(canvas, size);
    _drawBalls(canvas, size);
    _drawPreview(canvas, size);
  }

  /// Dünya birimini piksele çeviren **tek** ölçek.
  ///
  /// Hem x hem y hem de yarıçap bununla çarpılır. Ayrı ölçekler kullanmak
  /// (x→width, y→height, yarıçap→shortestSide) daireleri elipse çevirip
  /// fizikte tam temas eden topların ekranda boşluklu görünmesine yol
  /// açıyordu.
  double _scale(Size size) => size.width;

  void _drawDangerLine(Canvas canvas, Size size) {
    final y = controller.dangerY * _scale(size);
    final paint = Paint()
      ..color = AppColors.danger.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  void _drawBalls(Canvas canvas, Size size) {
    for (final ball in controller.balls) {
      _drawBall(
        canvas,
        size,
        ball.x,
        ball.y,
        ball.level,
        alpha: 1,
        // Birleşen top şişerek gelir (bkz. DropBall.drawRadius).
        worldRadius: ball.drawRadius,
      );
    }
  }

  void _drawPreview(Canvas canvas, Size size) {
    final radius = mergeDropRadiusForLevel(controller.currentLevel);
    final x = controller.aimX;
    final y = radius + 0.015;
    _drawBall(
      canvas,
      size,
      x,
      y,
      controller.currentLevel,
      alpha: controller.canDrop ? 0.72 : 0.32,
    );
  }

  void _drawBall(
    Canvas canvas,
    Size size,
    double x,
    double y,
    int level, {
    required double alpha,
    double? worldRadius,
  }) {
    final scale = _scale(size);
    final radius = (worldRadius ?? mergeDropRadiusForLevel(level)) * scale;
    final center = Offset(x * scale, y * scale);
    final color = _mergeDropLineColor(level);
    final onColor = LineTheme.readableOn(color);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: alpha),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.75 * alpha),
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: mergeDropLabelForLevel(level),
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: radius * 0.58,
          fontWeight: FontWeight.w900,
          color: onColor.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center.translate(-textPainter.width / 2, -textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MergeDropPainter oldDelegate) => true;
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

Color _mergeDropLineColor(int level) {
  const colors = <Color>[
    Color(0xFFE30613),
    Color(0xFF009A44),
    Color(0xFF00AEEF),
    Color(0xFFE6007E),
    Color(0xFF6A2C91),
    Color(0xFFB58500),
    Color(0xFFF05A8A),
  ];
  return colors[(level - 1).clamp(0, colors.length - 1)];
}
