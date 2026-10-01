import 'dart:async';
import 'dart:math' as math;

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
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/result_overlay.dart';
import '../application/merge_drop_controller.dart';
import '../domain/merge_drop_state.dart';
import 'merge_drop_effects.dart';
import 'merge_drop_painter.dart';
import 'metro_token.dart';

/// Hat Düşür'ün kalıcı en iyi değerlerinin anahtarları (rozetler bunu okur).
const String _bestLevelStat = 'max_level';
const String _bestChainStat = 'best_chain';

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
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MergeDropControls');

  late MetroTokenPalette _palette;

  /// Birleşme efektleri ve onların saati.
  final MergeDropEffects _effects = MergeDropEffects();

  /// Parmak tahtada mı (nişan alınıyor mu)?
  bool _holding = false;

  /// Bu koşudan önceki kalıcı en büyük hat — "rekor hat" bildirimi için.
  int _historicBest = 0;

  /// Kritik tehlikeye girişte bir kez uyarı sesi.
  MergeDropDanger _seenDanger = MergeDropDanger.calm;

  late final AnimationController _bannerAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
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
    _palette = MetroTokenPalette.from(scope.metro);
    _historicBest =
        scope.achievements?.gameBest(MergeDropController.id, _bestLevelStat) ??
        0;
    final controller = MergeDropController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, MergeDropController.id),
      // Meydan okuma modunda tohumlu rastgelelik; Serbest Oyun'da `null`
      // gelir ve oyun kendi tohumsuz `Random()`'ını kurar.
      random: scope.challengeRandomFor(widget.journey, MergeDropController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Yolculuk ortak: süren bir yolculuk varsa oyun onun içine girer —
      // puan, kalan süre ve geçilen duraklar oradan devam eder.
      session: JourneyScope.sessionFor(context, widget.journey),
    )..setPoolAspect(mergeDropPoolAspect);
    // Biten koşu günlük görevlere ve Yolculuk Kartı rozetlerine buradan
    // ulaşıyor. Oyun hiçbirini tanımaz; tek bildiği bir rapor hedefi.
    controller.reporter = scope.runReporter;
    // Sayaç tabanları koşudan okunur: yolculuk ekranlardan uzun yaşıyor,
    // sıfırdan başlanırsa yolculuğun ortasında açılan ekran geçmiş durak
    // bildirimlerini yeniden oynatır.
    _seenStationPulse = controller.stationBonusPulse;
    controller.addListener(_onControllerChanged);
    _controller = controller;
    controller.start();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    final events = controller.takeEvents();
    if (events.isNotEmpty) _onMerges(controller, events);

    final danger = controller.danger;
    if (danger != _seenDanger) {
      if (danger == MergeDropDanger.critical &&
          controller.status == GameStatus.playing) {
        _sound(GameSound.invalid);
        _haptic(HapticFeedback.mediumImpact);
      }
      _seenDanger = danger;
    }

    if (controller.stationBonusPulse != _seenStationPulse) {
      _seenStationPulse = controller.stationBonusPulse;
      _haptic(HapticFeedback.selectionClick);
      _sound(GameSound.station);
      _showBanner('Durak bonusu +${controller.lastStationBonus}');
    }

    if (controller.status == GameStatus.gameOver) {
      _effects.clear();
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

  /// Birleşmelerin his katmanı: efekt, ses, titreşim, bildirim ve rozet.
  ///
  /// Hiyerarşi bilerek seyrek: sıradan birleşme hafif bir dokunuş, zincir
  /// ve yeni hat bir tık güçlü, M11 en güçlü. Her birleşmede titreşim
  /// oyunu ucuz gösterirdi; bu yüzden aynı karedeki birleşmeler tek
  /// geri bildirimde toplanır.
  void _onMerges(MergeDropController controller, List<MergeDropEvent> events) {
    for (final event in events) {
      _effects.addMerge(event);
    }
    final top = events.reduce((a, b) => a.level >= b.level ? a : b);
    final longest = events.map((e) => e.chain).reduce(math.max);
    final achievements = AppScope.of(context).achievements;

    if (top.level >= mergeDropMaxLevel) {
      _haptic(HapticFeedback.heavyImpact);
      _sound(GameSound.combo);
      _showBanner('Bütün hatlar · M11', millis: 1400);
    } else if (top.newRunMax && top.level >= 5) {
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.combo);
      final record = top.level > _historicBest && _historicBest >= 5;
      _showBanner(
        record
            ? 'Rekor hat · ${mergeDropLabelForLevel(top.level)}'
            : 'Yeni hat · ${mergeDropLabelForLevel(top.level)}',
        millis: 800,
      );
    } else if (longest >= 3) {
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.combo);
    } else {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.clear);
    }

    // Rozetler koşunun ortasında açılır; değer yalnız büyür.
    achievements?.recordGameBest(
      MergeDropController.id,
      _bestLevelStat,
      controller.maxLevel,
    );
    achievements?.recordGameBest(
      MergeDropController.id,
      _bestChainStat,
      controller.bestChain,
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
    if (status == GameStatus.gameOver) {
      _haptic(HapticFeedback.heavyImpact);
    }
  }

  @visibleForTesting
  MergeDropController? get debugController => _controller;

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

  void _showBanner(String text, {int millis = 1600}) {
    _bannerTimer?.cancel();
    _bannerText = text;
    _bannerAnimation.forward();
    _bannerTimer = Timer(Duration(milliseconds: millis), () {
      if (mounted) _bannerAnimation.reverse();
    });
  }

  // --- Giriş: sürükle nişan al, bırak düşür ---

  void _aimTo(double worldX) => _controller?.moveAim(worldX);

  void _beginAim(double worldX) {
    _aimTo(worldX);
    setState(() => _holding = true);
  }

  /// Parmak kalktı. [cancel]: parmak tahtanın üstüne çekilip bırakıldı —
  /// oyuncu vazgeçti, parça düşmez.
  void _release({bool cancel = false}) {
    setState(() => _holding = false);
    if (cancel) return;
    _drop();
  }

  void _drop() {
    if (_controller?.drop() == true) {
      _sound(GameSound.place);
    } else {
      // Doğum noktası dolu ya da bekleme sürüyor: hafif bir ret.
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
                        palette: _palette,
                        accent: accent,
                        onPause: controller.pause,
                      ),
                      const SizedBox(height: AppSpacing.stack),
                      Expanded(
                        child: _Playfield(
                          controller: controller,
                          palette: _palette,
                          effects: _effects,
                          holding: _holding,
                          onBegin: _beginAim,
                          onMove: _aimTo,
                          onRelease: _release,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.stack),
                      JourneyStatusBar(
                        gameId: MergeDropController.id,
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
                  onRestart: () {
                    _effects.clear();
                    controller.restart();
                  },
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
    // Rekor, önceki bir rekoru geçmek demek: ilk oyunda her hat "rekor"
    // olurdu.
    final record = _historicBest >= 5 && controller.maxLevel > _historicBest;
    return ResultOverlay(
      // Sosyal çıkış için rota ve oyun kimliği; panel meydan okuma
      // modunda karşılaştırma, normal koşuda davet gösteriyor.
      journey: controller.journey,
      gameId: MergeDropController.id,
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
        StatRow(
          label: record ? 'En büyük hat · rekor' : 'En büyük hat',
          value: controller.maxLabel,
          highlight: record,
          accent: _palette.colorOf(controller.maxLevel),
        ),
        StatRow(label: 'Birleşme', value: '${controller.merges}'),
        StatRow(
          label: 'En uzun zincir',
          value: controller.bestChain >= 2 ? '×${controller.bestChain}' : '—',
        ),
      ],
      gameOverTitle: 'Depo doldu',
      gameOverSubtitle: 'Jetonlar tehlike çizgisinin üstüne yığıldı.',
      onRestart: () {
        _effects.clear();
        controller.restart();
      },
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

/// Üst şerit: ortak HUD ve oyuna özgü tek gösterge — bu koşunun en büyük
/// hattı. Şimdi/sonra parçaları oyun alanının hemen üstünde.
class _DropHud extends StatelessWidget {
  const _DropHud({
    required this.controller,
    required this.palette,
    required this.accent,
    required this.onPause,
  });

  final MergeDropController controller;
  final MetroTokenPalette palette;
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
        HudStat.value(
          label: 'EN BÜYÜK',
          value: controller.maxLabel,
          semanticLabel: 'En büyük hat ${controller.maxLabel}',
          accent: palette.colorOf(controller.maxLevel),
        ),
      ],
    );
  }
}

/// Oyun alanı: şimdi/sonra şeridi, depo ve dokunuş.
///
/// **Fizik alanı = çizilen alan.** Depo sabit bir oranla
/// ([mergeDropPoolAspect]) mevcut alana sığdırılır; dünya birimi depo
/// genişliğidir. Sahne görseli ve elle ölçülmüş koordinat yok.
class _Playfield extends StatelessWidget {
  const _Playfield({
    required this.controller,
    required this.palette,
    required this.effects,
    required this.holding,
    required this.onBegin,
    required this.onMove,
    required this.onRelease,
  });

  final MergeDropController controller;
  final MetroTokenPalette palette;
  final MergeDropEffects effects;
  final bool holding;
  final ValueChanged<double> onBegin;
  final ValueChanged<double> onMove;
  final void Function({bool cancel}) onRelease;

  /// Şimdi/sonra şeridinin yüksekliği.
  static const double _queueHeight = 32;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(
          constraints.maxWidth,
          math.max(0, constraints.maxHeight - _queueHeight - AppSpacing.sm * 2),
        );
        final width = math.min(
          available.width,
          available.height / mergeDropPoolAspect,
        );
        final height = width * mergeDropPoolAspect;
        final scale = width / MergeDropController.worldWidth;

        double worldX(Offset local) => (local.dx / scale).clamp(0.0, 1.0);

        // Depo başparmağa yakın, ekranın altına yaslı. Üstte kalan boşluğu
        // soluk şehir silueti doldurur (bkz. [MergeDropSkylinePainter]).
        final spare =
            constraints.maxHeight - height - _queueHeight - AppSpacing.sm;
        return Column(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: math.min(math.max(0.0, spare - AppSpacing.sm), 120),
                  child: const ExcludeSemantics(
                    child: CustomPaint(painter: MergeDropSkylinePainter()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: width,
              height: _queueHeight,
              child: _QueueStrip(controller: controller, palette: palette),
            ),
            const SizedBox(height: AppSpacing.sm),
            Listener(
              key: const ValueKey<String>('merge-drop-board'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => onBegin(worldX(e.localPosition)),
              onPointerMove: (e) => onMove(worldX(e.localPosition)),
              // Tahtanın üstüne çekilip bırakmak vazgeçmek demek.
              onPointerUp: (e) => onRelease(cancel: e.localPosition.dy < -24),
              onPointerCancel: (_) => onRelease(cancel: true),
              child: SizedBox(
                width: width,
                height: height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MergeDropPainter(
                      controller: controller,
                      palette: palette,
                      effects: effects,
                      showGuide: holding,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Şimdi ve sonra: iki küçük jeton, aynı tasarımla.
class _QueueStrip extends StatelessWidget {
  const _QueueStrip({required this.controller, required this.palette});

  final MergeDropController controller;
  final MetroTokenPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget slot(String label, int level, double size, String semantic) =>
        Semantics(
          label: '$semantic ${mergeDropLabelForLevel(level)}',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: AppText.micro),
                const SizedBox(width: AppSpacing.sm),
                MetroTokenView(level: level, palette: palette, size: size),
              ],
            ),
          ),
        );
    return Row(
      children: <Widget>[
        slot('ŞİMDİ', controller.currentLevel, 30, 'Şimdi'),
        const Spacer(),
        Opacity(
          opacity: 0.85,
          child: slot('SONRA', controller.nextLevel, 24, 'Sonra'),
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
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          if (t == 0 || text == null) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: FadeTransition(
                opacity: animation,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -12),
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
