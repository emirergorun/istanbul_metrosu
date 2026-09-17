import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../journey/models/journey.dart';
import '../../../journey/models/station.dart';
import '../../../journey/models/station_progress.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_progress.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/game_controller.dart';
import '../application/game_snapshot.dart';
import '../domain/board.dart';
import '../domain/clear_result.dart';
import '../domain/game_state.dart';
import '../domain/scoring.dart';
import '../../../session/widgets/arrival_sequence.dart';
import 'widgets/board_view.dart';
import '../../../session/widgets/pause_overlay.dart';
import 'widgets/piece_tray.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/result_overlay.dart';

/// Oyun ekranı.
///
/// Oyun kurallarını bilmez; [GameController] üzerinden okur ve hamle iletir.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.journey, this.resumeFrom});

  final Journey journey;

  /// Yarım kalan oyundan devam ediliyorsa oturumun kaydı.
  final SavedGame? resumeFrom;

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
  final ValueNotifier<BoardUndo?> _undoFx = ValueNotifier<BoardUndo?>(null);

  /// Geri alma geçişi; tahtanın bir anda eski hâline sıçramasını önler.
  late final AnimationController _undoController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: AppConstants.lineClearDuration,
  );
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Çok satırlı temizlikte tahtanın kısa dikey "vuruşu".
  ///
  /// Reddedilen hamlenin yatay sarsıntısından bilerek ayrı: o "olmadı"
  /// der, bu "güçlü vurdun" der. Tek satırda çalışmaz; her temizlikte
  /// sallanan tahta çabuk yorar.
  late final AnimationController _impactController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  double _impactStrength = 0;

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

  /// Durağa varış kutlaması: ray üzerindeki durak noktası büyür, halka atar.
  ///
  /// Bildirim şeridinden ayrı bir denetleyici: şerit 1,4 saniye durur ama
  /// ray kutlaması kısa olmalı — oyun akışını kesmemeli.
  late final AnimationController _arrivalPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  /// En son görülen durak sayısı; artışı varış olayı sayılır.
  int _seenStationsPassed = 0;

  /// Son varılan durak. Bildirim şeridi bunu gösterir.
  StationReachedEvent? _lastStationEvent;

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
      resumeFrom: widget.resumeFrom?.session,
      resumeProgress: widget.resumeFrom?.progress,
    );
    controller.addListener(_onControllerChanged);
    _controller = controller;

    // Kayıttan gelen oyun duraklatılmış açılır; kullanıcı "devam et" der.
    if (widget.resumeFrom == null) controller.start();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _showStationReachedIfNew();
    final status = _controller?.status;
    if (status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (status != GameStatus.arrived) {
      // "Tekrar oyna" aynı ekranı yeniden kullanır; bayrak sıfırlanmazsa
      // ikinci varışta kapı sesi çalmıyordu.
      _playedArrivalSound = false;
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

  /// Tren bir durak geçtiyse varışı kutla.
  ///
  /// Tetikleyici **durak sayısı**, bonus değil: bonus yalnızca o duraktan
  /// beri satır temizlendiyse geliyor, oysa durağın kendisi her hâlükârda
  /// geçiliyor. Eskiden bonussuz durak sessizce geçiyordu ve yolculuk
  /// ilerlemesi oyuncuya hiç görünmüyordu.
  ///
  /// Kutlama oyunu durdurmaz: ray üzerinde kısa bir nabız, üstte 1,4
  /// saniyelik bir şerit. Toplam kesinti bir saniyenin altında.
  void _showStationReachedIfNew() {
    final controller = _controller;
    if (controller == null) return;

    final passed = controller.stationsPassed;
    if (passed <= _seenStationsPassed) {
      // Yeniden başlatma sayacı sıfırlar.
      _seenStationsPassed = passed;
      return;
    }

    final previousCount = _seenStationsPassed;
    _seenStationsPassed = passed;

    final event = _stationEventFor(previousCount, passed);
    if (event == null) return;

    _lastStationEvent = event;
    _haptic(HapticFeedback.selectionClick);
    _sound(GameSound.station);

    _arrivalPulse.forward(from: 0);
    _stationBonusTimer?.cancel();
    _stationBonus.forward();
    _stationBonusTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) _stationBonus.reverse();
    });
  }

  /// Varış olayını yolculuk verisinden kurar.
  StationReachedEvent? _stationEventFor(int previousCount, int passed) {
    final controller = _controller;
    if (controller == null) return null;

    final journey = controller.journey;
    final stations = AppScope.of(context).metro.stationsOfLine(journey.lineId);
    if (stations.isEmpty) return null;

    final direction = journey.destination.order > journey.origin.order ? 1 : -1;
    Station? at(int index) {
      if (index < 0 || index > journey.stopCount) return null;
      final order = journey.origin.order + direction * index;
      for (final station in stations) {
        if (station.order == order) return station;
      }
      return null;
    }

    final reached = at(passed);
    if (reached == null) return null;

    return StationReachedEvent(
      previous: at(previousCount) ?? journey.origin,
      reached: reached,
      next: at(passed + 1),
      stationsPassed: passed,
      stopCount: journey.stopCount,
      // Bonus yalnızca o duraktan beri temizlik yapıldıysa verilir.
      bonusAwarded:
          controller.stationBonusPulse > 0 &&
              controller.lastStationBonus > 0 &&
              _bonusBelongsTo(passed)
          ? controller.lastStationBonus
          : 0,
    );
  }

  /// Controller'ın son bonusu **bu** durağa mı ait?
  ///
  /// Bonus ve durak geçişi aynı karede işleniyor; sayaç artmışsa bonus da
  /// bu durağındır.
  bool _bonusBelongsTo(int passed) => _controller?.stationsPassed == passed;

  /// Seri bu hamlede kopabilir mi?
  ///
  /// Açık tepside henüz temizlik yok ve tek parça kaldı: bu hamle seriyi
  /// ya sürdürür ya bitirir. Rozet o an uyarı rengine döner.
  bool _streakAtRisk(GameSession session) {
    final streak = session.streakState;
    return streak.value >= 1 &&
        !streak.clearedInSet &&
        streak.piecesLeftInSet <= 1;
  }

  /// Yolculuğun durak düzeyindeki hâli — ilerleme çubuğu bunu gösterir.
  StationProgress? _stationProgress(GameController controller) {
    final journey = controller.journey;
    return stationProgressFor(
      journey: journey,
      lineStations: AppScope.of(context).metro.stationsOfLine(journey.lineId),
      progress: controller.progress,
    );
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
    _arrivalPulse.dispose();
    _flashController.dispose();
    _undoController.dispose();
    _undoFx.dispose();
    _shakeController.dispose();
    _impactController.dispose();
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
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      _flash.value = BoardFlash(
        rows: outcome.clearedRows,
        columns: outcome.clearedColumns,
        cellValues: outcome.clearedCellValues,
        // Dalga parçanın ortasından başlar.
        originRow: target.row + (data.piece.height - 1) / 2,
        originCol: target.col + (data.piece.width - 1) / 2,
        points: outcome.gainedPoints,
        combo: outcome.combo,
        reduceMotion: reduceMotion,
      );
      _flashController.forward(from: 0);

      // Geri bildirim iki eksende birden büyür: hamlenin kademesi (aynı
      // anda kaç line) ve serinin sıcaklığı (combo). Uzun bir serinin tek
      // satırı da çift temizlik kadar kutlanmayı hak eder.
      final tier = outcome.tier;
      final isHotCombo = outcome.combo >= kComboPulseThreshold;

      if (!reduceMotion &&
          (tier.intensity >= ClearTier.double.intensity || isHotCombo)) {
        _impactStrength = tier.intensity * 1.6 + (isHotCombo ? 1.6 : 0);
        _impactController.forward(from: 0);
      }
      _haptic(
        tier.intensity >= ClearTier.double.intensity || isHotCombo
            ? HapticFeedback.heavyImpact
            : HapticFeedback.mediumImpact,
      );
      _sound(
        outcome.combo >= kComboSoundThreshold
            ? GameSound.combo
            : GameSound.clear,
      );
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

  /// Son hamleyi geri alır ve tahtayı eski hâline **geçişle** döndürür.
  void _undo() {
    final controller = _controller;
    if (controller == null) return;
    final before = controller.board;
    if (!controller.undo()) return;

    // Geri alınan hamle bir satır temizlediyse patlaması hâlâ çiziliyor
    // olabilir; geri gelen satırın üstünde patlama sürmemeli.
    _flashController.stop();
    _flash.value = null;
    _preview.value = null;

    _undoFx.value = BoardUndo(
      before: before,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    _undoController.forward(from: 0);
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
                    JourneyHud(
                      run: controller,
                      accent: accent,
                      onPause: controller.pause,
                      // HUD sırası: skor, sonra oyuna özgü rozetler.
                      // Combo ve streak yalnızca **varken** görünür; boş
                      // rozetler kalıcı gürültü olurdu.
                      chips: <Widget>[
                        if (session.combo >= 2)
                          ComboChip(
                            combo: session.combo,
                            graceLeft: session.comboState.graceLeft,
                            graceTotal: ScoreRules.comboGraceMoves,
                          ),
                        if (session.streak >= 1)
                          StreakChip(
                            streak: session.streak,
                            atRisk: _streakAtRisk(session),
                            piecesLeft: session.streakState.piecesLeftInSet,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(child: _buildPlayArea(controller, accent)),
                    const SizedBox(height: AppSpacing.sm),
                    // Geri al **aşağıda**, tepsinin hemen altında.
                    //
                    // Önce HUD'un sağ üst köşesindeydi: tek elle tutulan bir
                    // telefonda başparmağın en zor eriştiği nokta orası, oysa
                    // bu oyunun en sık basılan ikinci düğmesi. Duraklat
                    // yukarıda kaldı — o nadiren ve aceleyle basılmıyor.
                    //
                    // Kalan hak artık ipucu metninde değil düğmenin üstünde
                    // yazıyor: kaç hakkın kaldığını görmek için basılı
                    // tutmak gerekmiyor.
                    //
                    // Satır **her zaman** yerinde durur: hak bitince düğme
                    // soluk "0" gösterir, durak bonusu da aynı satırın
                    // solunda belirir. Önce hak bitince satır kalkıyor, bonus
                    // bildirimi de araya yeni satır ekliyordu; oyun alanı
                    // büyüyüp tahta aşağı kayıyordu.
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _StationPulse(
                            animation: _stationBonus,
                            accent: accent,
                            event: _lastStationEvent,
                          ),
                        ),
                        HudButton(
                          icon: Icons.undo_rounded,
                          tooltip: 'Geri al',
                          label: '${session.undoLeft}',
                          // Titreşimi `HudButton` veriyor; burada bir kez
                          // daha çağrılırsa geri alma iki kez titriyor.
                          onPressed: controller.canUndo ? _undo : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AnimatedBuilder(
                      animation: _arrivalPulse,
                      builder: (context, _) {
                        final stations = _stationProgress(controller);
                        return JourneyProgressBar(
                          lineId: journey.lineId,
                          stopCount: journey.stopCount,
                          originName: journey.origin.name,
                          destinationName: journey.destination.name,
                          progress: controller.progress,
                          remainingSeconds: controller.remainingSeconds,
                          nextStopName: stations?.approaching?.name,
                          stationProgress: stations,
                          arrivalPulse: _arrivalPulse.value,
                          accent: accent,
                          isMoving:
                              controller.status == GameStatus.playing &&
                              !controller.awaitingUndo,
                        );
                      },
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
            // Hamle kalmadı ama hak var: bitirmeden önce geri alma şansı.
            if (controller.status == GameStatus.playing &&
                controller.awaitingUndo)
              _UndoOffer(
                accent: accent,
                undoLeft: session.undoLeft,
                onUndo: _undo,
                onGiveUp: controller.acceptGameOver,
              ),
            // Rekoru geçme bildirimi — oyunu durdurmaz.
            _TargetBanner(animation: _targetBanner, accent: accent),

            // Sprint başladığında bir kez geçer; oyunu durdurmaz.
            SprintBanner(pulse: controller.sprintPulse),

            // Varış: oyunun finali. Tren gelir, kapılar açılır, sonuç çıkar.
            if (controller.status == GameStatus.arrived)
              ArrivalSequence(
                accent: accent,
                lineId: journey.lineId,
                stationName: journey.destination.name,
                child: _buildResult(controller, accent, showBackdrop: false),
              )
            // Hamle bitişi: tören yok, sade panel.
            else if (controller.status == GameStatus.gameOver)
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
      isArrival: controller.status == GameStatus.arrived,
      destinationName: session.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      // Blok oyununa özgü istatistikler; panel bunların ne olduğunu bilmez.
      //
      // Skor "ne kadar iyi oynadın"ı söyler; bunlar **nasıl** oynadığını.
      // Kırılan rekor satırın yanında işaretlenir: oyuncu düşük skorlu bir
      // koşuda bile en iyi serisini kurmuş olabilir.
      extraStats: <Widget>[
        StatRow(
          label: 'Geçilen durak',
          value:
              '${controller.stationsPassed} / ${session.journey.stopCount}'
              '${controller.runRecords.stations ? '  ★' : ''}',
          highlight: controller.runRecords.stations,
          accent: accent,
        ),
        StatRow(
          label: 'Temizlenen satır / sütun',
          value: '${session.clearedRows} / ${session.clearedColumns}',
        ),
        StatRow(
          label: 'En iyi combo',
          value: session.bestCombo > 0
              ? 'x${session.bestCombo}'
                    '${controller.runRecords.combo ? '  ★' : ''}'
              : '—',
          highlight: controller.runRecords.combo,
          accent: accent,
        ),
        StatRow(
          label: 'En iyi seri',
          value: session.bestStreak > 0
              ? '${session.bestStreak}'
                    '${controller.runRecords.streak ? '  ★' : ''}'
              : '—',
          highlight: controller.runRecords.streak,
          accent: accent,
        ),
      ],
      gameOverTitle: 'Hamle kalmadı',
      gameOverSubtitle: 'Tahtaya sığacak parça kalmadı, durağa varamadın.',
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
        // Alt sınır yok: sığmayan tahta **taşmak yerine küçülür**.
        //
        // Önce 24 pt'lik bir taban vardı; dokunma hedefini korumak içindi
        // ama yer olmadığında tabanı zorlamak taşmaya yol açıyordu ve
        // taşan tahtanın alt satırına hiç dokunulamıyordu. Küçük tahta,
        // erişilemeyen tahtadan iyidir.
        //
        // Desteklenen dikey ekranlarda hücre zaten 24 pt'nin üstünde
        // kalıyor; `screen_sizes_test` bunu koruyor. Bu dal yalnızca
        // bölünmüş ekran gibi alışılmadık yükseklerde devreye giriyor.
        _cellSize = math.max(1, math.min(byWidth, byHeight));

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
                    enabled:
                        controller.status == GameStatus.playing &&
                        !controller.awaitingUndo,
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
      undo: _undoFx,
      undoAnimation: _undoController,
    );

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _shakeController,
        _impactController,
      ]),
      builder: (context, child) {
        // Geçersiz bırakma: kısa yatay sarsıntı.
        final t = _shakeController.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
        // Çok satırlı temizlik: sönümlenen dikey vuruş.
        final i = _impactController.value;
        final dy = i == 0 || i == 1
            ? 0.0
            : math.sin(i * math.pi * 3) * _impactStrength * (1 - i);
        return Transform.translate(offset: Offset(dx, dy), child: child);
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
}

/// Hamle kalmadığında, geri alma hakkı varsa açılan panel.
class _UndoOffer extends StatelessWidget {
  const _UndoOffer({
    required this.accent,
    required this.undoLeft,
    required this.onUndo,
    required this.onGiveUp,
  });

  final Color accent;
  final int undoLeft;
  final VoidCallback onUndo;
  final VoidCallback onGiveUp;

  @override
  Widget build(BuildContext context) {
    return OverlayPanel(
      icon: Icons.undo_rounded,
      accent: accent,
      title: 'Hamle kalmadı',
      subtitle:
          'Tahtaya sığacak parça yok. Son hamleni geri alıp farklı '
          'oynayabilirsin.',
      children: <Widget>[
        StatRow(label: 'Kalan geri alma', value: '$undoLeft'),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: AppFeedback.onTap(context, onUndo),
          child: const Text('SON HAMLEYİ GERİ AL'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: AppFeedback.onTap(context, onGiveUp),
          child: const Text('Oyunu bitir'),
        ),
      ],
    );
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
                  style: AppText.bodyStrong.copyWith(color: Colors.white),
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
/// Durağa varış bildirimi — ilerleme çubuğunun üstünde kısa süre belirir.
///
/// Durak adını her varışta gösterir; bonus kazanıldıysa onu da ekler.
/// Yalnızca bonus gösterilseydi bonussuz duraklar sessizce geçerdi ve
/// yolculuk ilerlemesi oyuncunun gözünden kaçardı.
class _StationPulse extends StatelessWidget {
  const _StationPulse({
    required this.animation,
    required this.accent,
    required this.event,
  });

  final Animation<double> animation;
  final Color accent;
  final StationReachedEvent? event;

  @override
  Widget build(BuildContext context) {
    final reached = event;
    if (reached == null) return const SizedBox.shrink();

    final bonus = reached.bonusAwarded;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        if (t == 0) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          ),
        );
      },
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
            Icon(Icons.trip_origin_rounded, size: 15, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                bonus > 0
                    ? '${reached.reached.name} · +$bonus'
                    : reached.reached.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
