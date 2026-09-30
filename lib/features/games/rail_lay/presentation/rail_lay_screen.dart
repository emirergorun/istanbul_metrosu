import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/game_control_button.dart';
import '../../../../core/widgets/line_badge.dart';
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
              // Sahne atmosfer, oyun değil: karartılır ki gözü tahta alsın.
              // Kule ve gün batımı seçilir kalır ama tahtayla yarışmaz.
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.background.withValues(alpha: 0.55),
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
                              ),
                              const SizedBox(height: AppSpacing.stack),
                              _LevelHeader(
                                level: controller.levelNumber,
                                line: line,
                                painted: controller.paintedCount,
                                open: controller.openCount,
                              ),
                              const SizedBox(height: AppSpacing.stack),
                              Expanded(
                                child: _RailLayPlayArea(
                                  controller: controller,
                                  lineColor: line.color,
                                  onPanStart: _handlePanStart,
                                  onPanUpdate: _handlePanUpdate,
                                  onPanEnd: _handlePanEnd,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.stack),
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

/// Bölüm başlığı: tek satır, kutusuz. Solda bölümün hattı ve numarası,
/// sağda döşenen kare sayacı.
///
/// Hat rozeti bölümün **kendi** hattının renginde (yolculuğun değil):
/// raylar da o renkte döşeniyor.
class _LevelHeader extends StatelessWidget {
  const _LevelHeader({
    required this.level,
    required this.line,
    required this.painted,
    required this.open,
  });

  final int level;
  final MetroLine line;
  final int painted;
  final int open;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        LineBadge(label: line.id, color: line.color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'BÖLÜM $level',
            maxLines: 1,
            style: AppText.label.copyWith(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          label: '$painted / $open kare döşendi',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '$painted',
                      style: AppText.stat.copyWith(fontSize: 24, height: 1.1),
                    ),
                    Text(
                      ' / $open',
                      style: AppText.statSmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                Text('KARE', style: AppText.micro),
              ],
            ),
          ),
        ),
      ],
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

/// Bölüm sonu: kısa, sakin bir onay ve kazanılan puan.
///
/// Dönen övgü listesi ("HARİKA!", "MÜKEMMEL!") ve gölgeli dev yazı yerine
/// Tünele Kaç'la aynı dil: tabela fontunda HAT AÇILDI, altında hat renginde
/// puan. Hafifçe yükselerek belirir, sonda solar; zıplama yok.
class _Celebration extends StatelessWidget {
  const _Celebration({
    required this.progress,
    required this.award,
    required this.color,
  });

  final double progress;
  final int award;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rise = Curves.easeOutCubic.transform((progress * 4).clamp(0.0, 1.0));
    final fade = progress > 0.75 ? (1 - progress) / 0.25 : rise;
    return IgnorePointer(
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - rise)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'HAT AÇILDI',
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(height: 1.05),
              ),
              if (award > 0)
                Text(
                  '+$award puan',
                  style: AppText.captionStrong.copyWith(
                    color: LineTheme.from(color).accent,
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

/// Tahtanın altındaki satır: yalnız gerektiğinde bir cümle ve "Baştan".
///
/// İlerleme başlıktaki sayaçta; burada yalnız ilk bölümün ipucu ya da
/// sıkışma uyarısı konuşur. Sıkışınca uyarı rengine döner ve "Baştan"
/// ailenin öndeki denetimi olur — oyuncu kalan kareye ulaşamayacağını her
/// zaman kendisi fark etmiyor.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.controller, required this.onRestart});

  final RailLayController controller;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final stuck = controller.isStuck;
    final firstMove = controller.moves == 0 && controller.levelsCleared == 0;
    final message = stuck
        ? 'Sıkıştın: bölümü baştan al'
        : firstMove
        ? 'Kaydır: metro duvara kadar gider'
        : null;
    final canRestart =
        controller.status == GameStatus.playing &&
        !controller.isCelebrating &&
        controller.paintedCount > 1;
    return Row(
      children: <Widget>[
        Expanded(
          child: message == null
              ? const SizedBox.shrink()
              : Text(
                  message,
                  maxLines: 2,
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: stuck ? AppColors.warning : AppColors.textSecondary,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 88,
          child: GameControlButton(
            glyph: GameControlGlyph.restart,
            label: 'Baştan',
            semanticLabel: 'Bölümü baştan al',
            emphasis: stuck,
            onTap: canRestart ? onRestart : null,
          ),
        ),
      ],
    );
  }
}
