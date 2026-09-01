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
import '../application/station_memory_controller.dart';
import '../domain/station_memory_state.dart';

class StationMemoryScreen extends StatefulWidget {
  const StationMemoryScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<StationMemoryScreen> createState() => _StationMemoryScreenState();
}

class _StationMemoryScreenState extends State<StationMemoryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  StationMemoryController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenLineLevel = 1;
  Timer? _bannerTimer;
  String? _bannerText;

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
    final stations = scope.metro
        .stations()
        .where((station) => station.lineId == widget.journey.lineId)
        .map((station) => station.name)
        .toList();
    final controller = StationMemoryController(
      journey: widget.journey,
      store: scope.store,
      stationNames: stations,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: StationMemoryController.id,
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
      _showBanner('${controller.lineLabel} hafızası açıldı');
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

  void _choose(String stationName) {
    final accepted = _controller?.choose(stationName) ?? false;
    _haptic(accepted ? HapticFeedback.lightImpact : HapticFeedback.vibrate);
    _sound(accepted ? GameSound.place : GameSound.invalid);
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
                    _MemoryHud(
                      controller: controller,
                      accent: accent,
                      onPause: controller.pause,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: _MemoryPlayArea(
                        controller: controller,
                        accent: accent,
                        onChoose: _choose,
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
    );
  }

  Widget _buildResult(
    StationMemoryController controller,
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
        StatRow(label: 'Doğru round', value: '${controller.successes}'),
        StatRow(label: 'Hafıza hattı', value: controller.lineLabel),
      ],
      gameOverTitle: 'Sıra karıştı',
      gameOverSubtitle: 'Durakları gösterildiği sırayla seçmen gerekiyordu.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }

  String? _nextStopName(StationMemoryController controller) {
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

class _MemoryHud extends StatelessWidget {
  const _MemoryHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final StationMemoryController controller;
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
          label: 'Hafıza',
          value: '${controller.lineLabel} · ${controller.successes}',
          accent: _memoryLineColor(controller.lineLevel),
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

class _MemoryPlayArea extends StatelessWidget {
  const _MemoryPlayArea({
    required this.controller,
    required this.accent,
    required this.onChoose,
  });

  final StationMemoryController controller;
  final Color accent;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final round = controller.round;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.boardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            round.phase == StationMemoryPhase.showing
                ? 'Durak sırasını aklında tut'
                : 'Aynı sırayla seç',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            round.phase == StationMemoryPhase.showing
                ? 'Birazdan bu kartlar kapanacak.'
                : '${round.answerIndex + 1}. durağı seç',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SequenceStrip(
            round: round,
            accent: accent,
            lineColor: _memoryLineColor(controller.lineLevel),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final station in round.options)
                    FilledButton.tonal(
                      onPressed: round.phase == StationMemoryPhase.answering
                          ? () => onChoose(station)
                          : null,
                      child: Text(station),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SequenceStrip extends StatelessWidget {
  const _SequenceStrip({
    required this.round,
    required this.accent,
    required this.lineColor,
  });

  final StationMemoryRound round;
  final Color accent;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (var i = 0; i < round.sequence.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minWidth: 72),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: round.phase == StationMemoryPhase.showing
                  ? lineColor.withValues(alpha: 0.24)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
              border: Border.all(
                color: i < round.answerIndex
                    ? AppColors.success
                    : i == round.answerIndex
                    ? accent
                    : AppColors.outline,
                width: i == round.answerIndex ? 2 : 1,
              ),
            ),
            child: Text(
              round.phase == StationMemoryPhase.showing
                  ? round.sequence[i]
                  : i < round.answerIndex
                  ? 'Tamam'
                  : '${i + 1}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
      ],
    );
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
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

Color _memoryLineColor(int level) {
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
