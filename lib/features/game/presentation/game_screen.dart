import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../journey/models/journey.dart';
import '../../progress/journey_progress.dart';
import '../application/game_controller.dart';
import '../domain/board.dart';
import '../domain/game_state.dart';
import 'widgets/board_view.dart';
import 'widgets/game_hud.dart';
import 'widgets/pause_overlay.dart';
import 'widgets/piece_tray.dart';
import 'widgets/result_overlay.dart';

/// Oyun ekranı.
///
/// Oyun kurallarını bilmez; [GameController] üzerinden okur ve hamle iletir.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  GameController? _controller;

  final GlobalKey _boardKey = GlobalKey();
  final ValueNotifier<BoardPreview?> _preview = ValueNotifier<BoardPreview?>(
    null,
  );
  final ValueNotifier<BoardFlash?> _flash = ValueNotifier<BoardFlash?>(null);

  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: AppConstants.lineClearDuration,
  );
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  double _cellSize = 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flashController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _flash.value = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final controller = GameController(
      journey: widget.journey,
      store: AppScope.of(context).store,
    );
    controller.addListener(_onControllerChanged);
    _controller = controller;
    controller.start();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arka plana geçince oyun ve yolculuk sayacı durur; dönüşte kullanıcı
    // açıkça "devam et" demeli.
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _flashController.dispose();
    _shakeController.dispose();
    _preview.dispose();
    _flash.dispose();
    super.dispose();
  }

  // --- Haptics ---

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  // --- Drag & drop ---

  /// Feedback widget'ının global sol-üst köşesinden board hücresini bulur.
  ({int row, int col})? _cellFromGlobal(Offset globalTopLeft) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalTopLeft);
    return (
      row: (local.dy / _cellSize).round(),
      col: (local.dx / _cellSize).round(),
    );
  }

  void _updatePreview(Offset globalTopLeft, TrayDragData data) {
    final controller = _controller;
    if (controller == null) return;

    final target = _cellFromGlobal(globalTopLeft);
    if (target == null) return;

    _preview.value = BoardPreview(
      piece: data.piece,
      row: target.row,
      col: target.col,
      isValid: canPlace(controller.board, data.piece, target.row, target.col),
    );
  }

  void _onDrop(Offset globalTopLeft, TrayDragData data) {
    final controller = _controller;
    _preview.value = null;
    if (controller == null) return;

    final target = _cellFromGlobal(globalTopLeft);
    if (target == null) {
      _rejectPlacement();
      return;
    }

    final outcome = controller.place(data.index, target.row, target.col);
    if (!outcome.accepted) {
      _rejectPlacement();
      return;
    }

    if (outcome.didClear) {
      _flash.value = BoardFlash(
        rows: outcome.clearedRows,
        columns: outcome.clearedColumns,
      );
      _flashController.forward(from: 0);
      _haptic(
        outcome.linesCleared >= 2
            ? HapticFeedback.heavyImpact
            : HapticFeedback.mediumImpact,
      );
    } else {
      _haptic(HapticFeedback.lightImpact);
    }
  }

  void _rejectPlacement() {
    _haptic(HapticFeedback.vibrate);
    _shakeController.forward(from: 0);
  }

  // --- Aksiyonlar ---

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

    final scope = AppScope.of(context);
    final session = controller.session;
    final journey = session.journey;
    final line = scope.metro.lineById(journey.lineId);
    final accent = line == null ? AppColors.success : Color(line.colorValue);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller?.abandon();
      },
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
                    GameHud(
                      score: session.score,
                      targetScore: session.targetScore,
                      combo: session.combo,
                      targetProgress: session.targetProgress,
                      accent: accent,
                      canUndo: controller.canUndo,
                      undoLeft: session.undoLeft,
                      onUndo: () {
                        if (controller.undo()) {
                          _haptic(HapticFeedback.selectionClick);
                        }
                      },
                      onPause: controller.pause,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(child: _buildPlayArea(controller, accent)),
                    const SizedBox(height: AppSpacing.md),
                    JourneyProgressBar(
                      lineId: journey.lineId,
                      originName: journey.origin.name,
                      destinationName: journey.destination.name,
                      progress: session.progress,
                      remainingSeconds: session.remainingSeconds,
                      nextStopName: _nextStopName(session),
                      accent: accent,
                      isMoving: session.status == GameStatus.playing,
                    ),
                  ],
                ),
              ),
            ),
            if (session.status == GameStatus.paused)
              PauseOverlay(
                accent: accent,
                score: session.score,
                remainingSeconds: session.remainingSeconds,
                onResume: controller.resume,
                onRestart: controller.restart,
                onExit: _exitToHome,
              ),
            if (session.status.isFinished)
              ResultOverlay(
                session: session,
                accent: accent,
                bestScore: math.max(
                  scope.store.bestScoreFor(journey.difficulty.id),
                  session.score,
                ),
                isNewBest: controller.isNewBest,
                onRestart: controller.restart,
                onExit: _exitToHome,
                onContinue: session.status == GameStatus.victory
                    ? controller.continueEndless
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayArea(GameController controller, Color accent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Board 8 hücre, tepsi ~2.6 hücre yüksekliğinde; ikisi arasında boşluk.
        const gap = AppSpacing.md;
        const trayFactor = AppConstants.trayHeightFactor;
        final byWidth = constraints.maxWidth / AppConstants.boardCols;
        final byHeight =
            (constraints.maxHeight - gap - 2) /
            (AppConstants.boardRows + trayFactor);
        _cellSize = math.max(24, math.min(byWidth, byHeight));

        final boardSize = _cellSize * AppConstants.boardCols;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _buildBoard(controller, boardSize),
            const SizedBox(height: gap),
            SizedBox(
              width: boardSize,
              child: TrayBackground(
                child: PieceTray(
                  pieces: controller.tray,
                  board: controller.board,
                  boardCellSize: _cellSize,
                  enabled: controller.status == GameStatus.playing,
                  onDragStarted: (_) => _haptic(HapticFeedback.selectionClick),
                  onDragEnded: () => _preview.value = null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoard(GameController controller, double boardSize) {
    final board = BoardView(
      key: _boardKey,
      board: controller.board,
      cellSize: _cellSize,
      preview: _preview,
      flash: _flash,
      flashAnimation: _flashController,
    );

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        // Geçersiz bırakma: kısa yatay sarsıntı.
        final t = _shakeController.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      // Not: board konteynerinde padding/border yok — drag koordinatlarının
      // hücrelere birebir oturması için render box tam olarak board boyutunda
      // olmalı.
      child: Container(
        width: boardSize,
        height: boardSize,
        decoration: BoxDecoration(
          color: AppColors.boardBackground,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: DragTarget<TrayDragData>(
          onWillAcceptWithDetails: (details) {
            _updatePreview(details.offset, details.data);
            return true;
          },
          onMove: (details) => _updatePreview(details.offset, details.data),
          onLeave: (_) => _preview.value = null,
          onAcceptWithDetails: (details) =>
              _onDrop(details.offset, details.data),
          builder: (context, candidate, rejected) => board,
        ),
      ),
    );
  }

  /// Yaklaşık "bir sonraki durak" — ilerleme oranından türetilir.
  /// Gerçek konum kullanılmaz.
  String? _nextStopName(GameSession session) {
    final journey = session.journey;
    final stops = journey.stopCount;
    if (stops <= 0) return null;

    final direction = journey.destination.order > journey.origin.order ? 1 : -1;
    final passed = (session.progress * stops).floor();
    final nextIndex = math.min(passed + 1, stops);
    final targetOrder = journey.origin.order + direction * nextIndex;

    for (final station in AppScope.of(context).metro.stations()) {
      if (station.lineId == journey.lineId && station.order == targetOrder) {
        return station.name;
      }
    }
    return null;
  }
}
