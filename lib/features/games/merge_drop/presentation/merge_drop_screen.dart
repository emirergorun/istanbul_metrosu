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
import '../application/merge_drop_controller.dart';
import '../domain/merge_drop_state.dart';

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
  int _seenMerges = 0;
  Timer? _bannerTimer;
  String? _bannerText;
  final FocusNode _focusNode = FocusNode(debugLabel: 'MergeDropControls');

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
    final controller = MergeDropController(
      journey: widget.journey,
      store: scope.store,
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: MergeDropController.id,
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

    if (controller.merges != _seenMerges) {
      _seenMerges = controller.merges;
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.clear);
    }

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

  void _drop() {
    if (_controller?.drop() == true) {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.place);
    } else {
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
                        accent: accent,
                        onPause: controller.pause,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        // Havuz daha dar: toplara daha az yanal alan kalır,
                        // yığın daha çabuk sıkışır — oyun biraz zorlaşır.
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.82,
                            heightFactor: 1,
                            child: _DropPlayArea(
                              controller: controller,
                              onDrop: _drop,
                            ),
                          ),
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
        StatRow(label: 'Birleşme', value: '${controller.merges}'),
        StatRow(label: 'En büyük hat', value: controller.maxLabel),
      ],
      gameOverTitle: 'Alan doldu',
      gameOverSubtitle:
          'Hat rozetleri üst sınıra taştı, yolculuk yarıda kaldı.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }
}

class _DropHud extends StatelessWidget {
  const _DropHud({
    required this.controller,
    required this.accent,
    required this.onPause,
  });

  final MergeDropController controller;
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
          label: 'Sıradaki',
          value: controller.currentLabel,
          accent: _mergeDropLineColor(controller.currentLevel),
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
    final highlight = Color.lerp(accent, Colors.white, 0.55)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Sıradaki topla aynı görünüm: değişen rengi doğrudan gösterir.
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.4),
                colors: <Color>[highlight, accent],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
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
        ],
      ),
    );
  }
}

/// Sahne görselinin ([assets/images/merge_drop_scene.png]) gerçek piksel
/// en/boy oranı. Görsel **bozulmadan/kırpılmadan** tam gösterilmesi için
/// düzen bu oranı korur (bkz. [_DropPlayArea]).
const double _sceneAspectRatio = 1055 / 1491;

/// Kutunun (topların biriktiği alan) sahne görseli içindeki göreli
/// sınırları — sarı çerçevenin hemen içi, 0..1 aralığında.
///
/// Görsel manuel ölçülerek bulundu; görsel değişirse bu dört sayı da
/// yeniden ölçülmeli. Fizik dünyası bu dikdörtgene, tam üstüne binecek
/// şekilde yerleştirilir — "topların gösterilen alanın içine birikmesi"
/// bu hizalamayla sağlanır.
const double _boxLeft = 0.075;
const double _boxTop = 0.335;
const double _boxRight = 0.925;
const double _boxBottom = 0.955;

class _DropPlayArea extends StatelessWidget {
  const _DropPlayArea({required this.controller, required this.onDrop});

  final MergeDropController controller;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: _sceneAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sceneWidth = constraints.maxWidth;
            final sceneHeight = constraints.maxHeight;
            final boxLeft = sceneWidth * _boxLeft;
            final boxTop = sceneHeight * _boxTop;
            final boxWidth = sceneWidth * (_boxRight - _boxLeft);
            final boxHeight = sceneHeight * (_boxBottom - _boxTop);

            // Fizik dünyası izotropik (1 birim = kutu genişliği); kutunun
            // kaç birim yüksekliğinde olduğunu yalnızca düzen bilir.
            final aspect = boxHeight / boxWidth;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.setPoolAspect(aspect);
            });

            void aimFromLocal(Offset localInBox) {
              final x = (localInBox.dx / boxWidth).clamp(0.0, 1.0);
              controller.moveAim(x);
            }

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  'assets/images/merge_drop_scene.png',
                  fit: BoxFit.fill,
                ),
                Positioned(
                  left: boxLeft,
                  top: boxTop,
                  width: boxWidth,
                  height: boxHeight,
                  child: ClipRect(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) =>
                          aimFromLocal(details.localPosition),
                      onTapDown: (details) {
                        aimFromLocal(details.localPosition);
                        onDrop();
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          // Sırada gelen topun rengi kutunun içine hafifçe
                          // yansır: hem görsel derinlik katar hem de
                          // "sırada ne var" ipucu verir.
                          _AmbientTint(
                            color: _mergeDropLineColor(controller.currentLevel),
                          ),
                          CustomPaint(painter: _MergeDropPainter(controller)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Sıradaki topun rengiyle kutunun üst kısmına yumuşakça geçiş yapan çok
/// soluk bir parıltı biner — zemin artık sahne görselinden geldiği için
/// bu katman yalnızca renk ipucu, arka plan değil.
class _AmbientTint extends StatelessWidget {
  const _AmbientTint({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.55),
          radius: 1.15,
          colors: <Color>[
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _MergeDropPainter extends CustomPainter {
  const _MergeDropPainter(this.controller);

  final MergeDropController controller;

  @override
  void paint(Canvas canvas, Size size) {
    // Zemin artık sahne görselinden geliyor (bkz. _DropPlayArea); bu katman
    // şeffaf bırakılıyor ki görsel altından görünsün.
    _drawDangerLine(canvas, size);
    _drawAimGuide(canvas, size);
    _drawBalls(canvas, size);
    _drawPreview(canvas, size);
  }

  /// Dünya birimini piksele çeviren **tek** ölçek.
  ///
  /// Hem x hem y hem de yarıçap bununla çarpılır. Ayrı ölçekler kullanmak
  /// (x→width, y→height, yarıçap→shortestSide) daireleri elipse çevirip
  /// fizikte tam temas eden topların ekranda boşluklu görünmesine yol
  /// açıyordu.
  double _scale(Size size) => size.width;

  /// Tehlike çizgisini ince bir çizgi yerine peron kenarı gibi sarı-siyah
  /// diyagonal bir tehlike şeridi olarak çizer: hem "burası kutunun sınırı"
  /// mesajını çok daha net verir hem de metro temasına oturur.
  void _drawDangerLine(Canvas canvas, Size size) {
    final scale = _scale(size);
    final y = controller.dangerY * scale;
    const thickness = 6.0;
    final band = Rect.fromLTWH(0, y - thickness / 2, size.width, thickness);

    canvas.save();
    canvas.clipRect(band);
    canvas.drawRect(band, Paint()..color = const Color(0xFF16181C));

    const stripeWidth = 9.0;
    const stripeGap = 9.0;
    final yellow = Paint()..color = AppColors.warning;
    var sx = -band.height;
    while (sx < band.width + band.height) {
      final path = Path()
        ..moveTo(sx, band.top)
        ..lineTo(sx + stripeWidth, band.top)
        ..lineTo(sx + stripeWidth - band.height, band.bottom)
        ..lineTo(sx - band.height, band.bottom)
        ..close();
      canvas.drawPath(path, yellow);
      sx += stripeWidth + stripeGap;
    }
    canvas.restore();
  }

  /// Nişan alınan sütunu zeminden ayağa kadar ince, soluk bir çizgiyle
  /// gösterir — Suika/Fruit Merge'deki düşüş rehberinin karşılığı. Topun
  /// aşağıda **nereye birikeceğini** önceden okumayı kolaylaştırır.
  void _drawAimGuide(Canvas canvas, Size size) {
    if (!controller.canDrop) return;
    final scale = _scale(size);
    final radius = mergeDropRadiusForLevel(controller.currentLevel);
    final startY = (radius + 0.015 + radius * 0.9) * scale;
    final endY = controller.worldHeight * scale;
    if (endY <= startY) return;
    final x = controller.aimX * scale;
    final paint = Paint()
      ..color = _mergeDropLineColor(
        controller.currentLevel,
      ).withValues(alpha: 0.24)
      ..strokeWidth = 2;
    _drawDashedLine(
      canvas,
      Offset(x, startY),
      Offset(x, endY),
      paint,
      dash: 5,
      gap: 7,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 8,
    double gap = 6,
  }) {
    final total = (to - from).distance;
    if (total <= 0) return;
    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final segmentEnd = math.min(travelled + dash, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * segmentEnd,
        paint,
      );
      travelled += dash + gap;
    }
  }

  void _drawBalls(Canvas canvas, Size size) {
    final scale = _scale(size);
    // Önce tüm gölgeler, sonra tüm toplar: bir topun gölgesi komşusunun
    // üzerine düşse bile topun kendisi her zaman gölgenin üstünde kalır.
    for (final ball in controller.balls) {
      _drawBallShadow(canvas, scale, ball.x, ball.y, ball.drawRadius);
    }
    for (final ball in controller.balls) {
      _drawBall(
        canvas,
        size,
        ball.x,
        ball.y,
        ball.level,
        alpha: 1,
        // Birleşen top şişerek gelir (bkz. DropBall.drawRadius).
        worldRadius: ball.drawRadius,
      );
    }
  }

  void _drawBallShadow(
    Canvas canvas,
    double scale,
    double x,
    double y,
    double worldRadius,
  ) {
    final radius = worldRadius * scale;
    final center = Offset(x * scale, y * scale + radius * 0.32);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 1.7,
        height: radius * 0.75,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
  }

  void _drawPreview(Canvas canvas, Size size) {
    final radius = mergeDropRadiusForLevel(controller.currentLevel);
    final x = controller.aimX;
    final y = radius + 0.015;
    _drawBall(
      canvas,
      size,
      x,
      y,
      controller.currentLevel,
      alpha: controller.canDrop ? 0.85 : 0.35,
    );
  }

  /// Topu düz bir daire değil, ışığı üst-sol köşeden alan parlak bir küre
  /// gibi çizer (radyal gradyan + küçük highlight noktası), üstüne sevimli
  /// bir tren yüzü ve alt kenarına hat rozetini taşıyan küçük bir levha
  /// biner — Suika/Fruit Merge'deki yüzlü meyve görünümünün metro
  /// karşılığı. Düz dolgu + ortalanmış büyük metin eskiden yığını "oyuncak
  /// bloklar" gibi düz gösteriyordu.
  void _drawBall(
    Canvas canvas,
    Size size,
    double x,
    double y,
    int level, {
    required double alpha,
    double? worldRadius,
  }) {
    final scale = _scale(size);
    final radius = (worldRadius ?? mergeDropRadiusForLevel(level)) * scale;
    final center = Offset(x * scale, y * scale);
    final base = _mergeDropLineColor(level);
    final highlight = Color.lerp(base, Colors.white, 0.5)!;
    final shade = Color.lerp(base, Colors.black, 0.32)!;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = RadialGradient(
      center: const Alignment(-0.35, -0.42),
      radius: 0.95,
      colors: <Color>[
        highlight.withValues(alpha: alpha),
        base.withValues(alpha: alpha),
        shade.withValues(alpha: alpha),
      ],
      stops: const <double>[0.0, 0.55, 1.0],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = shade.withValues(alpha: 0.55 * alpha),
    );
    canvas.drawCircle(
      center.translate(-radius * 0.32, -radius * 0.38),
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.35 * alpha),
    );

    _drawTrainFace(canvas, center, radius, shade, alpha);
    _drawLevelPlate(canvas, center, radius, level, base, shade, alpha);
  }

  /// İki göz + gülümseme + allık: her top küçük, sevimli bir tren yüzüne
  /// dönüşür. Hat rengiyle bağımsız, her seviyede aynı yüz çizilir —
  /// kimlik zaten renk ve alttaki rozetten geliyor.
  void _drawTrainFace(
    Canvas canvas,
    Offset center,
    double radius,
    Color shade,
    double alpha,
  ) {
    final eyeDx = radius * 0.34;
    final eyeCenterY = center.dy - radius * 0.08;
    final eyeRadius = radius * 0.17;
    final pupilRadius = eyeRadius * 0.52;

    for (final dx in <double>[-eyeDx, eyeDx]) {
      final eyeCenter = Offset(center.dx + dx, eyeCenterY);
      canvas.drawCircle(
        eyeCenter,
        eyeRadius,
        Paint()..color = Colors.white.withValues(alpha: 0.94 * alpha),
      );
      final pupilCenter = eyeCenter.translate(0, pupilRadius * 0.2);
      canvas.drawCircle(
        pupilCenter,
        pupilRadius,
        Paint()..color = shade.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        pupilCenter.translate(-pupilRadius * 0.35, -pupilRadius * 0.35),
        pupilRadius * 0.32,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * alpha),
      );
    }

    final smileRect = Rect.fromCenter(
      center: center.translate(0, radius * 0.14),
      width: radius * 0.62,
      height: radius * 0.46,
    );
    canvas.drawArc(
      smileRect,
      0.35,
      math.pi - 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * 0.09)
        ..strokeCap = StrokeCap.round
        ..color = shade.withValues(alpha: 0.75 * alpha),
    );

    final blush = Paint()
      ..color = const Color(0xFFFF9EB0).withValues(alpha: 0.4 * alpha);
    for (final dx in <double>[-radius * 0.56, radius * 0.56]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(dx, radius * 0.1),
          width: radius * 0.32,
          height: radius * 0.18,
        ),
        blush,
      );
    }
  }

  /// Hat rozetini artık topun ortasında değil, tren camının altındaki
  /// güzergâh levhası gibi küçük bir haptan taşır — yüz merkezi meşgul
  /// etmeden hangi seviyede olduğumuzu okumayı sürdürür.
  void _drawLevelPlate(
    Canvas canvas,
    Offset center,
    double radius,
    int level,
    Color base,
    Color shade,
    double alpha,
  ) {
    final plateCenter = center.translate(0, radius * 0.62);
    final textPainter = TextPainter(
      text: TextSpan(
        text: mergeDropLabelForLevel(level),
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: radius * 0.4,
          fontWeight: FontWeight.w900,
          color: base.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Levha genişliği metne göre büyür: "M1".."M9" iki karakterken
    // "M10"/"M11" üç karakter — sabit genişlik olsaydı çift haneli
    // etiketler levhadan taşardı. Alt sınır eski görünümü korur.
    final plateWidth = math.max(
      radius * 1.05,
      textPainter.width + radius * 0.36,
    );
    final plateRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: plateCenter,
        width: plateWidth,
        height: radius * 0.46,
      ),
      Radius.circular(radius * 0.23),
    );
    canvas.drawRRect(
      plateRect,
      Paint()..color = Colors.white.withValues(alpha: 0.92 * alpha),
    );
    canvas.drawRRect(
      plateRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = shade.withValues(alpha: 0.45 * alpha),
    );

    textPainter.paint(
      canvas,
      plateCenter.translate(-textPainter.width / 2, -textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _MergeDropPainter oldDelegate) => true;
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

Color _mergeDropLineColor(int level) {
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
