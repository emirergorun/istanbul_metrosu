import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../journey/models/journey.dart';
import '../../../journey/models/station.dart';
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
import '../application/rail_lay_controller.dart';
import '../domain/rail_lay_state.dart';
import 'galata_backdrop.dart';
import 'rail_lay_painter.dart';

class RailLayScreen extends StatefulWidget {
  const RailLayScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<RailLayScreen> createState() => _RailLayScreenState();
}

class _RailLayScreenState extends State<RailLayScreen>
    with WidgetsBindingObserver {
  RailLayController? _controller;
  AudioService? _audio;

  /// Ortak yolculuk; oyun kendi tek oyunluk yolculuğunu kurduysa `null`.
  JourneyController? _journeyHost;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenClearPulse = 0;
  int _seenBumpPulse = 0;
  bool _wasSliding = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'RailLayControls');

  /// Bölümlerin hat renkleri: ağın gerçek hatları, rengi tekrar edenler
  /// (M1A/M1B aynı kırmızı) bir kez. Bölüm bölüm dönüşümlü gelir.
  late List<MetroLine> _palette;

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
    _palette = <MetroLine>[];
    for (final line in scope.metro.lines()) {
      if (_palette.any((MetroLine l) => l.color == line.color)) continue;
      _palette.add(line);
    }

    final session = JourneyScope.sessionFor(context, widget.journey);
    // Kayıt yalnızca oyun gerçekten o yolculuğa bağlıysa yazılır; başka bir
    // rotanın yolculuğuna bu oyunun puanı karışmamalı.
    _journeyHost = session == null ? null : JourneyScope.maybeOf(context);
    final controller = RailLayController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, RailLayController.id),
      // İlerleme kalıcı: oyuncu kaldığı bölümden devam eder.
      startLevel: scope.store.railLayLevel,
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      session: session,
    );
    controller.reporter = scope.runReporter;
    _seenClearPulse = controller.clearPulse;
    _seenBumpPulse = controller.bumpPulse;
    controller.addListener(_onControllerChanged);
    _controller = controller;
    controller.start();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    if (controller.clearPulse != _seenClearPulse) {
      _seenClearPulse = controller.clearPulse;
      // Bölüm numarası kalıcı kayda anında yazıldı; bölümün puanı da
      // yolculuk kaydına aynı anda yazılmalı. Beş saniyelik kalp atışını
      // beklerken uygulama kapanırsa puan kaybolur, bölüm ise geri gelmez.
      _journeyHost?.saveNow();
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.clear);
    }
    if (controller.bumpPulse != _seenBumpPulse) {
      _seenBumpPulse = controller.bumpPulse;
      _haptic(HapticFeedback.lightImpact);
    }
    // Metro duvara oturduğu an kısa bir tık: kayışın bittiği hissedilsin.
    if (_wasSliding && !controller.isSliding && !controller.isCelebrating) {
      _haptic(HapticFeedback.selectionClick);
    }
    _wasSliding = controller.isSliding;

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      _playedArrivalSound = false;
    }
    _syncMusic();
    // Bilerek setState() yok: build()'deki ListenableBuilder yeterli.
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
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  void _sound(GameSound sound) => AppScope.of(context).audio.play(sound);

  MetroLine _lineFor(int level) => _palette[(level - 1) % _palette.length];

  void _swipe(RailLayDirection direction) => _controller?.swipe(direction);

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _swipe(RailLayDirection.up);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _swipe(RailLayDirection.down);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _swipe(RailLayDirection.left);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _swipe(RailLayDirection.right);
    }
  }

  /// Sürüklemenin başladığı nokta; her yön verişten sonra sıfırlanır.
  Offset? _dragAnchor;

  void _handlePanStart(DragStartDetails details) {
    _dragAnchor = details.localPosition;
  }

  /// Parmak eşiği aşar aşmaz yön verir (Yolcu Topla kalıbı): parmağın
  /// kalkması beklenmez, çapa yenilendiği için parmağı kaldırmadan iki
  /// kayış zincirlenebilir.
  void _handlePanUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final delta = details.localPosition - anchor;
    if (delta.distance < 16) return;
    _swipe(
      delta.dx.abs() > delta.dy.abs()
          ? (delta.dx > 0 ? RailLayDirection.right : RailLayDirection.left)
          : (delta.dy > 0 ? RailLayDirection.down : RailLayDirection.up),
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
    final journeyLine = AppScope.of(context).metro.lineById(journey.lineId);
    final accent = journeyLine == null
        ? AppColors.success
        : LineTheme.from(journeyLine.color).accent;

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
              // Arka plan bir kez çizilir; oyun her karede yeniden
              // çizilirken kule önbellekte kalır.
              const Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: GalataBackdropPainter()),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final line = _lineFor(controller.levelNumber);
                  return Stack(
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
                              JourneyHud(
                                run: controller,
                                accent: accent,
                                onPause: controller.pause,
                                gameScore: controller.scoreThisGame,
                                chips: <Widget>[
                                  _HudChip(
                                    label: 'Bölüm',
                                    value:
                                        '${controller.levelNumber} · ${line.id}',
                                    accent: accent,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Expanded(
                                child: _RailLayPlayArea(
                                  controller: controller,
                                  lineColor: line.color,
                                  onPanStart: _handlePanStart,
                                  onPanUpdate: _handlePanUpdate,
                                  onPanEnd: _handlePanEnd,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _ControlRow(
                                controller: controller,
                                onRestart: controller.restartLevel,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              JourneyStatusBar(
                                gameId: RailLayController.id,
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
                          onSkipped: () =>
                              AppScope.of(context).audio.stopLongForm(),
                          lineId: journey.lineId,
                          stationName: journey.destination.name,
                          child: _buildResult(controller, accent),
                        ),
                      SprintBanner(pulse: controller.sprintPulse),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bu oyunda kaybetmek yok; panel yalnızca varışta açılır.
  Widget _buildResult(RailLayController controller, Color accent) {
    return ResultOverlay(
      journey: controller.journey,
      gameId: RailLayController.id,
      isArrival: true,
      discovery: controller.discovery,
      journeyContinues: false,
      remainingSeconds: controller.remainingSeconds,
      destinationName: controller.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      isNewBest: controller.isNewBest,
      extraStats: <Widget>[
        ...journeyBreakdownRows(controller.journeySession),
        StatRow(
          label: 'Tamamlanan bölüm',
          value: '${controller.levelsCleared}',
        ),
        StatRow(label: 'Sıradaki bölüm', value: '${controller.levelNumber}'),
      ],
      gameOverTitle: 'Hat döşendi',
      gameOverSubtitle: 'Yolculuk bitti.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: false,
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

/// Oyun alanı: tahta ortalanır, bölüm sonunda üstünde kutlama yazısı.
class _RailLayPlayArea extends StatelessWidget {
  const _RailLayPlayArea({
    required this.controller,
    required this.lineColor,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final RailLayController controller;
  final Color lineColor;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  /// Küçük bölümlerde tahta ekranı doldurmasın: hücre en fazla bu kadar.
  static const double _maxCell = 58;

  /// Tahtanın altındaki kutlama yuvası.
  ///
  /// Övgü yazısı önce tahtanın ortasına biniyordu ve döşenmiş rayların
  /// üstünde okunmuyordu (kullanıcı bildirdi). Artık tahtanın altında,
  /// kendi yerinde. Yuva kutlama yokken de yer kaplar: yazı gelip giderken
  /// tahta zıplamasın.
  static const double _celebrationSlot = 64;

  @override
  Widget build(BuildContext context) {
    final level = controller.level;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Yuva için yükseklikten pay düşülür; yalnız en uzun bölümlerde
        // hücre biraz küçülür, kısalar zaten sığıyor.
        final boardHeight = math.max(
          0.0,
          constraints.maxHeight - _celebrationSlot,
        );
        final cell = math.min(
          _maxCell,
          math.min(
            constraints.maxWidth / level.width,
            boardHeight / (level.height + railLayBoardDepth),
          ),
        );
        final board = Size(
          cell * level.width,
          cell * (level.height + railLayBoardDepth),
        );
        // Kaydırma tahtanın dışında da çalışsın: parmak koridora denk
        // gelmek zorunda değil.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox.fromSize(
                  size: board,
                  child: CustomPaint(
                    painter: RailLayPainter(
                      controller: controller,
                      lineColor: lineColor,
                    ),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth,
                  height: _celebrationSlot,
                  child: controller.isCelebrating
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Celebration(
                            progress: controller.celebrationProgress,
                            levelsCleared: controller.levelsCleared,
                            award: controller.lastAward,
                            color: lineColor,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bölüm sonu: kısa bir övgü ve kazanılan puan.
class _Celebration extends StatelessWidget {
  const _Celebration({
    required this.progress,
    required this.levelsCleared,
    required this.award,
    required this.color,
  });

  final double progress;
  final int levelsCleared;
  final int award;
  final Color color;

  static const List<String> _praise = <String>[
    'HAT AÇILDI!',
    'HARİKA!',
    'MÜKEMMEL!',
  ];

  @override
  Widget build(BuildContext context) {
    // İlk üçte birde büyüyerek belirir, sonda solar.
    final grow = Curves.easeOutBack.transform((progress * 3).clamp(0.0, 1.0));
    final fade = progress > 0.75 ? (1 - progress) / 0.25 : 1.0;
    final text = _praise[(levelsCleared - 1) % _praise.length];
    return IgnorePointer(
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.6 + 0.4 * grow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppText.display.copyWith(
                  fontSize: 30,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(
                      color: Color.lerp(color, Colors.black, 0.5)!,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
              if (award > 0)
                Text(
                  '+$award puan',
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: kTabularFigures,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tahtanın altındaki satır: durum metni ve "Baştan al".
///
/// Sıkışınca metin uyarıya döner ve düğme dolu hâle geçer; bu türde
/// oyuncu kalan kareye ulaşamayacağını her zaman kendisi fark etmiyor.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.controller, required this.onRestart});

  final RailLayController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final stuck = controller.isStuck;
    final firstMove = controller.moves == 0 && controller.levelsCleared == 0;
    final message = stuck
        ? 'Sıkıştın — bölümü baştan al'
        : firstMove
        ? 'Kaydır: metro duvara kadar gider'
        : '${controller.paintedCount} / ${controller.openCount} kare döşendi';
    final canRestart =
        controller.status == GameStatus.playing &&
        !controller.isCelebrating &&
        controller.paintedCount > 1;
    const buttonSize = Size(0, 40);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: stuck ? AppColors.warning : AppColors.textSecondary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        stuck
            ? FilledButton.icon(
                onPressed: canRestart ? onRestart : null,
                style: FilledButton.styleFrom(
                  minimumSize: buttonSize,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('BAŞTAN AL'),
              )
            : OutlinedButton.icon(
                onPressed: canRestart ? onRestart : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: buttonSize,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('BAŞTAN AL'),
              ),
      ],
    );
  }
}
