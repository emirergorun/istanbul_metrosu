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
import '../application/metro_merge_controller.dart';
import '../domain/metro_tile.dart';

class MetroMergeScreen extends StatefulWidget {
  const MetroMergeScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<MetroMergeScreen> createState() => _MetroMergeScreenState();
}

class _MetroMergeScreenState extends State<MetroMergeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  MetroMergeController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MetroMergeControls');

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
    final controller = MetroMergeController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: MetroMergeController.id,
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

  void _move(MetroMoveDirection direction) {
    final controller = _controller;
    if (controller == null) return;

    final outcome = controller.move(direction);
    if (!outcome.accepted) {
      _haptic(HapticFeedback.vibrate);
      _sound(GameSound.invalid);
      return;
    }

    if (outcome.terminalClears > 0 || outcome.didClear) {
      _haptic(HapticFeedback.mediumImpact);
      _sound(outcome.linesCleared >= 2 ? GameSound.combo : GameSound.clear);
    } else {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.place);
    }

    if (outcome.beatRecord) {
      _haptic(HapticFeedback.mediumImpact);
      _showBanner('Rekoru geçtin — durağına kadar devam');
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => MetroMoveDirection.left,
      LogicalKeyboardKey.arrowRight => MetroMoveDirection.right,
      LogicalKeyboardKey.arrowUp => MetroMoveDirection.up,
      LogicalKeyboardKey.arrowDown => MetroMoveDirection.down,
      _ => null,
    };
    if (direction != null) _move(direction);
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
                      _MergeHud(
                        controller: controller,
                        accent: accent,
                        onPause: controller.pause,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        child: _MetroMergeBoard(
                          controller: controller,
                          onMove: _move,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DirectionPad(
                        enabled: controller.status == GameStatus.playing,
                        accent: accent,
                        onMove: _move,
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
    MetroMergeController controller,
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
        StatRow(label: 'Birleşme', value: '${controller.totalMerges}'),
        StatRow(
          label: 'Temizlenen hat',
          value: '${controller.totalClearedLines}',
        ),
        StatRow(
          label: 'Final hat temizliği',
          value: '${controller.terminalClears}',
        ),
      ],
      gameOverTitle: 'Hat kilitlendi',
      gameOverSubtitle: 'Tahta doldu ve birleşebilecek tren kalmadı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }

  String? _nextStopName(MetroMergeController controller) {
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

class _MergeHud extends StatelessWidget {
  const _MergeHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final MetroMergeController controller;
  final Color accent;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return JourneyHud(run: controller, accent: accent, onPause: onPause);
  }
}

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.enabled,
    required this.accent,
    required this.onMove,
  });

  final bool enabled;
  final Color accent;
  final ValueChanged<MetroMoveDirection> onMove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hat Birleştir yön kontrolleri',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _DirectionButton(
            icon: Icons.keyboard_arrow_up_rounded,
            enabled: enabled,
            accent: accent,
            onPressed: () => onMove(MetroMoveDirection.up),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _DirectionButton(
                icon: Icons.keyboard_arrow_left_rounded,
                enabled: enabled,
                accent: accent,
                onPressed: () => onMove(MetroMoveDirection.left),
              ),
              const SizedBox(width: AppSpacing.xl),
              _DirectionButton(
                icon: Icons.keyboard_arrow_right_rounded,
                enabled: enabled,
                accent: accent,
                onPressed: () => onMove(MetroMoveDirection.right),
              ),
            ],
          ),
          _DirectionButton(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: enabled,
            accent: accent,
            onPressed: () => onMove(MetroMoveDirection.down),
          ),
        ],
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.icon,
    required this.enabled,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor: accent.withValues(alpha: 0.16),
          foregroundColor: accent,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textMuted,
        ),
        icon: Icon(icon, size: 26),
      ),
    );
  }
}

class _MetroMergeBoard extends StatelessWidget {
  const _MetroMergeBoard({required this.controller, required this.onMove});

  final MetroMergeController controller;
  final ValueChanged<MetroMoveDirection> onMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanEnd: (details) {
              final velocity = details.velocity.pixelsPerSecond;
              if (velocity.distance < 60) return;
              if (velocity.dx.abs() > velocity.dy.abs()) {
                onMove(
                  velocity.dx > 0
                      ? MetroMoveDirection.right
                      : MetroMoveDirection.left,
                );
              } else {
                onMove(
                  velocity.dy > 0
                      ? MetroMoveDirection.down
                      : MetroMoveDirection.up,
                );
              }
            },
            child: SizedBox.square(
              dimension: size,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.boardBackground,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  children: <Widget>[
                    for (var row = 0; row < controller.config.gridSize; row++)
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            for (
                              var col = 0;
                              col < controller.config.gridSize;
                              col++
                            )
                              Expanded(
                                child: _BoardCell(
                                  tile: controller.grid[row][col],
                                  dense: controller.config.gridSize >= 6,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardCell extends StatelessWidget {
  const _BoardCell({required this.tile, required this.dense});

  final MetroTile? tile;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final current = tile;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.all(dense ? 3 : 4),
      decoration: BoxDecoration(
        color: current == null ? AppColors.emptyCell : _metroLineColor(current),
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        border: current?.rank == metroMergeMaxRank
            ? Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2)
            : null,
      ),
      child: current == null ? null : _TileContent(tile: current, dense: dense),
    );
  }
}

class _TileContent extends StatelessWidget {
  const _TileContent({required this.tile, required this.dense});

  final MetroTile tile;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = _metroLineColor(tile);
    final foreground = LineTheme.readableOn(color);
    return Padding(
      padding: EdgeInsets.all(dense ? 4 : 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            tile.lineLabel,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: dense ? 15 : 19,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

Color _metroLineColor(MetroTile tile) {
  const colors = <Color>[
    Color(0xFFE30613), // M1 kırmızı
    Color(0xFF009A44), // M2 yeşil
    Color(0xFF00AEEF), // M3 mavi
    Color(0xFFE6007E), // M4 pembe
    Color(0xFF6A2C91), // M5 mor
    Color(0xFFB58500), // M6 altın
    Color(0xFFF05A8A), // M7 pembe
    Color(0xFF0067B1), // M8 lacivert
    Color(0xFFFFD300), // M9 sarı
  ];
  return colors[tile.lineIndex % colors.length];
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
