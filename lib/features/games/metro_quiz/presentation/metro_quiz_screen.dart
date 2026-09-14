import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_progress.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/metro_quiz_controller.dart';
import '../application/quiz_pool.dart';
import '../domain/quiz_generator.dart';
import '../domain/quiz_question.dart';
import '../domain/quiz_rules.dart';

/// Metro Bilgi: dört şıklı soru, seri çarpanı, üç yanlış hakkı.
///
/// Düzen başparmağa göre: soru üstte **okunur**, şıklar altta **dokunulur**.
/// Hareket eden vagonda tek elle oynanacağı için dört şık da alt yarıda ve
/// her biri tam genişlikte.
class MetroQuizScreen extends StatefulWidget {
  const MetroQuizScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<MetroQuizScreen> createState() => _MetroQuizScreenState();
}

class _MetroQuizScreenState extends State<MetroQuizScreen>
    with WidgetsBindingObserver {
  MetroQuizController? _controller;
  AudioService? _audio;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  int _seenStreakMultiplier = 1;

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

    final controller = MetroQuizController(
      journey: widget.journey,
      store: scope.store,
      pool: QuizPool(
        generator: QuizGenerator(metro: scope.metro),
        trivia: scope.questions.questions(),
      ),
      recordToBeat: scope.store.bestScoreForGameRoute(
        gameId: MetroQuizController.id,
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

    // Çarpan yükseldiği anda ayrı bir geri bildirim: seri oyunun asıl
    // gerilimi, sessizce artarsa oyuncu fark etmiyor.
    if (controller.multiplier > _seenStreakMultiplier) {
      _haptic(HapticFeedback.mediumImpact);
      _sound(GameSound.combo);
    }
    _seenStreakMultiplier = controller.multiplier;

    if (controller.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      _sound(GameSound.arrival);
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
    super.dispose();
  }

  bool get _hapticsEnabled => AppScope.of(context).store.hapticsEnabled;

  void _haptic(void Function() effect) {
    if (_hapticsEnabled) effect();
  }

  void _sound(GameSound sound) => AppScope.of(context).audio.play(sound);

  void _answer(int index) {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.answer(index)) return;

    if (controller.lastAnswerCorrect) {
      _haptic(HapticFeedback.lightImpact);
      _sound(GameSound.clear);
    } else {
      _haptic(HapticFeedback.vibrate);
      _sound(GameSound.invalid);
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
                      chips: <Widget>[
                        if (controller.multiplier > 1)
                          _MultiplierChip(
                            multiplier: controller.multiplier,
                            accent: accent,
                          ),
                        _LivesChip(left: controller.livesLeft),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      // Kart yukarı yaslı: göz HUD → soru → şıklar sırasını
                      // takip etsin. Ortalanınca kısa sorularda kart ekranın
                      // ortasında asılı kalıyor, uzun sorularda aşağı
                      // kayıyordu; okuma sırası her soruda değişiyordu.
                      child: Column(
                        children: <Widget>[
                          Flexible(
                            child: SingleChildScrollView(
                              child: _QuestionCard(controller: controller),
                            ),
                          ),
                          // Kart ile şıklar arasındaki boşluk seriye ayrıldı:
                          // oyunun asıl gerilimi bu, ama sayı olarak hiçbir
                          // yerde durmuyordu.
                          Expanded(
                            child: Center(
                              child: _StreakMeter(
                                controller: controller,
                                accent: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Options(controller: controller, onAnswer: _answer),
                    const SizedBox(height: AppSpacing.md),
                    JourneyProgressBar(
                      lineId: journey.lineId,
                      originName: journey.origin.name,
                      destinationName: journey.destination.name,
                      progress: controller.progress,
                      remainingSeconds: controller.remainingSeconds,
                      nextStopName: _nextStopName(controller),
                      accent: accent,
                      isMoving: controller.status == GameStatus.playing,
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
                lineId: journey.lineId,
                stationName: journey.destination.name,
                child: _buildResult(controller, accent, showBackdrop: false),
              )
            else if (controller.status == GameStatus.gameOver)
              _buildResult(controller, accent),
            SprintBanner(pulse: controller.sprintPulse),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(
    MetroQuizController controller,
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
        StatRow(label: 'Doğru cevap', value: '${controller.correctCount}'),
        StatRow(label: 'En uzun seri', value: '${controller.bestStreak}'),
      ],
      gameOverTitle: 'Üç yanlış oldu',
      gameOverSubtitle:
          'Yolculuk bitmeden üç soruyu kaçırdın. Durağına varmak için '
          'üçten fazla yanlış yapmaman gerekiyor.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      showBackdrop: showBackdrop,
    );
  }

  String? _nextStopName(MetroQuizController controller) {
    final journey = controller.journey;
    final stops = journey.stopCount;
    if (stops <= 0) return null;
    final passed = (controller.progress * stops).floor();
    if (passed >= stops) return null;
    final stations = AppScope.of(context).metro.stationsOfLine(journey.lineId);
    final originIndex = stations.indexWhere((s) => s.id == journey.origin.id);
    if (originIndex < 0) return null;
    final step = journey.destination.order > journey.origin.order ? 1 : -1;
    final index = originIndex + step * (passed + 1);
    if (index < 0 || index >= stations.length) return null;
    return stations[index].name;
  }
}

/// Soru kartı: bağlam etiketi, soru metni ve süre çubuğu.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.controller});

  final MetroQuizController controller;

  @override
  Widget build(BuildContext context) {
    final question = controller.question;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.surfaceHigh, width: 1.6),
      ),
      // Kart **içeriği kadar** yer kaplar; artan boşluk kartın üstüne ve
      // altına eşit dağılır. Kartı ekrana yaydığımızda üç satırlık soru
      // devasa bir boş kutunun ortasında kalıyordu.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Süre çubuğu kartın tepesinde: sayı okumak gerekmeden, göz ucuyla
          // "ne kadar kaldı" görülüyor.
          _TimerBar(progress: controller.questionProgress),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (question.context != null)
                      Text(
                        question.context!.toUpperCase(),
                        style: AppText.micro.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      question.topic == QuizTopic.trivia
                          ? 'BİLGİ'
                          : 'AĞ BİLGİSİ',
                      style: AppText.micro,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  question.prompt,
                  style: AppText.lead.copyWith(fontSize: 20, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // Renk **hattan bağımsız**: hat rengi kimliktir, durum değil. M1A'da
    // çubuk hat kırmızısıyla çizilince dolu çubuk "süren bitiyor" gibi
    // okunuyordu. Normalde nötr, son çeyrekte uyarı rengi.
    final color = progress < 0.25 ? AppColors.danger : AppColors.textSecondary;
    return SizedBox(
      height: 5,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: (progress * 1000).round().clamp(0, 1000),
            child: ColoredBox(color: color),
          ),
          Expanded(
            flex: 1000 - (progress * 1000).round().clamp(0, 1000),
            child: const ColoredBox(color: AppColors.surfaceHigh),
          ),
        ],
      ),
    );
  }
}

/// Dört şık. Cevaptan sonra doğru yeşil, seçilen yanlış kırmızı olur.
class _Options extends StatelessWidget {
  const _Options({required this.controller, required this.onAnswer});

  final MetroQuizController controller;
  final ValueChanged<int> onAnswer;

  @override
  Widget build(BuildContext context) {
    final question = controller.question;
    final revealing = controller.isRevealing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < question.options.length; i++) ...<Widget>[
          _OptionButton(
            label: question.options[i],
            // Cevaplandıktan sonra doğru şık her hâlükârda gösterilir:
            // oyuncu yanlış yaptıysa doğrusunu öğrenmeden geçmemeli.
            state: !revealing
                ? _OptionState.idle
                : i == question.answerIndex
                ? _OptionState.correct
                : i == controller.chosenIndex
                ? _OptionState.wrong
                : _OptionState.dimmed,
            onTap: revealing || controller.status != GameStatus.playing
                ? null
                : () => onAnswer(i),
          ),
          if (i < question.options.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color border, Color text) = switch (state) {
      _OptionState.idle => (
        AppColors.surfaceHigh,
        AppColors.outline,
        AppColors.textPrimary,
      ),
      _OptionState.correct => (
        AppColors.success.withValues(alpha: 0.20),
        AppColors.success,
        AppColors.textPrimary,
      ),
      _OptionState.wrong => (
        AppColors.danger.withValues(alpha: 0.18),
        AppColors.danger,
        AppColors.textPrimary,
      ),
      _OptionState.dimmed => (
        AppColors.surface,
        AppColors.surfaceHigh,
        AppColors.textMuted,
      ),
    };

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        // Şık yüksekliği 56: hareket eden vagonda 48 bile ıskalanıyor.
        constraints: const BoxConstraints(minHeight: 56),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodyStrong.copyWith(color: text),
        ),
      ),
    );
  }
}

/// Seri göstergesi: kaç doğru gitti, bir sonraki çarpana kaç kaldı.
///
/// Seri sıfırken hiçbir şey çizmez — oyunun sessiz hâli, boş bir kutu
/// göstermekten iyidir.
class _StreakMeter extends StatelessWidget {
  const _StreakMeter({required this.controller, required this.accent});

  final MetroQuizController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final streak = controller.streak;
    if (streak == 0) return const SizedBox.shrink();

    final remaining = controller.answersToNextMultiplier;
    final multiplier = controller.multiplier;

    return Semantics(
      label: remaining == null
          ? 'Seri $streak, çarpan $multiplier kat, en üst basamak'
          : 'Seri $streak, $remaining doğru sonra çarpan artıyor',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < streak.clamp(0, 10); i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              remaining == null
                  ? 'SERİ $streak · ×$multiplier'
                  : multiplier > 1
                  ? 'SERİ $streak · ×$multiplier · $remaining doğru sonra artıyor'
                  : 'SERİ $streak · $remaining doğru sonra ×2',
              textAlign: TextAlign.center,
              style: AppText.micro.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seri çarpanı rozeti.
class _MultiplierChip extends StatelessWidget {
  const _MultiplierChip({required this.multiplier, required this.accent});

  final int multiplier;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Seri çarpanı $multiplier kat',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.bolt_rounded, size: 15, color: accent),
              const SizedBox(width: 2),
              Text(
                'x$multiplier',
                style: AppText.statSmall.copyWith(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kalan yanlış hakkı.
class _LivesChip extends StatelessWidget {
  const _LivesChip({required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kalan yanlış hakkı $left',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < QuizRules.mistakeAllowance; i++)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < left
                        ? AppColors.textSecondary
                        : Colors.transparent,
                    border: Border.all(
                      color: i < left
                          ? AppColors.textSecondary
                          : AppColors.outline,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
