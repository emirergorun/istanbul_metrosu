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

  MetroLineTrain? _departingTrain;
  int _departingSize = metroLineMinSize;
  int _departingLevel = 1;
  int? _blockedTrainId;

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
    final controller = MetroLineController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, MetroLineController.id),
      random: scope.challengeRandomFor(
        widget.journey,
        MetroLineController.id,
      ),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      session: JourneyScope.sessionOf(context),
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
    _blocked.dispose();
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

  void _tapTrain(int trainId) {
    final controller = _controller;
    if (controller == null) return;

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
          }
        }
      case MetroLineTapResult.blocked:
        _haptic(HapticFeedback.mediumImpact);
        _sound(GameSound.invalid);
        setState(() => _blockedTrainId = trainId);
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
                // Tahtanın dışında kalan alan: düz siyah yerine metro sahnesi.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MetroLineBackdrop(accent: accent),
                  ),
                ),
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
                        _MetroLineHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.sm),
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
                            onTapTrain: _tapTrain,
                            onHint: controller.requestHint,
                            onTapEmpty: controller.clearHint,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Dokun: önü açık treni çıkar · Basılı tut: ipucu',
                          textAlign: TextAlign.center,
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
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
        StatRow(label: 'Boşaltılan depo', value: '${controller.completedLevels}'),
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
        _HudChip(
          label: 'SEVİYE',
          value: '${controller.level}',
          accent: accent,
        ),
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

/// Oyun tahtası: kare, dokunmaya ve basılı tutmaya duyarlı.
class _MetroLineBoard extends StatelessWidget {
  const _MetroLineBoard({
    required this.controller,
    required this.accent,
    required this.departure,
    required this.blocked,
    required this.departingTrain,
    required this.departingSize,
    required this.blockedTrainId,
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
  final ValueChanged<int> onTapTrain;
  final VoidCallback onHint;
  final VoidCallback onTapEmpty;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final n = controller.size;
          final cell = side / n;

          void handleTap(Offset local) {
            final col = (local.dx / cell).floor().clamp(0, n - 1);
            final row = (local.dy / cell).floor().clamp(0, n - 1);
            final train = controller.trainAt(math.Point<int>(col, row));
            if (train == null) {
              onTapEmpty();
            } else {
              onTapTrain(train.id);
            }
          }

          return SizedBox.square(
            key: boardKey,
            dimension: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => handleTap(details.localPosition),
              onLongPress: onHint,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.outline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  child: AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[
                      departure,
                      blocked,
                    ]),
                    builder: (context, _) => CustomPaint(
                      painter: _MetroLinePainter(
                        controller: controller,
                        accent: accent,
                        departingTrain: departure.isAnimating
                            ? departingTrain
                            : null,
                        departingSize: departingSize,
                        departureProgress: departure.value,
                        blockedTrainId: blocked.isAnimating
                            ? blockedTrainId
                            : null,
                        blockedProgress: blocked.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// İstanbul hat renkleri — karolar ve trenler bunlarla çizilir.
const List<Color> _lineColors = <Color>[
  Color(0xFFE30613), // M1 kırmızı
  Color(0xFF009A44), // M2 yeşil
  Color(0xFF00AEEF), // M3 mavi
  Color(0xFFE6007E), // M4 pembe
  Color(0xFF6A2C91), // M5 mor
  Color(0xFFF7A800), // M6 turuncu
];

class _MetroLinePainter extends CustomPainter {
  const _MetroLinePainter({
    required this.controller,
    required this.accent,
    required this.departingTrain,
    required this.departingSize,
    required this.departureProgress,
    required this.blockedTrainId,
    required this.blockedProgress,
  });

  final MetroLineController controller;
  final Color accent;
  final MetroLineTrain? departingTrain;
  final int departingSize;
  final double departureProgress;
  final int? blockedTrainId;
  final double blockedProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = controller.size;
    final cell = size.width / n;

    _paintDepot(canvas, size, cell, n);

    for (final train in controller.trains) {
      _paintTrain(
        canvas,
        train: train,
        boardSize: n,
        cell: cell,
        offset: 0,
        hinted: train.id == controller.hintTrainId,
        blockedGlow: train.id == blockedTrainId ? 1 - blockedProgress : 0,
      );
    }

    final leaving = departingTrain;
    if (leaving != null) {
      final route = _route(leaving, departingSize, cell);
      final bodyLength = (leaving.carCount - 1) * cell;
      final travel = _polylineLength(route) - bodyLength;
      _paintTrain(
        canvas,
        train: leaving,
        boardSize: departingSize,
        cell: cell,
        offset: Curves.easeInCubic.transform(departureProgress) * travel,
        hinted: false,
        blockedGlow: 0,
      );
    }
  }

  /// Depo zemini: peron betonu, üzerinde iki yönde uzanan raylar ve
  /// traversler.
  ///
  /// Önce düz bir zemin ve ince ızgara çizgileriydi; milimetrik kâğıt gibi
  /// duruyordu. Depo görüntüsünü veren şey ızgara değil **ray**: her satır
  /// ve sütunda iki paralel ray, aralarında traversler.
  void _paintDepot(Canvas canvas, Size size, double cell, int n) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF2A3340), Color(0xFF1A212B)],
        ).createShader(rect),
    );

    // Peron plakaları: hücre hücre hafif açık kareler.
    final slab = Paint()..color = Colors.white.withValues(alpha: 0.035);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if ((row + col).isOdd) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              col * cell + cell * 0.04,
              row * cell + cell * 0.04,
              cell * 0.92,
              cell * 0.92,
            ),
            Radius.circular(cell * 0.10),
          ),
          slab,
        );
      }
    }

    final tie = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = math.max(1, cell * 0.05)
      ..strokeCap = StrokeCap.round;
    final rail = Paint()
      ..color = accent.withValues(alpha: 0.13)
      ..strokeWidth = math.max(1, cell * 0.035)
      ..strokeCap = StrokeCap.round;

    final gauge = cell * 0.19;
    for (var i = 0; i < n; i++) {
      final mid = (i + 0.5) * cell;

      for (var t = 0; t < n * 2; t++) {
        final x = (t + 0.5) * cell / 2;
        canvas.drawLine(Offset(x, mid - gauge), Offset(x, mid + gauge), tie);
      }
      canvas.drawLine(
        Offset(0, mid - gauge),
        Offset(size.width, mid - gauge),
        rail,
      );
      canvas.drawLine(
        Offset(0, mid + gauge),
        Offset(size.width, mid + gauge),
        rail,
      );

      for (var t = 0; t < n * 2; t++) {
        final y = (t + 0.5) * cell / 2;
        canvas.drawLine(Offset(mid - gauge, y), Offset(mid + gauge, y), tie);
      }
      canvas.drawLine(
        Offset(mid - gauge, 0),
        Offset(mid - gauge, size.height),
        rail,
      );
      canvas.drawLine(
        Offset(mid + gauge, 0),
        Offset(mid + gauge, size.height),
        rail,
      );
    }
  }

  /// Trenin izleyeceği yol: kuyruktan başa, oradan da tahtanın dışına.
  ///
  /// Çizim bu çoklu çizgi üzerinde **yay uzunluğuyla** yürüyor. Tek bir
  /// öteleme yetmezdi: tren çıkarken vagonlar başın döndüğü köşelerden
  /// geçmeli, gövdeyi blok hâlinde kaydırmak treni duvarın içinden
  /// geçiriyormuş gibi gösterirdi.
  List<Offset> _route(MetroLineTrain train, int boardSize, double cell) {
    Offset center(math.Point<int> p) =>
        Offset((p.x + 0.5) * cell, (p.y + 0.5) * cell);

    final points = <Offset>[for (final c in train.cells.reversed) center(c)];

    final step = train.direction.delta;
    final head = train.head;
    final corridor = train.corridor(boardSize).length;
    for (var i = 1; i <= corridor + train.carCount + 1; i++) {
      points.add(
        center(math.Point<int>(head.x + step.x * i, head.y + step.y * i)),
      );
    }
    return points;
  }

  double _polylineLength(List<Offset> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    return total;
  }

  /// Çoklu çizginin verilen yay aralığına düşen parçası.
  List<Offset> _slice(List<Offset> points, double from, double to) {
    final out = <Offset>[];
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final len = (b - a).distance;
      if (len <= 0) continue;
      final segStart = walked;
      final segEnd = walked + len;

      if (segEnd >= from && segStart <= to) {
        final enter = math.max(from, segStart);
        final exit = math.min(to, segEnd);
        final p0 = Offset.lerp(a, b, (enter - segStart) / len)!;
        final p1 = Offset.lerp(a, b, (exit - segStart) / len)!;
        if (out.isEmpty) out.add(p0);
        out.add(p1);
      }
      walked = segEnd;
    }
    return out;
  }

  /// Yolun verilen yay uzunluğundaki noktası ve oradaki yön birimi.
  (Offset, Offset) _poseAt(List<Offset> points, double distance) {
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final len = (b - a).distance;
      if (len <= 0) continue;
      if (distance <= walked + len) {
        final t = ((distance - walked) / len).clamp(0.0, 1.0);
        return (Offset.lerp(a, b, t)!, (b - a) / len);
      }
      walked += len;
    }
    final a = points[points.length - 2];
    final b = points.last;
    final len = (b - a).distance;
    return (b, len > 0 ? (b - a) / len : const Offset(1, 0));
  }

  void _paintTrain(
    Canvas canvas, {
    required MetroLineTrain train,
    required int boardSize,
    required double cell,
    required double offset,
    required bool hinted,
    required double blockedGlow,
  }) {
    final route = _route(train, boardSize, cell);
    final bodyLength = (train.carCount - 1) * cell;
    final color = _lineColors[train.lineIndex % _lineColors.length];

    // İpucu ve uyarı parıltısı: trenin izlediği yol boyunca geniş bir hale.
    if (hinted || blockedGlow > 0) {
      final points = _slice(route, offset, offset + bodyLength);
      if (points.length >= 2) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = hinted
                ? AppColors.warning.withValues(alpha: 0.5)
                : AppColors.danger.withValues(alpha: 0.8 * blockedGlow)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.94
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Vagonlar kuyruktan başa çizilir ki lokomotif en üstte kalsın.
    for (var i = train.carCount - 1; i >= 0; i--) {
      final at = offset + bodyLength - i * cell;
      if (at < 0) continue;
      final (position, forward) = _poseAt(route, at);
      _paintWagon(
        canvas,
        position: position,
        forward: forward,
        cell: cell,
        color: color,
        isHead: i == 0,
        isTail: i == train.carCount - 1,
      );
    }
  }

  /// Tek bir vagon: yukarıdan görünen bir metro aracı.
  ///
  /// Önce tren tek parça kalın bir çizgiydi ve oyuncu haklı olarak
  /// "metroları değil düz çizgileri ayırıyorum" dedi. Sonra sade bir gövde
  /// oldu; bu sürüm gerçekçiliği artırıyor.
  ///
  /// Gerçek bir metro aracına yukarıdan bakınca görülen sıra şudur, dıştan
  /// içe: gölge, gövde, omuz hattında cam bandı, üstte açık renk çatı
  /// paneli, çatının ortasında klima/pantograf kutusu, gövdeyi bölen kapı
  /// derzleri. Lokomotifte ayrıca ön cam, iki far ve gidiş oku var. Her
  /// ölçü hücre boyuna oranlı: 10x10 tahtada hücre ~34 px kalıyor,
  /// ayrıntılar orada da dağılmasın diye kalınlıkların altına taban kondu.
  void _paintWagon(
    Canvas canvas, {
    required Offset position,
    required Offset forward,
    required double cell,
    required Color color,
    required bool isHead,
    required bool isTail,
  }) {
    final length = cell * 0.92;
    final width = cell * 0.66;
    final nose = isHead ? width * 0.44 : cell * 0.09;
    final back = isTail ? width * 0.34 : cell * 0.09;

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(math.atan2(forward.dy, forward.dx));

    Rect centered(double w, double h, {double dx = 0}) =>
        Rect.fromCenter(center: Offset(dx, 0), width: w, height: h);

    final body = RRect.fromRectAndCorners(
      centered(length, width),
      topLeft: Radius.circular(back),
      bottomLeft: Radius.circular(back),
      topRight: Radius.circular(nose),
      bottomRight: Radius.circular(nose),
    );

    // Zemine düşen gölge: tren tahtanın üstünde dursun, içine gömülmesin.
    canvas.save();
    canvas.translate(0, width * 0.10);
    canvas.drawRRect(
      body.inflate(cell * 0.01),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.06),
    );
    canvas.restore();

    // Tampon körüğü: vagonlar arasındaki koyu bağlantı.
    if (!isHead) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          centered(cell - length + 3, width * 0.40, dx: length * 0.5),
          Radius.circular(width * 0.10),
        ),
        Paint()..color = const Color(0xFF10161D),
      );
    }

    // Gövde: koyu kontur + hat rengi.
    canvas.drawRRect(body, Paint()..color = const Color(0xFF0B1118));
    canvas.drawRRect(body.deflate(cell * 0.030), Paint()..color = color);

    // Omuz hattı cam bandı: iki yanda boydan boya koyu şerit.
    final glass = Paint()..color = const Color(0xFF16202B).withValues(alpha: 0.92);
    for (final sign in <double>[-1, 1]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-length * 0.04, sign * width * 0.315),
            width: length * 0.72,
            height: width * 0.17,
          ),
          Radius.circular(width * 0.08),
        ),
        glass,
      );
      // Camlardan sızan ışık.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-length * 0.04, sign * width * 0.315),
            width: length * 0.62,
            height: width * 0.09,
          ),
          Radius.circular(width * 0.05),
        ),
        Paint()..color = const Color(0xFFFFE6B4).withValues(alpha: 0.72),
      );
    }

    // Çatı paneli: gövdeden açık, hafif gümüş.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        centered(length * 0.80, width * 0.34),
        Radius.circular(width * 0.13),
      ),
      Paint()..color = Color.lerp(color, Colors.white, 0.42)!,
    );

    // Çatı ekipmanı: klima kutusu — gövdeyi düz bir lekeden çıkarır.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        centered(length * 0.30, width * 0.17, dx: -length * 0.10),
        Radius.circular(width * 0.05),
      ),
      Paint()..color = const Color(0xFF2B3440).withValues(alpha: 0.8),
    );

    // Kapı derzleri: gövdeyi bölen ince koyu çizgiler.
    final seam = Paint()
      ..color = const Color(0xFF0B1118).withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, cell * 0.022);
    for (final dx in <double>[-0.26, 0.06]) {
      canvas.drawLine(
        Offset(length * dx, -width * 0.42),
        Offset(length * dx, width * 0.42),
        seam,
      );
    }

    if (isHead) {
      // Ön cam: koyu, üstünde ince bir yansıma.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          centered(length * 0.19, width * 0.56, dx: length * 0.27),
          Radius.circular(width * 0.15),
        ),
        Paint()..color = const Color(0xFF16202B),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          centered(length * 0.07, width * 0.40, dx: length * 0.235),
          Radius.circular(width * 0.08),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.28),
      );

      // Farlar: burnun iki ucunda sıcak beyaz.
      for (final sign in <double>[-1, 1]) {
        canvas.drawCircle(
          Offset(length * 0.40, sign * width * 0.26),
          math.max(1.2, width * 0.075),
          Paint()..color = const Color(0xFFFFF2CC),
        );
      }

      // Gidiş yönü oku — çatının üstünde, her zaman ileri bakar.
      final arrow = Path()
        ..moveTo(-length * 0.04, -width * 0.17)
        ..lineTo(-length * 0.04 + width * 0.22, 0)
        ..lineTo(-length * 0.04, width * 0.17)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..color = const Color(0xFF0B1118).withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, cell * 0.055)
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(arrow, Paint()..color = Colors.white);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MetroLinePainter oldDelegate) => true;
}

/// Oyun ekranının arkası: gün batımında bir peron sahnesi.
///
/// Referans, kullanıcının gönderdiği bir peron tablosuydu: solda camları
/// yanan bir tren, sağda tonozlu tavan boyunca uzayan floresan şeritler,
/// altta sarı emniyet çizgisi ve hissedilebilir yüzey, arkada turuncu bir
/// gökyüzü. Görselin kendisi kullanılmadı — imzalı bir eser ve elimizde
/// lisanslı bir dosya yok; sahne aynı kompozisyonla **çizildi**.
///
/// Her şey tek bir kaçış noktasına (sağ-orta) akıyor: tavan kaburgaları,
/// lambalar, peron karoları ve trenin gövdesi. Perspektifi taşıyan da bu.
///
/// TODO(GOR): Lisanslı bir illüstrasyon gelirse `assets/images/` altına
/// konup burası `Image.asset` ile değiştirilebilir.
class _MetroLineBackdrop extends CustomPainter {
  const _MetroLineBackdrop({required this.accent});

  final Color accent;

  /// Kaçış noktası — tüm perspektif çizgileri buraya gider.
  static const Offset _vanishing = Offset(0.86, 0.46);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Offset(
      size.width * _vanishing.dx,
      size.height * _vanishing.dy,
    );

    _paintSky(canvas, size);
    _paintClouds(canvas, size);
    _paintPlatform(canvas, size, vp);
    _paintVault(canvas, size, vp);
    _paintTrain(canvas, size, vp);
    _paintScrim(canvas, size);
  }

  /// Gün batımı: tepede lacivert, ortada şeftali ve altın, altta peronun
  /// karanlığı.
  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF1B3A63),
            Color(0xFF3E5E86),
            Color(0xFFC77A62),
            Color(0xFFE0A257),
            Color(0xFF241E22),
            Color(0xFF0C1016),
          ],
          stops: <double>[0, 0.16, 0.30, 0.40, 0.56, 1],
        ).createShader(rect),
    );
  }

  /// Şeftali rengi ince bulut şeritleri.
  void _paintClouds(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE98A76).withValues(alpha: 0.55);
    for (final c in <List<double>>[
      <double>[0.30, 0.11, 0.20, 0.012],
      <double>[0.46, 0.155, 0.13, 0.009],
      <double>[0.22, 0.195, 0.16, 0.010],
      <double>[0.52, 0.225, 0.10, 0.008],
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * c[0], size.height * c[1]),
            width: size.width * c[2],
            height: size.height * c[3],
          ),
          Radius.circular(size.height * c[3]),
        ),
        paint,
      );
    }
  }

  /// Peron zemini: kaçış noktasına akan karo çizgileri, sarı emniyet
  /// şeridi ve üzerindeki hissedilebilir noktalar.
  void _paintPlatform(Canvas canvas, Size size, Offset vp) {
    final floorTop = size.height * 0.52;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, floorTop, size.width, size.height),
    );

    canvas.drawRect(
      Rect.fromLTRB(0, floorTop, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[Color(0xFF6B5B52), Color(0xFF2A2320)],
        ).createShader(Rect.fromLTRB(0, floorTop, size.width, size.height)),
    );

    // Karo derzleri: alt kenardan kaçış noktasına giden ışınlar.
    final seam = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2;
    for (var i = -6; i <= 14; i++) {
      canvas.drawLine(Offset(size.width * i / 8, size.height), vp, seam);
    }
    // Enine derzler: kaçış noktasına yaklaştıkça sıklaşır.
    for (var i = 1; i <= 9; i++) {
      final t = math.pow(i / 10, 2.1).toDouble();
      final y = size.height - (size.height - vp.dy) * (1 - t);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), seam);
    }

    // Sarı emniyet şeridi ve hissedilebilir noktalar.
    final bandNear = size.height * 0.94;
    final bandFar = vp.dy + (size.height - vp.dy) * 0.12;
    final band = Path()
      ..moveTo(0, bandNear)
      ..lineTo(size.width * 0.34, bandNear)
      ..lineTo(vp.dx, vp.dy + 2)
      ..lineTo(vp.dx, bandFar)
      ..close();
    canvas.drawPath(
      band,
      Paint()..color = const Color(0xFFF2C14E).withValues(alpha: 0.55),
    );

    final stud = Paint()..color = const Color(0xFF1A1512).withValues(alpha: 0.45);
    for (var row = 1; row <= 7; row++) {
      final t = math.pow(row / 8, 2.0).toDouble();
      final y = size.height - (size.height - bandFar) * (1 - t) * 0.92;
      final r = math.max(1.0, size.width * 0.007 * (1 - t) + 1);
      for (var col = 0; col < 10; col++) {
        final x = size.width * (col + 0.5) / 10 * (1 - t) + vp.dx * t;
        canvas.drawCircle(Offset(x, y), r, stud);
      }
    }
    canvas.restore();
  }

  /// Tonozlu tavan: kaçış noktasına daralan kaburgalar, aralarında krem
  /// panolar ve boyunca uzanan floresan şeritler.
  void _paintVault(Canvas canvas, Size size, Offset vp) {
    final ceiling = size.height * 0.40;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, ceiling));

    // Tonoz gövdesi: sağ üstten kaçış noktasına akan bir yelpaze.
    for (var i = 8; i >= 0; i--) {
      final t = i / 8;
      final left = size.width * (0.30 + 0.56 * (1 - t));
      final top = -size.height * 0.02 + ceiling * 0.92 * t * 0.45;
      final panel = Path()
        ..moveTo(size.width * 1.02, top)
        ..quadraticBezierTo(
          left + (vp.dx - left) * 0.35,
          top + (vp.dy - top) * 0.10,
          vp.dx,
          vp.dy,
        )
        ..lineTo(size.width * 1.02, vp.dy)
        ..close();
      canvas.drawPath(
        panel,
        Paint()
          ..color = (i.isEven
                  ? const Color(0xFFE8E0CE)
                  : const Color(0xFF2E6B62))
              .withValues(alpha: 0.13),
      );
    }

    // Kaburgalar.
    final rib = Paint()
      ..color = const Color(0xFF1E4F49).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.width * 0.006)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 7; i++) {
      final t = math.pow(i / 7, 1.7).toDouble();
      final startY = -size.height * 0.03 + ceiling * 1.05 * t;
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 1.02, startY)
          ..quadraticBezierTo(
            size.width * (0.72 - 0.12 * t),
            startY + (vp.dy - startY) * 0.22,
            vp.dx,
            vp.dy - size.height * 0.004,
          ),
        rib,
      );
    }

    // Floresan şeritler: kaçış noktasına doğru küçülen parlak kapsüller.
    for (var i = 0; i < 7; i++) {
      final t = math.pow(i / 7, 1.55).toDouble();
      final center = Offset(
        size.width * (0.94 - 0.10 * t),
        size.height * (0.035 + 0.40 * t),
      );
      final w = size.width * (0.22 * (1 - t) + 0.02);
      final h = math.max(2.0, size.height * 0.011 * (1 - t) + 1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: h * 3.2),
          Radius.circular(h * 1.6),
        ),
        Paint()
          ..color = const Color(0xFFFFE9B8).withValues(alpha: 0.13)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 1.6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: h),
          Radius.circular(h / 2),
        ),
        Paint()..color = const Color(0xFFFFF6DF).withValues(alpha: 0.78),
      );
    }
    canvas.restore();
  }

  /// Soldaki tren: perspektifte daralan gövde, camları yanıyor.
  void _paintTrain(Canvas canvas, Size size, Offset vp) {
    final nearTop = size.height * 0.235;
    final nearBottom = size.height * 0.66;
    final farTop = vp.dy - size.height * 0.035;
    final farBottom = vp.dy + size.height * 0.045;
    final farX = size.width * 0.70;

    final body = Path()
      ..moveTo(-size.width * 0.04, nearTop)
      ..lineTo(farX, farTop)
      ..lineTo(farX, farBottom)
      ..lineTo(-size.width * 0.04, nearBottom)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF8E2530).withValues(alpha: 0.72));

    // Çatı bandı.
    final roof = Path()
      ..moveTo(-size.width * 0.04, nearTop)
      ..lineTo(farX, farTop)
      ..lineTo(farX, farTop + size.height * 0.012)
      ..lineTo(-size.width * 0.04, nearTop + size.height * 0.05)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFFD8DCE0).withValues(alpha: 0.5));

    // Camlar: perspektifte küçülen, içi sıcak ışıkla dolu dikdörtgenler.
    for (var i = 0; i < 9; i++) {
      final t0 = math.pow(i / 9, 1.35).toDouble();
      final t1 = math.pow((i + 0.62) / 9, 1.35).toDouble();
      double lerp(double a, double b, double t) => a + (b - a) * t;

      final x0 = lerp(-size.width * 0.04, farX, t0);
      final x1 = lerp(-size.width * 0.04, farX, t1);
      final top0 = lerp(nearTop + size.height * 0.062, farTop + size.height * 0.015, t0);
      final top1 = lerp(nearTop + size.height * 0.062, farTop + size.height * 0.015, t1);
      final bot0 = lerp(nearTop + size.height * 0.165, farTop + size.height * 0.032, t0);
      final bot1 = lerp(nearTop + size.height * 0.165, farTop + size.height * 0.032, t1);

      canvas.drawPath(
        Path()
          ..moveTo(x0, top0)
          ..lineTo(x1, top1)
          ..lineTo(x1, bot1)
          ..lineTo(x0, bot0)
          ..close(),
        Paint()..color = const Color(0xFFFFD79A).withValues(alpha: 0.62),
      );
    }

    // Kapılar: gövdeyi bölen koyu dikey şeritler.
    final door = Paint()
      ..color = const Color(0xFF3A1216).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.width * 0.008);
    for (final t in <double>[0.14, 0.38, 0.58, 0.73]) {
      final x = -size.width * 0.04 + (farX + size.width * 0.04) * t;
      final top = nearTop + (farTop - nearTop) * t;
      final bot = nearBottom + (farBottom - nearBottom) * t;
      canvas.drawLine(Offset(x, top), Offset(x, bot), door);
    }
  }

  /// Sahnenin üstüne karartma: oyun tahtası ve yazılar okunur kalmalı.
  ///
  /// Sahne kendi başına doğru renklerde; sorun kontrast. Ortada daha koyu
  /// bir perde var çünkü tahta tam oraya oturuyor.
  void _paintScrim(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.background.withValues(alpha: 0.62),
            AppColors.background.withValues(alpha: 0.80),
            AppColors.background.withValues(alpha: 0.86),
            AppColors.background.withValues(alpha: 0.72),
          ],
          stops: const <double>[0, 0.34, 0.62, 1],
        ).createShader(rect),
    );

    // Hat rengiyle çok hafif bir tonlama: ekran yolculuğun hattına ait
    // hissetsin.
    canvas.drawRect(rect, Paint()..color = accent.withValues(alpha: 0.05));
  }

  @override
  bool shouldRepaint(_MetroLineBackdrop oldDelegate) =>
      oldDelegate.accent != accent;
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
