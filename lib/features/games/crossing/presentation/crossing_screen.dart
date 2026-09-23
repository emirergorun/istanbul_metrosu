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
import '../application/crossing_controller.dart';
import '../domain/crossing_state.dart';

class CrossingScreen extends StatefulWidget {
  const CrossingScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<CrossingScreen> createState() => _CrossingScreenState();
}

class _CrossingScreenState extends State<CrossingScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CrossingController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  bool _playedCrashSound = false;
  int _seenStationPulse = 0;
  int _seenMilestone = 0;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'CrossingControls');

  /// Kaç satırda bir "iyi gidiyorsun" bildirimi çıkar.
  static const int _milestoneRows = 10;

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
    final controller = CrossingController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, CrossingController.id),
      // Geçen trenlerin hatları uydurma değil: ağın kendi hatları, kendi
      // resmi renkleriyle.
      lines: scope.metro.lines(),
      random: scope.challengeRandomFor(widget.journey, CrossingController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      session: JourneyScope.sessionOf(context),
    );
    controller.reporter = scope.runReporter;
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

    final milestone = controller.rowsCrossed ~/ _milestoneRows;
    if (milestone != _seenMilestone) {
      _seenMilestone = milestone;
      if (milestone > 0) {
        _haptic(HapticFeedback.mediumImpact);
        _showBanner('${milestone * _milestoneRows}. SIRA GEÇİLDİ');
      }
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
    // Not: bilerek setState() yok — oyun saniyede ~60 kez haber veriyor.
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
    _bannerTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) _bannerAnimation.reverse();
    });
  }

  void _move(CrossingDirection direction) {
    final controller = _controller;
    if (controller == null || controller.status != GameStatus.playing) return;
    controller.move(direction);
    _haptic(HapticFeedback.selectionClick);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.space) {
      _move(CrossingDirection.forward);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _move(CrossingDirection.back);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _move(CrossingDirection.left);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _move(CrossingDirection.right);
    }
  }

  /// Sürüklemenin başladığı nokta; her yön verişten sonra sıfırlanır.
  Offset? _dragAnchor;

  void _handlePanStart(DragStartDetails details) {
    _dragAnchor = details.localPosition;
  }

  /// Parmak eşiği aşar aşmaz yön verir.
  ///
  /// Yolcu Topla'daki çözümün aynısı: `onPanEnd` beklemek, adımı parmağın
  /// kalkmasına kadar geciktiriyordu. Çapa her yön verişte yenileniyor, bu
  /// yüzden parmağı kaldırmadan iki hamle zincirlenebiliyor.
  void _handlePanUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final delta = details.localPosition - anchor;
    if (delta.distance < 16) return;
    _move(
      delta.dx.abs() > delta.dy.abs()
          ? (delta.dx > 0 ? CrossingDirection.right : CrossingDirection.left)
          : (delta.dy > 0 ? CrossingDirection.back : CrossingDirection.forward),
    );
    _dragAnchor = details.localPosition;
  }

  void _handlePanEnd(DragEndDetails details) => _dragAnchor = null;

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
                        _CrossingHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _CrossingPlayArea(
                            controller: controller,
                            accent: accent,
                            onTapUp: (_) => _move(CrossingDirection.forward),
                            onPanStart: _handlePanStart,
                            onPanUpdate: _handlePanUpdate,
                            onPanEnd: _handlePanEnd,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Dokun: bir adım ileri · Kaydır: yön ver',
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        JourneyStatusBar(
                          gameId: CrossingController.id,
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
    CrossingController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      journey: controller.journey,
      gameId: CrossingController.id,
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
        StatRow(label: 'Geçilen sıra', value: '${controller.rowsCrossed}'),
        StatRow(label: 'Geçilen ray', value: '${controller.tracksCrossed}'),
      ],
      gameOverTitle: 'Tren geçti',
      gameOverSubtitle: 'Raydan çıkamadan tren geldi.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _CrossingHud extends StatelessWidget {
  const _CrossingHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final CrossingController controller;
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
          label: 'Sıra',
          value: '${controller.rowsCrossed}',
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
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Oyun alanı.
///
/// Oranı sabit: [crossingColumns] sütun × [crossingVisibleRows] satır.
/// Kamera hep oyuncuyu takip ettiği için alanın yüksekliği kaç satır
/// gösterdiğini belirliyor — oran serbest bırakılsaydı uzun bir telefonda
/// oyuncu daha fazla ileriyi görüp aynı oyunu daha kolay oynardı.
class _CrossingPlayArea extends StatelessWidget {
  const _CrossingPlayArea({
    required this.controller,
    required this.accent,
    required this.onTapUp,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final CrossingController controller;
  final Color accent;
  final GestureTapUpCallback onTapUp;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: crossingColumns / crossingVisibleRows,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Dokunuş parmak kalkınca sayılır: aynı alanda kaydırma da var,
          // basma anında adım atılsaydı her kaydırma önce bir adım
          // attırırdı.
          onTapUp: onTapUp,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CrossingPainter(
                  controller: controller,
                  accent: accent,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sahnenin tamamı: peronlar, raylar, trenler ve yolcu.
///
/// Çizim dili uygulamanın geri kalanıyla aynı — blur yok, her ölçü hücre
/// boyuna oranlı, tren ortak [MetroTrainPainter] ile çiziliyor. Kamera
/// dik üstten bakıyor: çapraz bir görünüm hem bu dille çelişirdi hem de
/// oyuncunun hangi satırda durduğunu belirsizleştirirdi.
class _CrossingPainter extends CustomPainter {
  const _CrossingPainter({required this.controller, required this.accent});

  final CrossingController controller;
  final Color accent;

  /// Peron zemini — koyu nötr skalanın açık ucu.
  ///
  /// [AppColors.surfaceHigh]'dan bir tık açık: ray satırı ballast rengiyle
  /// neredeyse siyah, aradaki fark ilk bakışta okunmalı (simülatörde iki
  /// satır tipi birbirine karışıyordu).
  static const Color _platform = Color(0xFF3A414B);
  static const Color _platformAlt = Color(0xFF333942);

  /// Ray satırının balast zemini.
  static const Color _ballast = Color(0xFF15181C);

  /// Yolcunun teni. Uygulamada başka insan figürü yok; sıcak, nötr bir
  /// ton seçildi ki hat renklerinin hiçbiriyle karışmasın.
  static const Color _skin = Color(0xFFF2D6B4);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cell = size.width / crossingColumns;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.background);

    final camera = controller.cameraRow;
    // Satırın alt kenarının ekran y'si. Oyuncunun satırı ekranın altından
    // [crossingPlayerViewRow] hücre yukarıda durur.
    double bottomOf(num index) =>
        size.height - (index - camera + crossingPlayerViewRow) * cell;

    final rows = controller.rows;
    for (final row in rows) {
      final bottom = bottomOf(row.index);
      final rect = Rect.fromLTRB(0, bottom - cell, size.width, bottom);
      if (rect.bottom < -cell || rect.top > size.height + cell) continue;
      if (row.isTrack) {
        _paintTrack(canvas, rect, cell);
      } else {
        _paintPlatform(canvas, rect, cell, row.index);
      }
    }

    // Sarı güvenlik şeridi peronun ray tarafına çizilir; satırlar ayrı ayrı
    // çizilirken komşusunu bilemediği için ikinci geçiş.
    for (final row in rows) {
      if (row.isTrack) continue;
      final bottom = bottomOf(row.index);
      if (bottom < -cell || bottom - cell > size.height + cell) continue;
      final above = controller.rowAt(row.index + 1);
      final below = controller.rowAt(row.index - 1);
      if (above?.isTrack ?? false) {
        _paintSafetyStrip(canvas, size, bottom - cell, cell, fromTop: true);
      }
      if (below?.isTrack ?? false) {
        _paintSafetyStrip(canvas, size, bottom, cell, fromTop: false);
      }
    }

    for (final row in rows) {
      if (!row.isTrack) continue;
      final center = bottomOf(row.index) - cell / 2;
      if (center < -cell || center > size.height + cell) continue;
      for (final train in row.trains) {
        _paintTrain(canvas, train, row.toRight, center, cell);
      }
    }

    _paintPlayer(canvas, cell, bottomOf(controller.visualRow) - cell / 2);
  }

  void _paintPlatform(Canvas canvas, Rect rect, double cell, int index) {
    // Satırlar arası çok hafif ton farkı: zemin tek düze bir blok değil,
    // döşeme sırası gibi okunsun.
    canvas.drawRect(
      rect,
      Paint()..color = index.isEven ? _platform : _platformAlt,
    );
    // Döşeme derzi.
    canvas.drawLine(
      Offset(0, rect.top),
      Offset(rect.right, rect.top),
      Paint()
        ..color = AppColors.background.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
  }

  void _paintTrack(Canvas canvas, Rect rect, double cell) {
    canvas.drawRect(rect, Paint()..color = _ballast);

    // Traversler: ray boyunca eşit aralıklı koyu çubuklar.
    final tie = Paint()..color = AppColors.textMuted.withValues(alpha: 0.22);
    final tieWidth = cell * 0.12;
    for (var x = cell * 0.2; x < rect.width; x += cell * 0.55) {
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          rect.top + cell * 0.18,
          tieWidth,
          rect.height - cell * 0.36,
        ),
        tie,
      );
    }

    // İki ray. Ray Değiştir'deki çizgi diliyle aynı: ince, açık, sürekli.
    final rail = Paint()
      ..color = AppColors.outline
      ..strokeWidth = math.max(1.5, cell * 0.06)
      ..strokeCap = StrokeCap.round;
    final gauge = cell * 0.26;
    canvas.drawLine(
      Offset(0, rect.center.dy - gauge),
      Offset(rect.right, rect.center.dy - gauge),
      rail,
    );
    canvas.drawLine(
      Offset(0, rect.center.dy + gauge),
      Offset(rect.right, rect.center.dy + gauge),
      rail,
    );
  }

  /// Peronun ray tarafındaki sarı güvenlik şeridi.
  ///
  /// Gerçek peronlardaki hissedilebilir yüzey: burada da aynı işi görüyor,
  /// "buradan ötesi tehlikeli" diyen tek işaret.
  void _paintSafetyStrip(
    Canvas canvas,
    Size size,
    double edgeY,
    double cell, {
    required bool fromTop,
  }) {
    final height = cell * 0.12;
    final rect = Rect.fromLTWH(
      0,
      fromTop ? edgeY : edgeY - height,
      size.width,
      height,
    );
    canvas.drawRect(
      rect,
      Paint()..color = AppColors.warning.withValues(alpha: 0.85),
    );
    // Noktalı doku: düz sarı bir şerit bir "ilerleme çubuğu" gibi
    // okunuyordu; noktalar onu zemin döşemesine çeviriyor.
    final dot = Paint()..color = AppColors.background.withValues(alpha: 0.35);
    for (var x = cell * 0.12; x < size.width; x += cell * 0.22) {
      canvas.drawRect(
        Rect.fromLTWH(x, rect.top + height * 0.3, cell * 0.06, height * 0.4),
        dot,
      );
    }
  }

  void _paintTrain(
    Canvas canvas,
    CrossingTrain train,
    bool toRight,
    double centerY,
    double cell,
  ) {
    final height = cell * crossingTrainHeightCells;
    final width = MetroTrain.widthFor(height: height, wagons: train.cars);
    final left = train.x * cell;
    if (left > cell * crossingColumns + width || left + width < -width) return;

    canvas.save();
    if (toRight) {
      canvas.translate(left, centerY - height / 2);
    } else {
      // Ortak tren sağa bakarak çiziliyor; sola giden tren aynalanıyor ki
      // burnu gittiği yöne dönük olsun.
      canvas.translate(left + width, centerY - height / 2);
      canvas.scale(-1, 1);
    }
    MetroTrainPainter(
      color: train.line.color,
      wagons: train.cars,
    ).paint(canvas, Size(width, height));
    canvas.restore();

    _paintLinePlate(
      canvas,
      label: train.line.id,
      center: Offset(left + width / 2, centerY),
      trainHeight: height,
      trainWidth: width,
    );
  }

  /// Trenin üzerindeki hat kodu levhası.
  ///
  /// Gövde zaten hattın resmi renginde; levha koyu ve yazı beyaz, çünkü on
  /// hattın rengi sarıdan mora uzanıyor ve tek bir yazı rengi hepsinin
  /// üzerinde okunamaz. Koyu levha + beyaz yazı gerçek hat tabelalarının
  /// da dili.
  void _paintLinePlate(
    Canvas canvas, {
    required String label,
    required Offset center,
    required double trainHeight,
    required double trainWidth,
  }) {
    final padding = trainHeight * 0.10;
    var fontSize = trainHeight * 0.34;
    TextPainter layout(double size) => TextPainter(
      text: TextSpan(
        text: label,
        // Tuval üzerindeki metin tema fontunu miras almaz; aile
        // AppText'ten geliyor (bkz. AppText.lead).
        style: AppText.lead.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var painter = layout(fontSize);
    // Levha trenin yarısından fazlasını kaplamamalı: ilk denemede gövdeyi
    // tamamen örtüyordu ve tren bir rozete dönüşmüştü.
    final maxWidth = trainWidth * 0.52;
    if (painter.width + padding * 2 > maxWidth) {
      fontSize *= (maxWidth - padding * 2) / painter.width;
      painter = layout(fontSize);
    }

    final rect = Rect.fromCenter(
      center: center,
      width: painter.width + padding * 2,
      height: painter.height + padding * 0.4,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height * 0.32),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = AppColors.background.withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, trainHeight * 0.03)
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  /// Yolcu figürü.
  ///
  /// Uygulamadaki "yolcu" dilinin büyütülmüş hâli (bkz. Yolcu Topla'nın
  /// yolcu işareti): daire baş, omuz yayı, yuvarlatılmış gövde ve ince koyu
  /// kontur. Paltosu yolculuğun hat renginde — oyuncu hangi hatta seyahat
  /// ettiğini üstünde taşıyor.
  ///
  /// Zıplama dik üstten bakan bir kamerada yükseklik kazandırmıyor; his
  /// figürün hafifçe büyüyüp küçülmesi ve altındaki gölgenin daralmasıyla
  /// veriliyor.
  void _paintPlayer(Canvas canvas, double cell, double centerY) {
    final progress = controller.hopProgress;
    final lift = math.sin(math.pi * progress);
    final center = Offset((controller.visualColumn + 0.5) * cell, centerY);
    final scale = 1 + 0.16 * lift;

    // Gölge: zıplarken küçülür ve soluklaşır.
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, cell * 0.24),
        width: cell * (0.46 - 0.12 * lift),
        height: cell * (0.16 - 0.04 * lift),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.34 - 0.12 * lift),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, cell * 0.045)
      ..color = AppColors.background.withValues(alpha: 0.7);

    // Gövde: omuzlar yukarıda geniş, etek aşağıda dar.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, cell * 0.10),
        width: cell * 0.44,
        height: cell * 0.36,
      ),
      Radius.circular(cell * 0.13),
    );
    canvas.drawRRect(body, Paint()..color = accent);
    canvas.drawRRect(body, outline);

    // Baktığı yön: baş o yöne doğru küçük bir pay kayar.
    final facing = controller.facing.delta;
    final head = Offset(
      facing.x * cell * 0.04,
      -cell * 0.14 - facing.y * cell * 0.03,
    );
    canvas.drawCircle(head, cell * 0.17, Paint()..color = _skin);
    canvas.drawCircle(head, cell * 0.17, outline);

    // Saç/başlık: yüzün arkasını kapatan koyu bir yay, figüre yön verir.
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: cell * 0.17),
      math.pi * (facing.y >= 0 ? 1.0 : 0.0),
      math.pi,
      true,
      Paint()..color = AppColors.brandNavyDeep.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrossingPainter oldDelegate) => true;
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
