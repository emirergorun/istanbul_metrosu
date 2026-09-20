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
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/journey_breakdown.dart';
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
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Yolculuk ortak: süren bir yolculuk varsa oyun onun içine girer —
      // puan, kalan süre ve geçilen duraklar oradan devam eder.
      session: JourneyScope.sessionOf(context),
    );
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

    if (outcome.merges > 0) {
      _haptic(HapticFeedback.mediumImpact);
      _sound(outcome.merges >= 2 ? GameSound.combo : GameSound.clear);
    } else {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.place);
    }

    if (outcome.reachedTarget) {
      _haptic(HapticFeedback.heavyImpact);
      _showBanner('M11! Tüm hatları birleştirdin');
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
              // Düz koyu zemin yerine hafif bir metro haritası dokusu:
              // kıvrılan hatlar, aktarma noktaları ve yumuşak bir ışık.
              Positioned.fill(
                child: CustomPaint(painter: _MergeBackdrop(accent: accent)),
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
                      // Yön tuşları kaldırıldı: tahtada kaydırma ve
                      // klavyede ok tuşları zaten çalışıyor, ekrandaki
                      // dörtlü ped yalnızca yer kaplıyordu.
                      const SizedBox(height: AppSpacing.sm),
                      JourneyStatusBar(
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
    MetroMergeController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    return ResultOverlay(
      isArrival: controller.status == GameStatus.arrived,
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
        StatRow(label: 'Birleşme', value: '${controller.totalMerges}'),
        StatRow(label: 'En yüksek hat', value: controller.highestLabel),
      ],
      gameOverTitle: 'Hat kilitlendi',
      gameOverSubtitle: 'Tahta doldu ve birleşebilecek tren kalmadı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
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
    return JourneyHud(
      run: controller,
      accent: accent,
      onPause: onPause,
      gameScore: controller.scoreThisGame,
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
                                  dense: false,
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
        // Zemin, hat renginin koyulaştırılmış hâli: karo hattın kimliğini
        // taşır ama üstündeki tren ve etiket okunur kalır.
        color: current == null
            ? AppColors.emptyCell
            : Color.lerp(_metroLineColor(current), const Color(0xFF0B1118), 0.7),
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        border: current == null
            ? null
            : Border.all(
                color: current.rank == metroMergeMaxRank
                    ? Colors.white.withValues(alpha: 0.9)
                    : _metroLineColor(current).withValues(alpha: 0.75),
                width: current.rank == metroMergeMaxRank ? 2 : 1.5,
              ),
      ),
      child: current == null ? null : _TileContent(tile: current, dense: dense),
    );
  }
}

/// Karonun içi: hattın rengiyle çizilmiş küçük bir metro treni ve üstünde
/// hat etiketi.
///
/// Tren **karenin içinde** kalır; hücre geometrisi hiç değişmez. Oyun
/// mantığı ızgara hücrelerine dayandığı için bu şart: karo bir tren
/// şeklinde olsaydı komşuluk ve kaydırma okuması bozulurdu.
///
/// Zemin, hattın renginin koyulaştırılmış hâli; tren ise tam güçte hat
/// rengi. Böylece her hat kendi rengini taşırken trenin beyaz konturu ve
/// pencereleri her renkte okunur kalıyor (tren gövdesini beyaz yapmak
/// işe yaramaz: pencereler de beyaz çizildiği için tren düz bir lekeye
/// dönüşüyordu).
class _TileContent extends StatelessWidget {
  const _TileContent({required this.tile, required this.dense});

  final MetroTile tile;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = _metroLineColor(tile);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        // İki vagonluk tren, karenin ~%68'i kadar yer kaplar.
        final trainHeight = side * 0.29;
        return Padding(
          padding: EdgeInsets.all(side * 0.06),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tile.lineLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: side * 0.27,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Color.lerp(color, Colors.white, 0.55),
                  ),
                ),
              ),
              SizedBox(height: side * 0.08),
              MetroTrain(color: color, height: trainHeight),
            ],
          ),
        );
      },
    );
  }
}

/// Oyun ekranının arka planı.
///
/// Eskiden düz koyu bir zemindi ve tahtanın etrafı bomboş duruyordu. Burada
/// şematik bir metro haritası çizilir: yumuşak bir ışık, kıvrılarak geçen
/// birkaç hat ve üzerlerinde aktarma noktaları. Hepsi çok düşük alfada —
/// amaç tahtayla yarışmak değil, boşluğu doldurmak.
class _MergeBackdrop extends CustomPainter {
  const _MergeBackdrop({required this.accent});

  /// Yolculuğun hattının rengi; doku ona göre tonlanır.
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(AppColors.background, accent, 0.10)!,
            AppColors.background,
            Color.lerp(AppColors.background, Colors.black, 0.35)!,
          ],
          stops: const <double>[0, 0.45, 1],
        ).createShader(rect),
    );

    // Üstten gelen yumuşak ışık — peron aydınlatması hissi.
    canvas.drawCircle(
      Offset(size.width * 0.5, -size.height * 0.12),
      size.width * 0.78,
      Paint()..color = accent.withValues(alpha: 0.07),
    );

    _drawLines(canvas, size);
  }

  /// Şematik hatlar: 45 derecelik kırılmalarla ilerleyen, gerçek metro
  /// haritalarındaki gibi köşeleri yuvarlatılmış yollar.
  void _drawLines(Canvas canvas, Size size) {
    const palette = <Color>[
      Color(0xFFE30613),
      Color(0xFF009A44),
      Color(0xFF00AEEF),
      Color(0xFFFFD300),
    ];
    final stroke = (size.shortestSide * 0.012).clamp(2.0, 6.0);

    // Her hat: başlangıç yüksekliği, kırılma noktaları (genişliğin oranı)
    // ve kırılmada ne kadar yukarı/aşağı gittiği.
    const routes = <List<double>>[
      <double>[0.16, 0.22, -0.09, 0.62, 0.07],
      <double>[0.38, 0.14, 0.08, 0.55, -0.06],
      <double>[0.72, 0.30, -0.07, 0.70, 0.05],
      <double>[0.89, 0.20, 0.06, 0.58, -0.08],
    ];

    for (var i = 0; i < routes.length; i++) {
      final r = routes[i];
      final path = Path();
      var y = size.height * r[0];
      path.moveTo(-size.width * 0.05, y);
      path.lineTo(size.width * r[1], y);
      final y2 = y + size.height * r[2];
      path.lineTo(size.width * (r[1] + 0.12), y2);
      path.lineTo(size.width * r[3], y2);
      final y3 = y2 + size.height * r[4];
      path.lineTo(size.width * (r[3] + 0.12), y3);
      path.lineTo(size.width * 1.05, y3);

      canvas.drawPath(
        path,
        Paint()
          ..color = palette[i].withValues(alpha: 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      // Aktarma noktaları: hattın kırıldığı yerlerdeki halkalar.
      for (final point in <Offset>[
        Offset(size.width * r[1], y),
        Offset(size.width * r[3], y2),
      ]) {
        canvas.drawCircle(
          point,
          stroke * 1.5,
          Paint()..color = AppColors.background.withValues(alpha: 0.9),
        );
        canvas.drawCircle(
          point,
          stroke * 1.5,
          Paint()
            ..color = palette[i].withValues(alpha: 0.16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.55,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MergeBackdrop oldDelegate) =>
      oldDelegate.accent != accent;
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
