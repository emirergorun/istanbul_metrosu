import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_host.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/hud_widgets.dart';
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/simit_catch_controller.dart';
import '../domain/simit_catch_state.dart';
import 'simit_catch_painter.dart';

/// Simit Kap ekranı: ortak HUD, Boğaz sahnesi, yolculuk şeridi.
class SimitCatchScreen extends StatefulWidget {
  const SimitCatchScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<SimitCatchScreen> createState() => _SimitCatchScreenState();
}

class _SimitCatchScreenState extends State<SimitCatchScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  SimitCatchController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  bool _playedCrashSound = false;
  int _seenStationPulse = 0;
  int _seenAwardPulse = 0;
  int _seenBumpPulse = 0;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'SimitCatchControls');

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
    final controller = SimitCatchController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, SimitCatchController.id),
      random: scope.challengeRandomFor(widget.journey, SimitCatchController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      session: JourneyScope.sessionFor(context, widget.journey),
    );
    controller.reporter = scope.runReporter;
    // Sayaç tabanları koşudan okunur: yolculuğun ortasında açılan ekran
    // geçmiş durak bildirimlerini yeniden oynatmasın.
    _seenStationPulse = controller.stationBonusPulse;
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

    if (controller.awardPulse != _seenAwardPulse) {
      _seenAwardPulse = controller.awardPulse;
      if (controller.lastAwardSwish) {
        _haptic(HapticFeedback.mediumImpact);
        _sound(GameSound.combo);
      } else {
        _haptic(HapticFeedback.selectionClick);
        _sound(GameSound.clear);
      }
    }

    if (controller.bumpPulse != _seenBumpPulse) {
      _seenBumpPulse = controller.bumpPulse;
      _haptic(HapticFeedback.lightImpact);
    }

    if (controller.status == GameStatus.gameOver && !_playedCrashSound) {
      _playedCrashSound = true;
      _haptic(HapticFeedback.heavyImpact);
      _sound(GameSound.invalid);
    } else if (controller.status == GameStatus.playing) {
      _playedCrashSound = false;
    }

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      _playedArrivalSound = false;
    }

    _syncMusic();
    // Not: bilerek setState() yok — fizik saniyede ~60 kez haber veriyor.
    // Canlı kalması gereken kısmı build()'deki ListenableBuilder çiziyor.
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
    final controller = _controller;
    if (controller == null || controller.status != GameStatus.playing) return;
    controller.flap();
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
    AppRoutes.exitToGallery(context);
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
                        _SimitCatchHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _SimitCatchPlayArea(
                            controller: controller,
                            onFlap: _flap,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        JourneyStatusBar(
                          gameId: SimitCatchController.id,
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
                SprintBanner(pulse: controller.sprintPulse),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(
    SimitCatchController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    final sea = controller.endReason == SimitCatchEnd.sea;
    return ResultOverlay(
      journey: controller.journey,
      gameId: SimitCatchController.id,
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
        StatRow(label: 'Geçilen simit', value: '${controller.simitsPassed}'),
        StatRow(label: 'Tam isabet', value: '${controller.swishes}'),
        StatRow(label: 'En uzun seri', value: '${controller.bestStreak}'),
      ],
      gameOverTitle: sea ? 'Denize düştün' : 'Simidi kaçırdın',
      gameOverSubtitle: sea
          ? 'Martı kanat çırpmayı bırakınca Boğaz\'a indi.'
          : 'Martı simidin içinden geçemeden simit geride kaldı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _SimitCatchHud extends StatelessWidget {
  const _SimitCatchHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final SimitCatchController controller;
  final Color accent;
  final VoidCallback onPause;

  /// Seri rozetinin rengi: seri sürerken simit kabuğunun turuncusu.
  static const Color _streakColor = Color(0xFFFFB04A);

  @override
  Widget build(BuildContext context) {
    final streak = controller.streak;
    return JourneyHud(
      run: controller,
      accent: accent,
      onPause: onPause,
      gameScore: controller.scoreThisGame,
      chips: <Widget>[
        HudStat.value(
          label: 'SERİ',
          value: '×$streak',
          semanticLabel: 'Üst üste $streak tam isabet',
          accent: streak > 0 ? _streakColor : null,
        ),
        HudStat.value(
          label: 'SİMİT',
          value: '${controller.simitsPassed}',
          semanticLabel: '${controller.simitsPassed} simit geçildi',
        ),
      ],
    );
  }
}

/// Oyun alanı: sahnenin her yerine dokunmak kanat çırpar.
class _SimitCatchPlayArea extends StatelessWidget {
  const _SimitCatchPlayArea({required this.controller, required this.onFlap});

  final SimitCatchController controller;
  final VoidCallback onFlap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Basma anında: Flappy türünde kanat parmak değdiği an çırpılır,
      // kalkmasını beklemek her kanadı gecikmeli hissettiriyor.
      onTapDown: (_) => onFlap(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: CustomPaint(
          painter: SimitCatchPainter(controller),
          child: const SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: HudHint(text: 'Dokun: kanat çırp'),
              ),
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: HudToast(text: text ?? '', accent: accent),
        ),
      ),
    );
  }
}
