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
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../application/train_snake_controller.dart';
import '../domain/train_snake_state.dart';

class TrainSnakeScreen extends StatefulWidget {
  const TrainSnakeScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<TrainSnakeScreen> createState() => _TrainSnakeScreenState();
}

class _TrainSnakeScreenState extends State<TrainSnakeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  TrainSnakeController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStationPulse = 0;
  int _seenLevel = 1;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'TrainSnakeControls');

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
    final controller = TrainSnakeController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: TrainSnakeController.id,
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

    if (controller.level != _seenLevel) {
      _seenLevel = controller.level;
      _haptic(HapticFeedback.mediumImpact);
      _showBanner('${controller.lineLabel} HATTINA GEÇTİN!');
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
    // LaneRunnerScreen/RailFlightScreen'de uygulanan aynı düzeltme). Canlı
    // kalması gereken kısmı build()'deki ListenableBuilder hallediyor.
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

  void _turn(SnakeDirection direction) {
    _controller?.turn(direction);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.keyW) {
      _turn(SnakeDirection.up);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.keyS) {
      _turn(SnakeDirection.down);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _turn(SnakeDirection.left);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _turn(SnakeDirection.right);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.distance < 80) return;
    if (velocity.dx.abs() > velocity.dy.abs()) {
      _turn(velocity.dx > 0 ? SnakeDirection.right : SnakeDirection.left);
    } else {
      _turn(velocity.dy > 0 ? SnakeDirection.down : SnakeDirection.up);
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
          // Yalnızca bu içerik controller'ı dinler ve her adımda yeniden
          // kurulur; PopScope/KeyboardListener/Scaffold sarmalayıcıları
          // hiç değişmediği için bir kez kurulup öyle kalır.
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
                        _SnakeHud(
                          controller: controller,
                          accent: accent,
                          onPause: controller.pause,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _SnakePlayArea(
                            controller: controller,
                            onPanEnd: _handlePanEnd,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
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
                // Sprint başladığında bir kez geçer; oyunu durdurmaz.
                SprintBanner(pulse: controller.sprintPulse),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(
    TrainSnakeController controller,
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
        StatRow(
          label: 'Toplanan yolcu',
          value: '${controller.passengersCollected}',
        ),
        StatRow(label: 'Ulaşılan hat', value: controller.lineLabel),
      ],
      gameOverTitle: 'Tren durdu',
      gameOverSubtitle: 'Duvara ya da kendi vagonlarına çarptın.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _SnakeHud extends StatelessWidget {
  const _SnakeHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final TrainSnakeController controller;
  final Color accent;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return JourneyHud(
      run: controller,
      accent: accent,
      onPause: onPause,
      chips: <Widget>[
        // "Hat" çipi kaldırıldı: sağdaki M1-M11 merdiveni şu anki hattı
        // zaten gösteriyor, HUD'da tekrar etmeye gerek yok.
        _HudChip(
          label: 'Yolcu',
          value:
              '${controller.passengersInLevel}/$trainSnakePassengersPerLevel',
          accent: accent,
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

/// Kaynak sahne görselinin ([assets/images/train_snake_scene.png]) gerçek
/// piksel en/boy oranı. Görsel **bozulmadan/kırpılmadan** tam gösterilmesi
/// için düzen bu oranı korur (bkz. [_SnakePlayArea]).
const double _sceneAspectRatio = 596 / 1026;

/// Oyun alanının (sarı rayların hemen içi) sahne görseli içindeki göreli
/// sınırları, 0..1 aralığında. Görsel manuel ölçülerek bulundu; görsel
/// değişirse bu dört sayı da yeniden ölçülmeli.
const double _boardLeft = 0.151;
const double _boardTop = 0.108;
const double _boardRight = 0.864;
const double _boardBottom = 0.882;

/// M1..M11 merdiveninin sahne görseli içindeki göreli sınırları. Görselde
/// bu merdiven **sabit** çizilmiş (hep M1 vurgulu); bu dikdörtgenin üstüne
/// gerçek seviyeyle senkron, canlı bir merdiven bindirilir.
const double _ladderLeft = 0.895;
const double _ladderTop = 0.135;
const double _ladderRight = 1.0;
const double _ladderBottom = 0.615;

/// Sahne görselini tam gösterir, canlı oyunu (tahta + tren + yolcu) tam da
/// görseldeki sarı raylı kutunun içine oturtur. Raylar görselin kendi
/// çizimi olduğu için kenarlar her zaman net görünür ("yanlar belli
/// olsun"); oyun katmanı o dikdörtgeni opak doldurduğundan altındaki örnek
/// çizim (tren/yolcu illüstrasyonu) tamamen örtülür.
class _SnakePlayArea extends StatelessWidget {
  const _SnakePlayArea({required this.controller, required this.onPanEnd});

  final TrainSnakeController controller;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: _sceneAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sceneWidth = constraints.maxWidth;
            final sceneHeight = constraints.maxHeight;
            final boardLeft = sceneWidth * _boardLeft;
            final boardTop = sceneHeight * _boardTop;
            final boardWidth = sceneWidth * (_boardRight - _boardLeft);
            final boardHeight = sceneHeight * (_boardBottom - _boardTop);

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  'assets/images/train_snake_scene.png',
                  fit: BoxFit.fill,
                ),
                Positioned(
                  left: boardLeft,
                  top: boardTop,
                  width: boardWidth,
                  height: boardHeight,
                  child: ClipRect(
                    child: GestureDetector(
                      onPanEnd: onPanEnd,
                      child: CustomPaint(
                        painter: _TrainSnakePainter(controller),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: sceneWidth * _ladderLeft,
                  top: sceneHeight * _ladderTop,
                  width: sceneWidth * (_ladderRight - _ladderLeft),
                  height: sceneHeight * (_ladderBottom - _ladderTop),
                  child: _LineLadder(level: controller.level),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Görseldeki sabit M1..M11 merdiveninin üstüne binen canlı sürüm: şu anki
/// hat büyük ve rengiyle vurgulu, diğerleri küçük ve soluk. "M1'den M2'ye
/// geçince sağ panel de senkron ilerlesin" isteğinin karşılığı.
class _LineLadder extends StatelessWidget {
  const _LineLadder({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Boyut hem genişliğe hem yüksekliğe sığmalı — 11 madalyonun
        // toplamı yüksekliği aşarsa Column taşardı.
        final pill = math.min(
          constraints.maxWidth,
          constraints.maxHeight / trainSnakeMaxLevel,
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            for (var i = 1; i <= trainSnakeMaxLevel; i++)
              _LadderPill(active: i == level, size: pill, level: i),
          ],
        );
      },
    );
  }
}

class _LadderPill extends StatelessWidget {
  const _LadderPill({
    required this.active,
    required this.size,
    required this.level,
  });

  final bool active;
  final double size;
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = _snakeLineColor(level);
    final dimension = active ? size : size * 0.78;
    return Semantics(
      label: '${trainSnakeLabelForLevel(level)} hattı${active ? ', şu anki hat' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: dimension,
        height: dimension,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : AppColors.surfaceHigh.withValues(alpha: 0.9),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.8)
                : _TrainSnakePainter._carOutline,
            width: active ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          trainSnakeLabelForLevel(level),
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w800,
            fontSize: dimension * 0.4,
            color: active
                ? LineTheme.readableOn(color)
                : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Işgarada treni ve yolcuyu çizer. Bilerek düz: gradyan, parıltı ya da
/// yapay bir "AI görünümü" yok — tek renk dolgular ve net çizgiler.
class _TrainSnakePainter extends CustomPainter {
  const _TrainSnakePainter(this.controller);

  final TrainSnakeController controller;

  // Tahta artık koyu değil, krem tonlu ve hafif kareli — referans
  // görsellerdeki gibi sıcak, oyunsu bir zemin.
  static const Color _cream = Color(0xFFF3E5C3);
  static const Color _creamAlt = Color(0xFFEAD7A8);

  static const List<Color> _passengerColors = <Color>[
    Color(0xFF2F80ED),
    Color(0xFFEB5757),
    Color(0xFF27AE60),
    Color(0xFFF2994A),
    Color(0xFFBB6BD9),
  ];

  // Vagon gövdesi nötr, gerçek bir tren gibi — kimlik rengi yalnızca ön
  // kabinde. Bütün gövdeyi hat rengine boyamak treni "renkli bir yılana"
  // çeviriyordu.
  static const Color _carBody = Color(0xFFEDEFF2);
  static const Color _carWindow = Color(0xFF29323D);
  static const Color _carOutline = Color(0xFF7D8590);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / trainSnakeColumns;
    final cellH = size.height / trainSnakeRows;
    _drawBoard(canvas, size, cellW, cellH);
    _drawPassenger(canvas, cellW, cellH);
    _drawBody(canvas, cellW, cellH);
  }

  void _drawBoard(Canvas canvas, Size size, double cellW, double cellH) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _cream);
    final alt = Paint()..color = _creamAlt;
    for (var row = 0; row < trainSnakeRows; row++) {
      for (var col = 0; col < trainSnakeColumns; col++) {
        if ((row + col).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH),
          alt,
        );
      }
    }
  }

  /// Referans görseldeki gibi renkli, basit bir "yolcu" işareti: yuvarlak
  /// baş + gövde, ince koyu bir çerçeveyle sticker gibi kesilmiş hissi.
  /// Her toplanan yolcuda renk değişir — tahtada tek tip nokta yerine canlı
  /// bir çeşitlilik olsun diye.
  void _drawPassenger(Canvas canvas, double cellW, double cellH) {
    final p = controller.passenger;
    final cell = math.min(cellW, cellH);
    final center = Offset((p.x + 0.5) * cellW, (p.y + 0.5) * cellH);
    final color =
        _passengerColors[controller.passengersCollected % _passengerColors.length];
    final fill = Paint()..color = color;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, cell * 0.05)
      ..color = AppColors.background.withValues(alpha: 0.55);

    final headCenter = center.translate(0, -cell * 0.15);
    canvas.drawCircle(headCenter, cell * 0.15, fill);
    canvas.drawCircle(headCenter, cell * 0.15, outline);

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, cell * 0.16),
        width: cell * 0.36,
        height: cell * 0.3,
      ),
      Radius.circular(cell * 0.12),
    );
    canvas.drawRRect(bodyRect, fill);
    canvas.drawRRect(bodyRect, outline);
  }

  /// Vagon vagon eklenen gerçek bir **tren** çizer — yılan değil: tek bir
  /// gövde boyunca uzanan kimlik şeridi tüm vagonları "aynı trenin parçası"
  /// gibi bağlar (ayrı, trenden kopuk bir nesne yok). Baş vagon, gidilen
  /// yöne dönük sivri bir kabin burnuyla ayrışır.
  ///
  /// Konumlar [_interpolatedCenter] ile hücreden hücreye **kayarak**
  /// çizilir — eskiden her vagon bir sonraki hücreye ışınlanıyordu, bu da
  /// "kasıyor" hissi veriyordu.
  void _drawBody(Canvas canvas, double cellW, double cellH) {
    final body = controller.body;
    if (body.isEmpty) return;
    final cell = math.min(cellW, cellH);
    final bodyFill = Paint()..color = _carBody;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, cell * 0.045)
      ..color = _carOutline;
    final windowFill = Paint()..color = _carWindow;
    final stripeFill = Paint()..color = _snakeLineColor(controller.level);
    final dir = _headDirectionOffset();

    for (var i = body.length - 1; i >= 0; i--) {
      final isTail = i == body.length - 1 && body.length > 1;
      final isHead = i == 0;
      final center = _interpolatedCenter(i, cellW, cellH);
      final scaleW = isTail ? 0.62 : 0.96;
      final scaleH = isTail ? 0.62 : 0.92;
      final rect = Rect.fromCenter(
        center: center,
        width: cellW * scaleW,
        height: cellH * scaleH,
      );
      final rrect = isHead
          ? _leadingRoundedRect(rect, dir, cell * 0.16, cell * 0.46)
          : RRect.fromRectAndRadius(
              rect,
              Radius.circular(cell * (isTail ? 0.5 : 0.14)),
            );

      canvas.drawRRect(rrect, bodyFill);

      if (!isTail) {
        canvas.save();
        canvas.clipRRect(rrect);
        // Pencere bandı.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + cell * 0.1,
              rect.top + cell * 0.1,
              rect.width - cell * 0.2,
              cell * 0.26,
            ),
            Radius.circular(cell * 0.08),
          ),
          windowFill,
        );
        // Kimlik şeridi: gövdenin alt kısmında baştan kuyruğa aynı renk
        // devam eder — tek bir trenin parçası olduklarını gösterir.
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left,
            rect.bottom - cell * 0.14,
            rect.width,
            cell * 0.14,
          ),
          stripeFill,
        );
        canvas.restore();
      }
      canvas.drawRRect(rrect, outline);
    }
  }

  /// [i]. vagonun ekrandaki konumu — önceki hücre ile şimdiki hücre
  /// arasında [TrainSnakeController.stepProgress] oranında ara değer.
  ///
  /// `previousBody[i-1] == body[i]` ilişkisi (bkz. controller) sayesinde
  /// her vagon "eskiden neredeydi"den "şimdi nerede"ye doğru düzgün bir
  /// çizgide kayar; adım adım ışınlanmaz.
  Offset _interpolatedCenter(int i, double cellW, double cellH) {
    final current = controller.body[i];
    final previousBody = controller.previousBody;
    final prevIndex = i == 0 ? 0 : i - 1;
    final previous = prevIndex < previousBody.length
        ? previousBody[prevIndex]
        : current;
    final t = controller.stepProgress;
    final x = previous.x + (current.x - previous.x) * t;
    final y = previous.y + (current.y - previous.y) * t;
    return Offset((x + 0.5) * cellW, (y + 0.5) * cellH);
  }

  /// Dikdörtgeni, verilen yönde "ilerleyen" iki köşesi büyük yarıçapla
  /// (sivri kabin burnu), arkadaki iki köşesi küçük yarıçapla yuvarlanmış
  /// döndürür — baş vagonun ayrı bir parça değil, kendi gövdesinin doğal
  /// bir devamı gibi görünmesini sağlar.
  RRect _leadingRoundedRect(Rect rect, Offset dir, double small, double big) {
    final right = dir.dx > 0.5;
    final left = dir.dx < -0.5;
    final down = dir.dy > 0.5;
    final up = dir.dy < -0.5;
    return RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(left || up ? big : small),
      topRight: Radius.circular(right || up ? big : small),
      bottomLeft: Radius.circular(left || down ? big : small),
      bottomRight: Radius.circular(right || down ? big : small),
    );
  }

  Offset _headDirectionOffset() {
    if (controller.body.length < 2) return const Offset(1, 0);
    final head = controller.body[0];
    final neck = controller.body[1];
    final dx = (head.x - neck.x).toDouble();
    final dy = (head.y - neck.y).toDouble();
    if (dx == 0 && dy == 0) return const Offset(1, 0);
    return Offset(dx, dy);
  }

  @override
  bool shouldRepaint(covariant _TrainSnakePainter oldDelegate) => true;
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

Color _snakeLineColor(int level) {
  const colors = <Color>[
    Color(0xFFE30613),
    Color(0xFF009A44),
    Color(0xFF00AEEF),
    Color(0xFFE6007E),
    Color(0xFF6A2C91),
    Color(0xFFB58500),
    Color(0xFFF05A8A),
    Color(0xFF00B2A9),
    Color(0xFF8BC34A),
    Color(0xFFFF7043),
    Color(0xFF3F51B5),
  ];
  return colors[(level - 1).clamp(0, colors.length - 1)];
}
