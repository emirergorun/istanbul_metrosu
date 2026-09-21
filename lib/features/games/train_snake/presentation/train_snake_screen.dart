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
import '../../../../core/widgets/line_badge.dart';
import '../../../../core/widgets/pressable.dart';
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
      discovery: scope.discoveryFor(widget.journey, TrainSnakeController.id),
      // Meydan okuma modunda tohumlu rastgelelik; Serbest Oyun'da `null`
      // gelir ve oyun kendi tohumsuz `Random()`'ını kurar.
      random: scope.challengeRandomFor(widget.journey, TrainSnakeController.id),
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: TrainSnakeController.id,
        originId: widget.journey.origin.id,
        destinationId: widget.journey.destination.id,
      ),
    );
    // Biten koşu günlük görevlere ve pasaport başarımlarına buradan
    // ulaşıyor. Oyun hiçbirini tanımaz; tek bildiği bir rapor hedefi.
    controller.reporter = scope.runReporter;
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

  /// Sürüklemenin başladığı nokta; her dönüşten sonra sıfırlanır.
  Offset? _dragAnchor;

  void _handlePanStart(DragStartDetails details) {
    _dragAnchor = details.localPosition;
  }

  /// Parmak eşiği aşar aşmaz döner.
  ///
  /// Önce `onPanEnd` kullanılıyordu ve yön ancak **parmak kalkınca**
  /// belirleniyordu; üstüne 80 px/s hız eşiği vardı, yani yavaş kaydırma
  /// hiç sayılmıyordu. Adım aralığı 0,22 saniye olan bir oyunda bu
  /// gecikme "tuşlar dönmüyor" diye hissediliyordu.
  ///
  /// Dönüşten sonra çapa yeniden konuyor: parmağı kaldırmadan L çizerek
  /// arka arkaya iki dönüş yapılabiliyor.
  void _handlePanUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final delta = details.localPosition - anchor;
    // 16 logical px: kazara titremeyi eler, bilinçli hareketi geçirir.
    if (delta.distance < 16) return;

    _turn(
      delta.dx.abs() > delta.dy.abs()
          ? (delta.dx > 0 ? SnakeDirection.right : SnakeDirection.left)
          : (delta.dy > 0 ? SnakeDirection.down : SnakeDirection.up),
    );
    _dragAnchor = details.localPosition;
  }

  void _handlePanEnd(DragEndDetails details) => _dragAnchor = null;

  /// Yön tuşuna basıldı.
  void _turnFromPad(SnakeDirection direction) {
    if (_controller?.status != GameStatus.playing) return;
    _turn(direction);
    if (AppScope.of(context).store.hapticsEnabled) {
      HapticFeedback.selectionClick();
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
                        _LevelProgress(controller: controller, accent: accent),
                        const SizedBox(height: AppSpacing.sm),
                        Expanded(
                          child: _SnakePlayArea(
                            controller: controller,
                            accent: accent,
                            onPanStart: _handlePanStart,
                            onPanUpdate: _handlePanUpdate,
                            onPanEnd: _handlePanEnd,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Dönüş tuşları oyun alanının **altında**: metroda
                        // tek elle, tutunurken oynanıyor ve başparmak
                        // ekranın alt üçte birine ulaşabiliyor. Kaydırma
                        // da çalışmaya devam ediyor; iki girdi birbirini
                        // dışlamıyor.
                        _TurnPad(
                          accent: accent,
                          enabled: controller.status == GameStatus.playing,
                          hint: controller.isAwaitingFirstInput,
                          current: controller.direction,
                          onTurn: _turnFromPad,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        JourneyStatusBar(
              gameId: TrainSnakeController.id,
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
      // Sosyal çıkış için rota ve oyun kimliği; panel meydan okuma
      // modunda karşılaştırma, normal koşuda davet gösteriyor.
      journey: controller.journey,
      gameId: TrainSnakeController.id,
      isArrival: controller.status == GameStatus.arrived,
      discovery: controller.discovery,
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
        StatRow(label: 'Vagon sayısı', value: '${controller.body.length}'),
      ],
      // Bu oyunun üç finali var: varış (yolculuk süresi doldu), zafer
      // (tüm hatlar tamamlandı) ve çarpma. Motorda yeni bir durum yok;
      // zafer yalnızca panelin dilini değiştiriyor.
      gameOverTitle: controller.isVictory
          ? 'Tüm hatlar tamamlandı'
          : 'Tren durdu',
      gameOverSubtitle: controller.isVictory
          ? 'M1\'den M11\'e kadar bütün hatları topladın. '
                'Trenin ${controller.body.length} vagon uzunluğunda.'
          : 'Duvara ya da kendi vagonlarına çarptın.',
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
      // "Hat" çipi sağdaki M1-M11 merdiveni, "Yolcu" çipi de sahnedeki
      // canlı YOLCU kutusu aynı şeyi gösterdiği için kaldırıldı. HUD'da
      // kalan skor + rota rekoru sahnede hiç görünmüyor, onlar duruyor.
      chips: const <Widget>[],
    );
  }
}

/// Oyun tahtası.
///
/// Eskiden ekranın tamamı bir sahne görseliydi
/// (`assets/images/train_snake_scene.png`, 877 KB) ve oyun alanı o
/// görselin içine elle ölçülmüş yüzdelerle yerleştiriliyordu. Üç sorun
/// vardı:
///
/// 1. **Sahte düğmeler.** Görselin üstünde boyalı bir geri oku ve bir
///    duraklatma düğmesi vardı; ikisi de işlevsizdi ama oyuncu basıyordu.
/// 2. **Çift gösterge.** Görsele basılı "HAT / YOLCU / SKOR" kutuları
///    ortak HUD ile aynı şeyi söylüyordu.
/// 3. **Kırılgan düzen.** Tahtanın sınırları görselden ölçülmüş dört
///    ondalık sayıydı; görsel değişirse hepsi yeniden ölçülmeliydi.
///
/// Şimdi tahtayı kendimiz çiziyoruz: oran serbest, sahte düğme yok,
/// ekranın tamamı oyuna ait.
class _SnakePlayArea extends StatelessWidget {
  const _SnakePlayArea({
    required this.controller,
    required this.accent,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final TrainSnakeController controller;
  final Color accent;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: trainSnakeColumns / trainSnakeRows,
        child: GestureDetector(
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              // Kenarlık hat renginde: tahta hangi hatta oynandığını
              // söyleyen tek yer. Blok Metro'da ızgara çizgisi aynı işi
              // yapıyor.
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _TrainSnakePainter(controller),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hat merdiveni yerine tek satırlık ilerleme.
///
/// Önce sağda M1..M11 dikey merdiveni vardı: on bir rozet, ekranın
/// yüksekliğinin yarısı, ve hangisinde olduğunu anlamak için taramak
/// gerekiyordu. Tek satır aynı üç bilgiyi veriyor — hangi hattasın,
/// hedefe ne kadar kaldı, ne kadar yol gittin — ve okunması bir bakış.
class _LevelProgress extends StatelessWidget {
  const _LevelProgress({required this.controller, required this.accent});

  final TrainSnakeController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final collected = controller.passengersCollected;
    final ratio = (collected / trainSnakeGoalPassengers).clamp(0.0, 1.0);

    return Semantics(
      label:
          '${controller.lineLabel} hattı, $collected yolcu toplandı, '
          'hedefe ${controller.passengersToGoal} kaldı',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                LineBadge(
                  label: controller.lineLabel,
                  color: accent,
                  compact: true,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    controller.isVictory
                        ? 'Tüm hatlar tamamlandı'
                        : 'Hedefe ${controller.passengersToGoal} yolcu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(fontSize: 12),
                  ),
                ),
                Text(
                  '$collected / $trainSnakeGoalPassengers',
                  style: AppText.micro.copyWith(
                    fontFeatures: kTabularFigures,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Çubuk yalnızca genişliğini değiştirir; düzen sabit kalır.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: (ratio * 1000).round().clamp(0, 1000),
                      child: ColoredBox(color: accent),
                    ),
                    Expanded(
                      flex: 1000 - (ratio * 1000).round().clamp(0, 1000),
                      child: const ColoredBox(color: AppColors.surfaceHigh),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        _passengerColors[controller.passengersCollected %
            _passengerColors.length];
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

/// Trenin yönünü veren dört tuş.
///
/// **Mutlak yön**, göreli dönüş değil. Önce iki göreli tuş denendi
/// ("sola dön / sağa dön"): ölü tuş bırakmıyordu ve hedefler daha
/// genişti, ama oyun yukarıdan bakış. Tren aşağı giderken "sağa dön"
/// ekranda **sola** gitmek demek. Tutarlı ve öğrenilebilir, ama metroda
/// oturumlar kısa — ilk oturumdaki kafa karışıklığı doğrudan silme
/// sebebi.
///
/// Dört tuşun klasik itirazı "biri her zaman ölü": tam ters yön yasak.
/// Bunu gizlemek yerine **gösteriyoruz** — o tuş sönük çizilir ve
/// dokunmayı yok sayar. Oyuncu "oraya basamam" bilgisini bedava alır.
///
/// Tuşlar kaydırmanın yerine geçmiyor, yanında duruyor; ikisi de artık
/// aynı dili konuşuyor (mutlak yön).
class _TurnPad extends StatelessWidget {
  const _TurnPad({
    required this.accent,
    required this.enabled,
    required this.hint,
    required this.current,
    required this.onTurn,
  });

  final Color accent;
  final bool enabled;

  /// Tren henüz başlamadıysa tuşlar "başlat" görevini de görüyor.
  final bool hint;

  /// Trenin o an baktığı yön; tam tersi sönük çizilir.
  final SnakeDirection current;

  final ValueChanged<SnakeDirection> onTurn;

  static const List<({SnakeDirection direction, IconData icon, String label})>
  _buttons = <({SnakeDirection direction, IconData icon, String label})>[
    (
      direction: SnakeDirection.left,
      icon: Icons.keyboard_arrow_left_rounded,
      label: 'Sola',
    ),
    (
      direction: SnakeDirection.up,
      icon: Icons.keyboard_arrow_up_rounded,
      label: 'Yukarı',
    ),
    (
      direction: SnakeDirection.down,
      icon: Icons.keyboard_arrow_down_rounded,
      label: 'Aşağı',
    ),
    (
      direction: SnakeDirection.right,
      icon: Icons.keyboard_arrow_right_rounded,
      label: 'Sağa',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // İpucu satırı yer kaplamasın diye yüksekliği sabit: tren
        // başlayınca tuşlar zıplamıyor.
        SizedBox(
          height: 18,
          child: hint
              ? Center(
                  child: Text(
                    'BİR YÖNE BAS YA DA KAYDIR',
                    style: AppText.micro.copyWith(color: accent),
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            for (final button in _buttons) ...<Widget>[
              Expanded(
                child: _TurnButton(
                  icon: button.icon,
                  label: button.label,
                  // Tam ters yön oynanamaz: tuş sönük ve dokunmaz.
                  enabled: enabled && !button.direction.isOppositeOf(current),
                  onTap: () => onTurn(button.direction),
                ),
              ),
              if (button != _buttons.last) const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }
}

class _TurnButton extends StatelessWidget {
  const _TurnButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        // 60: hareket eden vagonda 48 bile ıskalanıyor. Dört tuş satırı
        // paylaşınca her biri 375 px ekranda ~80 px genişlikte kalıyor,
        // yani 44 pt eşiğinin çok üstünde.
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          border: Border.all(
            color: enabled ? AppColors.outline : AppColors.surface,
            width: 1.4,
          ),
        ),
        child: Icon(
          icon,
          size: 32,
          color: enabled ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}
