import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
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
import '../application/lane_runner_controller.dart';
import 'lane_runner_scene_painter.dart';

class LaneRunnerScreen extends StatefulWidget {
  const LaneRunnerScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<LaneRunnerScreen> createState() => _LaneRunnerScreenState();
}

class _LaneRunnerScreenState extends State<LaneRunnerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  LaneRunnerController? _controller;
  LaneRunnerScenePainter? _painter;
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

  /// Her vsync karesinde bir artar; sahne bununla boyanır. Fizik
  /// motorun `Timer`'ında ve ekran yenilemesine hizalı değil; çizici
  /// engelleri son fizik adımından bu yana ileri kestirir (bkz. Makinist).
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker((_) => _frame.value++);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
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
      discovery: scope.discoveryFor(widget.journey, LaneRunnerController.id),
      // Meydan okuma modunda tohumlu rastgelelik; Serbest Oyun'da `null`
      // gelir ve oyun kendi tohumsuz `Random()`'ını kurar.
      random: scope.challengeRandomFor(widget.journey, LaneRunnerController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Yolculuk ortak: süren bir yolculuk varsa oyun onun içine girer —
      // puan, kalan süre ve geçilen duraklar oradan devam eder.
      session: JourneyScope.sessionFor(context, widget.journey),
    );
    // Biten koşu günlük görevlere ve Yolculuk Kartı rozetlerine buradan
    // ulaşıyor. Oyun hiçbirini tanımaz; tek bildiği bir rapor hedefi.
    controller.reporter = scope.runReporter;
    // Sayaç tabanları koşudan okunur: yolculuk ekranlardan uzun yaşıyor,
    // sıfırdan başlanırsa yolculuğun ortasında açılan ekran geçmiş durak
    // bildirimlerini yeniden oynatır.
    _seenStationPulse = controller.stationBonusPulse;
    _seenLineLevel = controller.lineLevel;
    controller.addListener(_onControllerChanged);
    _controller = controller;
    _painter = LaneRunnerScenePainter(
      controller: controller,
      colorForLevel: _runnerLineColor,
      frame: _frame,
    );
    // Oyun başlamadan sahneyi bir kez görünmez çizip GPU'yu ısıt: ilk
    // saniyelerdeki ve yeni bölgeye ilk girişteki takılma oyundan önceye,
    // ekranın açılış geçişine kayar.
    final warm = _painter!.warmUp(MediaQuery.sizeOf(context));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final image in warm) {
        image.dispose();
      }
    });
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
          // Yalnızca bu içerik controller'ı dinler ve her fizik tikinde
          // yeniden kurulur; PopScope/KeyboardListener/Scaffold sarmalayıcıları
          // hiç değişmediği için bir kez kurulup öyle kalır.
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              // Tam ekran 3B sahne: her vsync karesinde yalnız boyanır,
              // widget ağacı yeniden kurulmaz. Ekranın her yerinde
              // kaydırma ray değiştirir.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -80) {
                      _moveLeft();
                    } else if (velocity > 80) {
                      _moveRight();
                    }
                  },
                  child: RepaintBoundary(child: CustomPaint(painter: _painter)),
                ),
              ),
              const Positioned.fill(child: IgnorePointer(child: _Scrims())),
              // HUD ve denetimler controller'ı dinler.
              ListenableBuilder(
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
                            const Spacer(),
                            IgnorePointer(
                              child: Text(
                                'Sağa/sola kaydır ya da ok tuşlarıyla ray değiştir',
                                style: AppText.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _LaneControls(
                              onLeft: _moveLeft,
                              onRight: _moveRight,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            JourneyStatusBar(
                              gameId: LaneRunnerController.id,
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
                        onSkipped: () =>
                            AppScope.of(context).audio.stopLongForm(),
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
            ],
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
      // Sosyal çıkış için rota ve oyun kimliği; panel meydan okuma
      // modunda karşılaştırma, normal koşuda davet gösteriyor.
      journey: controller.journey,
      gameId: LaneRunnerController.id,
      isArrival: controller.status == GameStatus.arrived,
      discovery: controller.discovery,
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
      gameScore: controller.scoreThisGame,
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

/// Üstte ve altta karartma: HUD ve düğmeler açık gökyüzünde de okunur.
class _Scrims extends StatelessWidget {
  const _Scrims();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[0, 0.18, 0.7, 1],
          colors: <Color>[
            Color(0xAA000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xCC000000),
          ],
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
