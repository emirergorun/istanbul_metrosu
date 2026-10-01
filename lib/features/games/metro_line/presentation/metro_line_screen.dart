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
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/metro_line_controller.dart';
import '../domain/metro_line_state.dart';
import 'metro_line_backdrop.dart';
import 'metro_line_board_painter.dart';

class MetroLineScreen extends StatefulWidget {
  const MetroLineScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<MetroLineScreen> createState() => _MetroLineScreenState();
}

class _MetroLineScreenState extends State<MetroLineScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  MetroLineController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  bool _playedGameOverSound = false;
  int _seenStationPulse = 0;
  int _seenDeparture = 0;
  int _seenLevel = 1;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MetroLineControls');

  /// Testler oyunu doğrudan izleyebilsin diye.
  @visibleForTesting
  MetroLineController? get debugController => _controller;

  /// Çıkan trenin kayma animasyonu.
  late final AnimationController _departure = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Önü kapalı trene dokununca kırmızı uyarı.
  late final AnimationController _blocked = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final AnimationController _bannerAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Bölüm geçişi: son tren eski adadan çıkar, eski ada çekilir, yeni ada
  /// sekerek belirir, trenler havadan raylarına iner. Geçiş sürerken
  /// dokunuşlar yok sayılır. Zaman çizelgesi [_LevelTransition]'da.
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
    value: 1,
  );

  /// Geçişte eski adada çıkan son tren ve o adanın boyu.
  MetroLineTrain? _outgoingTrain;
  int _outgoingSize = metroLineMinSize;

  MetroLineTrain? _departingTrain;
  int _departingSize = metroLineMinSize;
  int _departingLevel = 1;
  int? _blockedTrainId;

  /// Son çarpma: hangi tren, kaç hücre ilerleyip neye çarptı.
  _Bump? _bump;
  bool _bumpImpactPlayed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blocked.addListener(_onBumpTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final scope = AppScope.of(context);
    _audio = scope.audio;
    final controller = MetroLineController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, MetroLineController.id),
      random: scope.challengeRandomFor(widget.journey, MetroLineController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Ortak oturum yalnız aynı rotadaysa; bkz. [JourneyScope.sessionFor].
      session: JourneyScope.sessionFor(context, widget.journey),
    );
    controller.reporter = scope.runReporter;
    _seenStationPulse = controller.stationBonusPulse;
    _seenDeparture = controller.departurePulse;
    _seenLevel = controller.level;
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

    if (controller.level != _seenLevel) {
      _seenLevel = controller.level;
      // Dokunuşla gelen geçişi [_tapTrain] baştan başlatır; buraya düşen
      // değişim (tekrar oyna) yalnız yeni adanın girişini oynatır.
      _outgoingTrain = null;
      _transition.forward(from: _LevelTransition.inStart);
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.clear);
      _showBanner('DEPO BOŞALDI · ${controller.level}. SEVİYE');
    }

    if (controller.status == GameStatus.gameOver && !_playedGameOverSound) {
      _playedGameOverSound = true;
      _haptic(HapticFeedback.heavyImpact);
      _sound(GameSound.invalid);
    } else if (controller.status == GameStatus.playing) {
      _playedGameOverSound = false;
    }

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      _playedArrivalSound = false;
    }

    _syncMusic();
    // Bilerek setState() yok: canlı kalması gereken her şey build()'deki
    // ListenableBuilder'ın içinde.
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
    _departure.dispose();
    _blocked.removeListener(_onBumpTick);
    _blocked.dispose();
    _transition.dispose();
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

  /// Çarpma anı geldiğinde bir kez titreşim ve ses.
  void _onBumpTick() {
    if (_bumpImpactPlayed || _bump == null) return;
    if (_blocked.value < _Bump.impactAt) return;
    _bumpImpactPlayed = true;
    _haptic(HapticFeedback.heavyImpact);
    _sound(GameSound.invalid);
  }

  /// Önü kapalı trenin önündeki boş kare sayısı ve yolu kesen tren.
  _Bump _bumpFor(MetroLineController controller, MetroLineTrain train) {
    var free = 0;
    int? hit;
    for (final cell in train.corridor(controller.size)) {
      final other = controller.trainAt(cell);
      if (other != null && other.id != train.id) {
        hit = other.id;
        break;
      }
      free++;
    }
    final d = train.direction.delta;
    return _Bump(
      trainId: train.id,
      // Vagon hücreden kısa: burun komşu karenin vagonuna 0,2 hücrede değer.
      distance: free + 0.2,
      hitTrainId: hit,
      direction: Offset(d.x.toDouble(), d.y.toDouble()),
    );
  }

  void _tapTrain(int trainId) {
    final controller = _controller;
    if (controller == null) return;
    // Bölüm geçişi sürerken tahta henüz yerine oturmadı.
    if (_transition.isAnimating) return;

    // Çıkış animasyonu için treni **dokunmadan önce** yakala: kabul
    // edilirse controller onu listeden çıkaracak.
    final train = controller.trains.firstWhere(
      (t) => t.id == trainId,
      orElse: () => controller.trains.first,
    );
    final size = controller.size;
    final level = controller.level;

    final result = controller.tap(trainId);
    switch (result) {
      case MetroLineTapResult.cleared:
        _haptic(HapticFeedback.lightImpact);
        _sound(GameSound.place);
        if (controller.departurePulse != _seenDeparture) {
          _seenDeparture = controller.departurePulse;
          // Seviye bu dokunuşla değiştiyse tahta da değişti; eski trenin
          // yeni tahtada çizilecek yeri yok.
          if (controller.level == level) {
            setState(() {
              _departingTrain = train;
              _departingSize = size;
              _departingLevel = level;
            });
            _departure.forward(from: 0);
          } else {
            // Son tren: eski adada çıkışını tamamlasın, sonra yeni ada.
            setState(() {
              _outgoingTrain = train;
              _outgoingSize = size;
            });
            _transition.forward(from: 0);
          }
        }
      case MetroLineTapResult.blocked:
        // Tren önündeki boşluğu gidip çarpar ve geri döner; titreşim ve
        // ses çarpma anında ([_onBumpTick]). Uzun yol daha uzun sürer.
        _haptic(HapticFeedback.selectionClick);
        final bump = _bumpFor(controller, train);
        setState(() {
          _blockedTrainId = trainId;
          _bump = bump;
          _bumpImpactPlayed = false;
        });
        _blocked.duration = Duration(
          milliseconds: 520 + (bump.distance * 110).round(),
        );
        _blocked.forward(from: 0);
      case MetroLineTapResult.ignored:
        break;
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      _controller?.requestHint();
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
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Stack(
              children: <Widget>[
                // Arka plan: gün batımında Boğaz; tahta denizde yüzen bir ada.
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: MetroLineIstanbulBackdrop()),
                  ),
                ),
                Column(
                  children: <Widget>[
                    // Üst bilgi alanının arkası mat. HUD'ın renkleri (soluk
                    // gri künye, yarı saydam hat rengi rozetler, rekor
                    // çubuğu) uygulamanın koyu zeminine göre ayarlı; gün
                    // batımı göğünün üstünde okunmuyordu. Şerit HUD'ı
                    // değiştirmiyor, yalnızca diğer oyunlardaki zemini
                    // arkasına koyuyor — üst alan her oyunda aynı kalsın.
                    ColoredBox(
                      color: AppColors.background,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.md,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: _MetroLineHud(
                            controller: controller,
                            accent: accent,
                            onPause: controller.pause,
                          ),
                        ),
                      ),
                    ),
                    // Şeridin alt kenarı göğe yumuşakça karışır; keskin bir
                    // çizgi sahneyi başlık çubuğuyla kesilmiş gösterirdi.
                    const _HudFade(),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: Column(
                            children: <Widget>[
                              _HeartRow(hearts: controller.hearts),
                              const SizedBox(height: AppSpacing.sm),
                              Expanded(
                                child: _MetroLineBoard(
                                  controller: controller,
                                  accent: accent,
                                  departure: _departure,
                                  blocked: _blocked,
                                  departingTrain:
                                      controller.level == _departingLevel
                                      ? _departingTrain
                                      : null,
                                  departingSize: _departingSize,
                                  blockedTrainId: _blockedTrainId,
                                  bump: _bump,
                                  transition: _transition,
                                  outgoingTrain: _outgoingTrain,
                                  outgoingSize: _outgoingSize,
                                  onTapTrain: _tapTrain,
                                  onHint: () {
                                    if (!_transition.isAnimating) {
                                      controller.requestHint();
                                    }
                                  },
                                  onTapEmpty: controller.clearHint,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Dokun: önü açık treni çıkar · Basılı tut: ipucu',
                                textAlign: TextAlign.center,
                                // Denizin üstünde okunsun: beyaz ve gölgeli.
                                style: AppText.caption.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  shadows: const <Shadow>[
                                    Shadow(
                                      color: Color(0xCC0B2236),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              JourneyStatusBar(
                                gameId: MetroLineController.id,
                                run: controller,
                                lineStations: AppScope.of(
                                  context,
                                ).metro.stationsOfLine(journey.lineId),
                                accent: accent,
                                isMoving:
                                    controller.status == GameStatus.playing,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
    MetroLineController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      journey: controller.journey,
      gameId: MetroLineController.id,
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
        StatRow(label: 'Çıkarılan tren', value: '${controller.clearedTrains}'),
        StatRow(
          label: 'Boşaltılan depo',
          value: '${controller.completedLevels}',
        ),
        StatRow(label: 'Ulaşılan seviye', value: '${controller.level}'),
      ],
      gameOverTitle: 'Hat tıkandı',
      gameOverSubtitle: 'Üç kez kapalı raya tren soktun.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

/// Mat HUD şeridinden sahneye geçiş: zeminden saydama kısa bir gradyan.
class _HudFade extends StatelessWidget {
  const _HudFade();

  /// Jeton satırıyla HUD arasındaki eski boşluğun yerini tutar.
  static const double height = 14;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.background,
              AppColors.background.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetroLineHud extends StatelessWidget {
  const _MetroLineHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final MetroLineController controller;
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
        _HudChip(label: 'SEVİYE', value: '${controller.level}', accent: accent),
        _HudChip(
          label: 'KALAN',
          value: '${controller.trainsLeft}',
          accent: accent,
        ),
      ],
    );
  }
}

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
          // Etiket zaten büyük harf yazılır: Dart'ın `toUpperCase`'i
          // Türkçe'yi bilmiyor, 'Seviye' → 'SEVIYE' oluyordu (noktalı İ
          // değil). Yerelleştirilmiş bir dönüşüm eklemek yerine metni
          // doğrudan doğru yazmak daha basit.
          Text(label, style: AppText.micro.copyWith(color: accent)),
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

/// Kalan hak: dolu jeton yanar, harcanan söner.
///
/// İlham alınan oyundaki su damlalarının metro karşılığı — jeton.
class _HeartRow extends StatelessWidget {
  const _HeartRow({required this.hearts});

  final int hearts;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kalan hak $hearts',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (var i = 0; i < metroLineHearts; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.confirmation_number_rounded,
                  size: 20,
                  color: i < hearts
                      ? AppColors.warning
                      : AppColors.textMuted.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tahtanın anahtarı — testler tahtayı bununla bulur.
const Key boardKey = ValueKey<String>('metro-line-board');

/// Oyun tahtası: eğik kameradan 3B depo platformu; dokunmaya ve basılı
/// tutmaya duyarlı. Dokunulan nokta perspektiften geri çevrilerek hangi
/// hücreye düştüğü bulunur (bkz. [MetroLineBoardProjection]).
class _MetroLineBoard extends StatelessWidget {
  const _MetroLineBoard({
    required this.controller,
    required this.accent,
    required this.departure,
    required this.blocked,
    required this.departingTrain,
    required this.departingSize,
    required this.blockedTrainId,
    required this.bump,
    required this.transition,
    required this.outgoingTrain,
    required this.outgoingSize,
    required this.onTapTrain,
    required this.onHint,
    required this.onTapEmpty,
  });

  final MetroLineController controller;
  final Color accent;
  final Animation<double> departure;
  final Animation<double> blocked;
  final MetroLineTrain? departingTrain;
  final int departingSize;
  final int? blockedTrainId;
  final _Bump? bump;
  final AnimationController transition;
  final MetroLineTrain? outgoingTrain;
  final int outgoingSize;
  final ValueChanged<int> onTapTrain;
  final VoidCallback onHint;
  final VoidCallback onTapEmpty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        void handleTap(Offset local) {
          if (transition.isAnimating) return;
          final projection = MetroLineBoardProjection(controller.size, size);
          final train = projection.trainAt(controller, local);
          if (train == null) {
            onTapEmpty();
          } else {
            onTapTrain(train.id);
          }
        }

        return SizedBox(
          key: boardKey,
          width: size.width,
          height: size.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => handleTap(details.localPosition),
            onLongPress: onHint,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                departure,
                blocked,
                transition,
              ]),
              builder: (context, _) {
                final phase = _LevelTransition(
                  t: transition.isAnimating ? transition.value : 1,
                  hasOutgoing: outgoingTrain != null,
                  trainCount: controller.trains.length,
                );
                final MetroLineBoardPainter painter;
                if (phase.showOldIsland) {
                  painter = MetroLineBoardPainter(
                    controller: controller,
                    accent: accent,
                    boardSize: outgoingSize,
                    trains: const <MetroLineTrain>[],
                    departingTrain: outgoingTrain,
                    departingSize: outgoingSize,
                    departureProgress: phase.departure,
                    blockedTrainId: null,
                    blockedGlow: 0,
                  );
                } else {
                  painter = MetroLineBoardPainter(
                    controller: controller,
                    accent: accent,
                    boardSize: controller.size,
                    trains: controller.trains,
                    hintTrainId: controller.hintTrainId,
                    drop: phase.active ? phase.drop : null,
                    departingTrain: departure.isAnimating
                        ? departingTrain
                        : null,
                    departingSize: departingSize,
                    departureProgress: departure.value,
                    blockedTrainId: blocked.isAnimating ? blockedTrainId : null,
                    blockedGlow: bump?.glow(blocked.value) ?? 0,
                    bumpTrainId: blocked.isAnimating ? bump?.trainId : null,
                    bumpOffset: bump?.offset(blocked.value) ?? 0,
                    hitTrainId: blocked.isAnimating ? bump?.hitTrainId : null,
                    hitShift: bump?.jolt(blocked.value) ?? Offset.zero,
                  );
                }
                return Opacity(
                  opacity: phase.opacity,
                  child: Transform.scale(
                    scale: phase.scale,
                    child: CustomPaint(
                      painter: painter,
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Önü kapalı trene dokunuş: ileri, çarp, geri. [t] 0 → 1.
///
/// | aralık     | olan                                              |
/// |------------|---------------------------------------------------|
/// | 0 – .42    | tren hızlanarak boşluğu geçer, burnu değer        |
/// | .42 – .52  | çarpma: tren hafif geri seker, karşıdaki sarsılır |
/// | .52 – 1    | tren yavaşça yerine döner                         |
@immutable
class _Bump {
  const _Bump({
    required this.trainId,
    required this.distance,
    required this.hitTrainId,
    required this.direction,
  });

  final int trainId;

  /// Burnun karşıdaki trene değdiği yol (hücre).
  final double distance;
  final int? hitTrainId;

  /// Trenin gidiş yönü (sütun, satır).
  final Offset direction;

  static const double impactAt = 0.42;
  static const double reboundEnd = 0.52;

  double _k(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// Trenin yol boyunca ilerlemesi (hücre).
  double offset(double t) {
    if (t < impactAt) {
      return distance * Curves.easeInQuad.transform(_k(t, 0, impactAt));
    }
    if (t < reboundEnd) {
      // Çarpınca biraz geri seker.
      return distance - 0.12 * math.sin(math.pi * _k(t, impactAt, reboundEnd));
    }
    return distance *
        (1 - Curves.easeInOutCubic.transform(_k(t, reboundEnd, 1)));
  }

  /// Çarpılan trenin sarsıntısı: gidiş yönünde kısa bir itilme.
  Offset jolt(double t) {
    if (t < impactAt || t > 0.62) return Offset.zero;
    final k = _k(t, impactAt, 0.62);
    return direction * (0.1 * math.sin(math.pi * k) * (1 - k * 0.5));
  }

  /// Kırmızı uyarı: çarpma anında yanar, dönüşte söner.
  double glow(double t) {
    if (t < impactAt) return 0;
    return 1 - _k(t, impactAt, 1);
  }
}

/// Bölüm geçişinin zaman çizelgesi; [t] 0 → 1 (1,7 sn).
///
/// | aralık      | olan                                         |
/// |-------------|----------------------------------------------|
/// | 0 – .24     | son tren eski adadan çıkar                   |
/// | .18 – .40   | eski ada hafifçe küçülüp saydamlaşır         |
/// | .40 – .62   | yeni ada küçükten sekerek büyür              |
/// | .48 – 1     | trenler sırayla havadan sekerek iner         |
///
/// Ekran hiç boş kalmaz: bir ada solarken öteki gelir, trenler ada
/// yerine oturmadan inmeye başlar.
@immutable
class _LevelTransition {
  const _LevelTransition({
    required this.t,
    required this.hasOutgoing,
    required this.trainCount,
  });

  final double t;
  final bool hasOutgoing;
  final int trainCount;

  static const double departEnd = 0.24;
  static const double outStart = 0.18;
  static const double inStart = 0.4;
  static const double inEnd = 0.62;
  static const double dropStart = 0.48;
  static const double dropDuration = 0.26;

  bool get active => t < 1;
  bool get showOldIsland => active && hasOutgoing && t < inStart;

  double _k(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  double get departure => _k(0, departEnd);

  double get scale {
    if (!active) return 1;
    if (showOldIsland) {
      return 1 - 0.1 * Curves.easeIn.transform(_k(outStart, inStart));
    }
    return 0.9 + 0.1 * Curves.easeOutBack.transform(_k(inStart, inEnd));
  }

  double get opacity {
    if (!active) return 1;
    if (showOldIsland) return 1 - _k(outStart, inStart);
    return (_k(inStart, inEnd) * 1.6).clamp(0.0, 1.0);
  }

  /// [index]. trenin yüksekliği ve görünürlüğü.
  (double, double) drop(int index) {
    final room = 1 - dropStart - dropDuration;
    final stagger = trainCount <= 1
        ? 0.0
        : math.min(0.045, room / (trainCount - 1));
    final local = _k(
      dropStart + index * stagger,
      dropStart + index * stagger + dropDuration,
    );
    if (local <= 0) return (0, 0);
    return ((1 - Curves.bounceOut.transform(local)) * 3.5, 1);
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
          if (animation.value == 0 || text == null) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: const Alignment(0, -0.55),
            child: Opacity(
              opacity: animation.value,
              child: Transform.scale(
                scale: 0.94 + 0.06 * animation.value,
                child: child,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.7)),
          ),
          child: Text(
            text ?? '',
            style: AppText.captionStrong.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}
