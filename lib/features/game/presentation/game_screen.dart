import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/audio/audio_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../journey/models/journey.dart';
import '../../progress/journey_progress.dart';
import '../application/game_controller.dart';
import '../domain/board.dart';
import '../domain/game_state.dart';
import 'widgets/arrival_sequence.dart';
import 'widgets/board_view.dart';
import 'widgets/game_hud.dart';
import 'widgets/pause_overlay.dart';
import 'widgets/piece_tray.dart';
import 'widgets/result_overlay.dart';

/// Oyun ekranı.
///
/// Oyun kurallarını bilmez; [GameController] üzerinden okur ve hamle iletir.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.journey, this.resumeFrom});

  final Journey journey;

  /// Yarım kalan oyundan devam ediliyorsa oturumun kaydı.
  final GameSession? resumeFrom;

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

  /// "Hedefi geçtin" şeridi: iner, bekler, kalkar. Oyunu durdurmaz.
  late final AnimationController _targetBanner = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Timer? _targetBannerTimer;

  /// Durak bonusu bildirimi — ilerleme çubuğunun üstünde kısa süre belirir.
  late final AnimationController _stationBonus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Timer? _stationBonusTimer;
  int _seenStationPulse = 0;

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

    final store = AppScope.of(context).store;
    // dispose sırasında AppScope'a erişmek güvenli değil; referansı şimdi al.
    _audio = AppScope.of(context).audio;
    final controller = GameController(
      journey: widget.journey,
      store: store,
      recordToBeat: store.bestScoreForRoute(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      resumeFrom: widget.resumeFrom,
    );
    controller.addListener(_onControllerChanged);
    _controller = controller;

    // Kayıttan gelen oyun duraklatılmış açılır; kullanıcı "devam et" der.
    if (widget.resumeFrom == null) controller.start();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _showStationBonusIfNew();
    if (_controller?.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    }
    _syncMusic();
    setState(() {});
  }

  bool _playedArrivalSound = false;

  AudioService? _audio;

  /// Müziğin en son hangi duruma göre ayarlandığı.
  ///
  /// `_onControllerChanged` saniyede bir tetikleniyor; player'a her saniye
  /// `resume()` göndermemek için yalnızca durum değişince iş yapılır.
  GameStatus? _musicSyncedFor;

  /// Müziği oyunun durumuyla eşitler.
  ///
  /// Oynarken çalar, duraklatınca kaldığı yerde bekler, oyun bitince
  /// (varış ya da hamle bitişi) susar — varış sesi temiz duyulsun.
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

  /// Controller yeni bir durak bonusu verdiyse kısa bildirim göster.
  void _showStationBonusIfNew() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.stationBonusPulse == _seenStationPulse) return;

    _seenStationPulse = controller.stationBonusPulse;
    _haptic(HapticFeedback.selectionClick);
    _sound(GameSound.station);
    _stationBonusTimer?.cancel();
    _stationBonus.forward();
    _stationBonusTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) _stationBonus.reverse();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arka plana geçince oyun ve yolculuk sayacı durur; dönüşte kullanıcı
    // açıkça "devam et" demeli.
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
      // Oyun zaten bitmişse `pause()` erken döner ve müzik durumu
      // değişmez; müziği burada da susturuyoruz.
      _audio?.pauseMusic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Oyun ekranından çıkılıyor: müzik oyun ekranına ait, menülerde çalmaz.
    _audio?.stopMusic();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _targetBannerTimer?.cancel();
    _stationBonusTimer?.cancel();
    _stationBonus.dispose();
    _flashController.dispose();
    _shakeController.dispose();
    _targetBanner.dispose();
    _preview.dispose();
    _flash.dispose();
    super.dispose();
  }

  // --- Haptics ---

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  void _sound(GameSound sound) => AppScope.of(context).audio.play(sound);

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
      _sound(outcome.combo >= 2 ? GameSound.combo : GameSound.clear);
    } else {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.place);
    }

    if (outcome.beatRecord) _showRecordBanner();
  }

  /// Rekoru geçmek oyunu durdurmaz; kısa bir bildirimle geçilir.
  void _showRecordBanner() {
    _haptic(HapticFeedback.mediumImpact);
    _targetBannerTimer?.cancel();
    _targetBanner.forward();
    _targetBannerTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) _targetBanner.reverse();
    });
  }

  void _rejectPlacement() {
    _haptic(HapticFeedback.vibrate);
    _sound(GameSound.invalid);
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
    // Hat rengi kimlik taşır; koyu zeminde okunabilir varyantı kullanılır.
    final accent = line == null
        ? AppColors.success
        : LineTheme.from(line.color).accent;

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
                      recordToBeat: session.recordToBeat,
                      recordBeaten: session.recordBeaten,
                      isSprint: session.isSprint,
                      combo: session.combo,
                      recordProgress: session.recordProgress,
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
                    _StationBonusPulse(
                      animation: _stationBonus,
                      accent: accent,
                      amount: controller.lastStationBonus,
                    ),
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
                onSettings: () => AppRoutes.openSettings(context),
                onExit: _exitToHome,
              ),
            // Rekoru geçme bildirimi — oyunu durdurmaz.
            _TargetBanner(animation: _targetBanner, accent: accent),

            // Varış: oyunun finali. Tren gelir, kapılar açılır, sonuç çıkar.
            if (session.status == GameStatus.arrived)
              ArrivalSequence(
                accent: accent,
                lineId: journey.lineId,
                stationName: journey.destination.name,
                child: _buildResult(controller, accent, showBackdrop: false),
              )
            // Hamle bitişi: tören yok, sade panel.
            else if (session.status == GameStatus.gameOver)
              _buildResult(controller, accent),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(
    GameController controller,
    Color accent, {
    bool showBackdrop = true,
  }) {
    final session = controller.session;
    return ResultOverlay(
      session: session,
      accent: accent,
      bestScore: math.max(
        AppScope.of(context).store.bestScoreForRoute(
          session.journey.origin.id,
          session.journey.destination.id,
        ),
        session.score,
      ),
      isNewBest: controller.isNewBest,
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
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

        // Bırakma alanı board'dan büyüktür ve tepsiyi de kapsar.
        //
        // Parça parmağın üstünde gösterildiği için en alt satıra yerleştirmek,
        // parmağın board'un alt kenarının biraz altına inmesini gerektirir.
        // Hedef yalnızca board olsaydı orada `onLeave` tetiklenir ve bırakma
        // reddedilirdi — alt satır oynanamaz hale gelirdi.
        return DragTarget<TrayDragData>(
          onWillAcceptWithDetails: (details) {
            _updatePreview(details.offset, details.data);
            return true;
          },
          onMove: (details) => _updatePreview(details.offset, details.data),
          onLeave: (_) => _preview.value = null,
          onAcceptWithDetails: (details) =>
              _onDrop(details.offset, details.data),
          builder: (context, candidate, rejected) => Column(
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
                    onDragStarted: (_) =>
                        _haptic(HapticFeedback.selectionClick),
                    onDragEnded: () => _preview.value = null,
                  ),
                ),
              ),
            ],
          ),
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
        child: board,
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

/// "Rekoru geçtin" şeridi.
///
/// Rekoru geçmek oyunu bitirmez; tek final varıştır. Bu yüzden kutlama,
/// akışı kesmeyen kısa bir bildirim olarak gösterilir.
class _TargetBanner extends StatelessWidget {
  const _TargetBanner({required this.animation, required this.accent});

  final Animation<double> animation;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          if (t == 0) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -24),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Rekoru geçtin — durağına kadar devam',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Durak bonusu bildirimi.
///
/// İlerleme çubuğunun hemen üstünde belirir; oyuncu bonusun neden geldiğini
/// (bir durak geçildi) mekânsal olarak da anlasın diye oraya konumlandı.
class _StationBonusPulse extends StatelessWidget {
  const _StationBonusPulse({
    required this.animation,
    required this.accent,
    required this.amount,
  });

  final Animation<double> animation;
  final Color accent;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        if (t == 0) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.local_activity_rounded, size: 15, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Durak bonusu +$amount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
