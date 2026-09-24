import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/pressable.dart';
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
import '../application/escape_progress_controller.dart';
import '../application/tunnel_escape_controller.dart';
import '../domain/escape_level.dart';
import 'escape_board_view.dart';
import 'escape_complete_panel.dart';
import 'escape_level_map.dart';
import 'escape_widgets.dart';

/// Tünele Kaç'ın oyun ekranı — hat haritası ve tahta aynı ekranda.
///
/// Harita ile tahta **tek bir koşunun** iki yüzü: bölüm seçmek yolculuğu
/// durdurmaz, bölümden haritaya dönmek koşuyu bitirmez. Ekran kapanınca
/// koşu biter ([TunnelEscapeController.leave]).
class TunnelEscapeScreen extends StatefulWidget {
  const TunnelEscapeScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<TunnelEscapeScreen> createState() => _TunnelEscapeScreenState();
}

class _TunnelEscapeScreenState extends State<TunnelEscapeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  TunnelEscapeController? _controller;
  EscapeProgressController? _ownedProgress;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  bool _leaving = false;
  int _seenStationPulse = 0;
  EscapePhase? _seenPhase;

  Timer? _bannerTimer;
  String? _bannerText;
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
    // Uygulamada ilerleme tek ve rozetlerle paylaşılıyor; ekranı tek başına
    // kuran testlerde yerel bir kopya yeterli.
    final progress =
        scope.escapeProgress ??
        (_ownedProgress = EscapeProgressController(store: scope.store));
    final controller = TunnelEscapeController(
      journey: widget.journey,
      levelProgress: progress,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, TunnelEscapeController.id),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      session: JourneyScope.sessionFor(context, widget.journey),
    );
    controller.reporter = scope.runReporter;
    _seenStationPulse = controller.stationBonusPulse;
    _seenPhase = controller.phase;
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

    if (controller.phase != _seenPhase) {
      final entered = controller.phase;
      _seenPhase = entered;
      if (entered == EscapePhase.solved &&
          (controller.completion?.stars ?? 0) >= 3) {
        _sound(GameSound.combo);
      }
    }

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
    } else if (controller.status != GameStatus.arrived) {
      _playedArrivalSound = false;
    }

    _syncMusic();
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
    _ownedProgress?.dispose();
    _bannerTimer?.cancel();
    _bannerAnimation.dispose();
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

  /// Oyundan çık: koşu biter, galeriye dönülür.
  void _exit() {
    _leaving = true;
    _controller?.leave();
    Navigator.of(context).pop();
  }

  void _openLevel(int number) {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.openLevel(number)) {
      _haptic(HapticFeedback.lightImpact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final journey = controller.journey;
    final line = AppScope.of(context).metro.lineById(journey.lineId);
    final accent = line == null
        ? AppColors.success
        : LineTheme.from(line.color).accent;

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final inLevel = controller.phase != EscapePhase.map;
        return PopScope(
          // Bölümdeyken geri hareketi haritaya döner; haritadan geri çıkış.
          canPop: !inLevel,
          onPopInvokedWithResult: (bool didPop, _) {
            if (didPop) {
              _leaving = true;
              controller.leave();
            } else {
              controller.showMap();
            }
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        JourneyHud(
                          run: controller,
                          accent: accent,
                          onPause: controller.pause,
                          gameScore: controller.scoreThisGame,
                        ),
                        const SizedBox(height: AppSpacing.stack),
                        Expanded(
                          child: inLevel
                              ? _LevelView(
                                  controller: controller,
                                  accent: accent,
                                  hapticsEnabled: _hapticsEnabled,
                                  onMoved: () => _sound(GameSound.place),
                                  onSolved: () {
                                    _haptic(HapticFeedback.mediumImpact);
                                    _sound(GameSound.clear);
                                  },
                                )
                              : _MapView(
                                  controller: controller,
                                  onOpen: _openLevel,
                                  onExit: _exit,
                                ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        JourneyStatusBar(
                          gameId: TunnelEscapeController.id,
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
                    onRestart: () {
                      controller.resume();
                      controller.restartLevel();
                    },
                    onSettings: () => AppRoutes.openSettings(context),
                    onExit: _exit,
                  ),
                if (controller.status == GameStatus.arrived)
                  ArrivalSequence(
                    accent: accent,
                    onSkipped: () => AppScope.of(context).audio.stopLongForm(),
                    lineId: journey.lineId,
                    stationName: journey.destination.name,
                    child: _buildResult(controller, accent),
                  ),
                SprintBanner(pulse: controller.sprintPulse),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResult(TunnelEscapeController controller, Color accent) {
    // Çıkış sırasında koşu "bitti" sayılıyor; o an ekran zaten kapanıyor,
    // panel bir kare bile görünmemeli.
    if (_leaving) return const SizedBox.shrink();
    return ResultOverlay(
      journey: controller.journey,
      gameId: TunnelEscapeController.id,
      isArrival: true,
      discovery: controller.discovery,
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
          label: 'Bitirilen bölüm',
          value: '${controller.levelsSolvedThisRun}',
        ),
        StatRow(label: 'Toplanan yıldız', value: '${controller.starsThisRun}'),
      ],
      onRestart: controller.restart,
      onExit: _exit,
      showBackdrop: false,
    );
  }
}

/// Harita yüzü: başlık, hat haritası ve sıradaki bölüme tek dokunuş.
class _MapView extends StatelessWidget {
  const _MapView({
    required this.controller,
    required this.onOpen,
    required this.onExit,
  });

  final TunnelEscapeController controller;
  final ValueChanged<int> onOpen;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final progress = controller.levelProgress;
    return ListenableBuilder(
      listenable: progress,
      builder: (BuildContext context, _) {
        final count = controller.levels.length;
        final done = progress.completedCount;
        final next = progress.nextLevel(count);
        final allDone = done >= count;
        final station = EscapeStation.of(next, AppScope.of(context).metro);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                _BackButton(semanticLabel: 'Oyundan çık', onTap: onExit),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('TÜNELE KAÇ', style: AppText.tileTitle),
                      Text(
                        '$done/$count bölüm · ${progress.totalStars} yıldız',
                        style: AppText.caption.copyWith(
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: EscapeLevelMap(
                progress: progress,
                levelCount: count,
                onOpen: onOpen,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              button: true,
              label: allDone
                  ? 'Bölüm $next, ${station.name}, tekrar oyna'
                  : 'Bölüm $next, ${station.name}, başla',
              child: ExcludeSemantics(
                child: FilledButton(
                  onPressed: AppFeedback.onTap(context, () => onOpen(next)),
                  child: Text(
                    allDone ? 'BÖLÜM $next · TEKRAR' : 'BÖLÜM $next · BAŞLA',
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bölüm yüzü: başlık, tahta, denetimler ve tamamlanma paneli.
///
/// Hiyerarşi: önce oyun, sonra arayüz. Tahta kalan bütün yüksekliği alır;
/// başlık tek satır, denetimler kutusuz tek sıra. Bölüm bitince panel
/// denetimlerin yerine oturur, tahta arkada kararır.
class _LevelView extends StatelessWidget {
  const _LevelView({
    required this.controller,
    required this.accent,
    required this.hapticsEnabled,
    required this.onMoved,
    required this.onSolved,
  });

  final TunnelEscapeController controller;
  final Color accent;
  final bool hapticsEnabled;
  final VoidCallback onMoved;
  final VoidCallback onSolved;

  @override
  Widget build(BuildContext context) {
    final level = controller.level!;
    final station = EscapeStation.of(level.number, AppScope.of(context).metro);
    final completion = controller.completion;
    final solved = controller.phase == EscapePhase.solved && completion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _LevelHeader(
          level: level,
          station: station,
          moves: controller.moves,
          onMap: controller.showMap,
        ),
        const SizedBox(height: AppSpacing.stack),
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: EscapeBoardView(
                        controller: controller,
                        hapticsEnabled: hapticsEnabled,
                        onMoved: onMoved,
                        onSolved: onSolved,
                        teachIdleHints: level.number <= 3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stack),
                    _Controls(controller: controller),
                  ],
                ),
              ),
              if (solved) ...<Widget>[
                const Positioned.fill(child: _SolvedScrim()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EscapeCompletePanel(
                    key: ValueKey<int>(completion.level.number),
                    completion: completion,
                    accent: station.color,
                    onNext: controller.openNext,
                    onReplay: controller.replay,
                    onMap: controller.showMap,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bölüm bitince tahtayı karartan perde: göz panele gitsin, tahta yine de
/// arkada seçilsin. Dokunuşları yutar.
class _SolvedScrim extends StatelessWidget {
  const _SolvedScrim();

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AbsorbPointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: instant ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (BuildContext context, double t, _) =>
            ColoredBox(color: AppColors.background.withValues(alpha: 0.62 * t)),
      ),
    );
  }
}

/// Bölüm başlığı: tek satır. Solda haritaya dönüş, ortada bölüm ve durak,
/// sağda hamle sayacı.
///
/// Bölüm numarası tabela fontunda ve durağın hat renginde — oyunun
/// kimliği orada. Geri kalan her şey gövde fontunda; yazıların hiçbiri
/// logo gibi bağırmıyor.
class _LevelHeader extends StatelessWidget {
  const _LevelHeader({
    required this.level,
    required this.station,
    required this.moves,
    required this.onMap,
  });

  final EscapeLevel level;
  final EscapeStation station;
  final int moves;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _BackButton(semanticLabel: 'Hat haritasına dön', onTap: onMap),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'BÖLÜM ${level.number}',
                style: AppText.label.copyWith(color: station.color),
              ),
              const SizedBox(height: 2),
              Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.lead,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _MoveCounter(moves: moves, threeStarMoves: level.threeStarMoves),
      ],
    );
  }
}

/// Hamle sayacı: büyük sayı, altında üç yıldızın sınırı.
class _MoveCounter extends StatelessWidget {
  const _MoveCounter({required this.moves, required this.threeStarMoves});

  final int moves;
  final int threeStarMoves;

  @override
  Widget build(BuildContext context) {
    // Canlı bölge yalnız sayı: her hamlede ekran okuyucu kısa bir şey
    // söylesin. Yıldız sınırı ayrı ve sessiz.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          label: '$moves hamle',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '$moves',
                  style: AppText.stat.copyWith(fontSize: 24, height: 1.1),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('HAMLE', style: AppText.micro),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Semantics(
          label: 'Üç yıldız için en fazla $threeStarMoves hamle',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const EscapeStarRow(count: 3, size: 10, gap: 1),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$threeStarMoves',
                  style: AppText.caption.copyWith(
                    fontFeatures: kTabularFigures,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tahtanın altındaki denetim sırası: geri al, ipucu, baştan.
class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final TunnelEscapeController controller;

  @override
  Widget build(BuildContext context) {
    final playing = controller.acceptsInput;
    return Row(
      children: <Widget>[
        Expanded(
          child: EscapeControlButton(
            glyph: EscapeControlGlyph.undo,
            label: 'Geri al',
            semanticLabel: 'Son hamleyi geri al',
            emphasis: true,
            onTap: controller.canUndo ? controller.undo : null,
          ),
        ),
        Expanded(
          child: EscapeControlButton(
            glyph: EscapeControlGlyph.hint,
            label: 'İpucu',
            semanticLabel: 'Sıradaki hamleyi göster',
            busy: controller.isHintPending,
            onTap: playing && !controller.isHintPending
                ? controller.requestHint
                : null,
          ),
        ),
        Expanded(
          child: EscapeControlButton(
            glyph: EscapeControlGlyph.restart,
            label: 'Baştan',
            semanticLabel: 'Bölümü baştan başlat',
            onTap: playing && controller.moves > 0
                ? controller.restartLevel
                : null,
          ),
        ),
      ],
    );
  }
}

/// Geri düğmesi: kutusuz ok, 44 piksellik parmak alanı.
///
/// Sol kenara optik olarak hizalı: okun kendisi değil, dokunma alanı
/// kenarda başlar.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.semanticLabel, required this.onTap});

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-AppSpacing.sm, 0),
      child: Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        scale: 0.9,
        borderRadius: BorderRadius.circular(22),
        child: const SizedBox.square(
          dimension: 44,
          child: Icon(
            Icons.chevron_left_rounded,
            size: 32,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
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
    final value = text;
    if (value == null) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 72,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: animation,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: accent.withValues(alpha: 0.6)),
              ),
              child: Text(
                value,
                style: AppText.captionStrong.copyWith(color: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
