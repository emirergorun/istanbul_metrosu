import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/metro_train.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_host.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/journey_breakdown.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../../../../core/telemetry/analytics.dart';
import '../../../player/application/share_service.dart';
import '../application/metro_quiz_controller.dart';
import '../application/quiz_pool.dart';
import '../domain/quiz_rules.dart';
import '../domain/trivia_category.dart';
import 'category_glyph.dart';

/// Metro Bilgi: dört şıklı soru, seri çarpanı, üç yanlış hakkı.
///
/// **Okuma sırası** yukarıdan aşağı tek bir çizgi: skor ve kalan hak →
/// kategori → soru → dört şık. Kategori sorunun üstünde durur, çünkü
/// oyuncunun ilk kararı "bu neyle ilgili" — sorunun içinde saklı bir
/// etiket bu işi görmüyordu.
///
/// **Soru kartı ekranın gövdesidir.** Blok Metro'da tahta ne ise burada
/// kart odur: HUD ile şıklar arasında kalan alanın tamamını kaplar, metin
/// kendi içinde dikey ortalanır. Artan boşluk kartın *içinde* kalır ve
/// tabelanın nefesi gibi okunur; kartın *dışında* bırakılırsa ekranın
/// üçte biri boş bir leke oluyordu.
///
/// **Katman merdiveni** üç basamak: zemin ([AppColors.background]) en
/// koyu, dokunulacak şıklar ([AppColors.surface]) bir üstü, okunacak kart
/// ([AppColors.surfaceHigh]) en açık. Önce kart şıklardan koyuydu; soru
/// geride, şıklar önde duruyor ve hiyerarşi tersine dönüyordu.
class MetroQuizScreen extends StatefulWidget {
  const MetroQuizScreen({super.key, required this.journey});

  /// Soru kartı. Kart ile şıklar arasındaki boşluğu ölçen test bunu kullanır.
  @visibleForTesting
  static const Key questionCardKey = ValueKey<String>('quiz_question_card');

  /// Dört şıkkı taşıyan sütun.
  @visibleForTesting
  static const Key optionsKey = ValueKey<String>('quiz_options');

  final Journey journey;

  @override
  State<MetroQuizScreen> createState() => _MetroQuizScreenState();
}

class _MetroQuizScreenState extends State<MetroQuizScreen>
    with WidgetsBindingObserver {
  MetroQuizController? _controller;
  AudioService? _audio;

  /// Oyuncu konu seçmeden oyun başlamaz.
  ///
  /// Seçim ekranı tek dokunuşla geçilebilir: "Karışık" birincil eylem,
  /// kategoriler onun altında. Konu seçmek isteyen seçer, istemeyen
  /// akışta gecikmez.
  bool _started = false;
  GameStatus? _musicSyncedFor;
  bool _playedArrivalSound = false;
  bool _loggedOutcome = false;
  int _seenStreakMultiplier = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _begin(TriviaCategory? category) {
    if (_controller != null) return;
    final scope = AppScope.of(context);
    _audio = scope.audio;

    final controller = MetroQuizController(
      journey: widget.journey,
      store: scope.store,
      discovery: scope.discoveryFor(widget.journey, MetroQuizController.id),
      // Meydan okumada **soru sırası** tohumlanır, cevaplar değil.
      // Karekod hiçbir soruyu ve hiçbir doğru şıkkı taşımıyor; iki cihaz
      // aynı yerel soru havuzundan aynı sırayı türetiyor. Havuz farklı
      // sürümdeyse yükteki içerik sürümü bunu görünür kılar.
      pool: QuizPool(
        repository: scope.questions,
        onlyCategory: category,
        random: scope.challengeRandomFor(
          widget.journey,
          MetroQuizController.id,
        ),
      ),
      recordToBeat: scope.store.bestJourneyScore(
        widget.journey.origin.id,
        widget.journey.destination.id,
      ),
      // Yolculuk ortak: süren bir yolculuk varsa oyun onun içine girer —
      // puan, kalan süre ve geçilen duraklar oradan devam eder.
      session: JourneyScope.sessionOf(context),
    );
    // Biten koşu günlük görevlere ve pasaport başarımlarına buradan
    // ulaşıyor. Oyun hiçbirini tanımaz; tek bildiği bir rapor hedefi.
    controller.reporter = scope.runReporter;
    controller.addListener(_onControllerChanged);
    scope.analytics.log(
      AnalyticsEvent.gameStarted,
      params: <String, String>{
        'game': MetroQuizController.id,
        'kategori': category?.id ?? 'karisik',
      },
    );
    setState(() {
      _controller = controller;
      _started = true;
    });
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
      _logOutcome(AnalyticsEvent.journeyArrived);
    }
    if (controller.status == GameStatus.gameOver && !_loggedOutcome) {
      _logOutcome(AnalyticsEvent.gameOver);
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

  /// Şıkka dokunuldu.
  ///
  /// Çift dokunuş buradan geçmez: [MetroQuizController.answer] ikinci
  /// çağrıda `false` döner (soru artık cevap bekleme evresinde değil), bu
  /// yüzden ikinci dokunuş ne can götürür ne puan ekler. Ekran ayrıca
  /// cevaptan sonra [Pressable.onTap]'i boşaltır; iki koruma da gerekli,
  /// çünkü dokunuş ile yeniden çizim arasında bir kare geçebiliyor.
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

  void _useJoker() {
    if (_controller?.useJoker() ?? false) {
      _haptic(HapticFeedback.selectionClick);
    }
  }

  /// Yolculuğun sonucunu bir kez kaydeder.
  ///
  /// Denetleyici aynı durumu birden çok kez duyurabiliyor; sayaç
  /// şişmesin diye tek seferlik.
  void _logOutcome(AnalyticsEvent event) {
    if (_loggedOutcome) return;
    _loggedOutcome = true;
    AppScope.of(context).analytics.log(
      event,
      params: <String, String>{'game': MetroQuizController.id},
    );
  }

  void _exitToHome() {
    if (_controller?.status == GameStatus.playing) {
      _logOutcome(AnalyticsEvent.gameAbandoned);
    }
    _controller?.abandon();
    AppRoutes.exitToGallery(context);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_started || controller == null) {
      return _CategoryPicker(
        journey: widget.journey,
        onPick: _begin,
        onExit: () => Navigator.of(context).pop(),
      );
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
                      gameScore: controller.scoreThisGame,
                      chips: <Widget>[
                        if (controller.multiplier > 1)
                          _MultiplierReadout(
                            multiplier: controller.multiplier,
                            accent: accent,
                          ),
                        _LivesIndicator(left: controller.livesLeft),
                      ],
                      actions: <Widget>[
                        _JokerButton(
                          left: controller.jokersLeft,
                          enabled: controller.canUseJoker,
                          onTap: _useJoker,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            child: _QuestionCard(controller: controller),
                          ),
                          // Cevap gösterilirken not, oyun sürerken seri.
                          // İkisi aynı yerde: kartın altındaki tek satır
                          // her an bir şey söylüyor ama iki şey birden
                          // söylemiyor.
                          if (controller.isRevealing &&
                              controller.question.explanation !=
                                  null) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            _ExplanationLine(
                              text: controller.question.explanation!,
                            ),
                          ] else if (controller.streak > 0) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            _StreakLine(controller: controller, accent: accent),
                          ],
                        ],
                      ),
                    ),
                    // Sorudan şıklara tek sabit adım. Bu boşluk düzenin
                    // artığı değil, bilinçli bir değer.
                    const SizedBox(height: AppSpacing.lg),
                    _Options(controller: controller, onAnswer: _answer),
                    const SizedBox(height: AppSpacing.md),
                    JourneyStatusBar(
                      gameId: MetroQuizController.id,
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
      // Sosyal çıkış için rota ve oyun kimliği; panel meydan okuma
      // modunda karşılaştırma, normal koşuda davet gösteriyor.
      journey: controller.journey,
      gameId: MetroQuizController.id,
      isArrival: controller.status == GameStatus.arrived,
      discovery: controller.discovery,
      // Yolculuk ortaksa oyun bitişi bir ara duraktır, yolculuğun sonu değil.
      journeyContinues:
          controller.sharesJourney && controller.status != GameStatus.arrived,
      remainingSeconds: controller.remainingSeconds,
      destinationName: controller.journey.destination.name,
      score: controller.score,
      recordToBeat: controller.recordToBeat,
      isFirstRun: controller.isFirstRun,
      recordBeaten: controller.recordBeaten,
      accent: accent,
      isNewBest: controller.isNewBest,
      extraStats: <Widget>[
        // Varışta yolculuğun dağılımı: hangi oyunda ne kadar süre geçti,
        // ne kazandırdı. Oyunun kendi sayıları bunun altında.
        if (controller.status == GameStatus.arrived)
          ...journeyBreakdownRows(controller.journeySession),
        StatRow(label: 'Doğru cevap', value: '${controller.correctCount}'),
        StatRow(label: 'En uzun seri', value: '${controller.bestStreak}'),
        if (controller.bestCategory != null)
          StatRow(
            label: 'En iyi kategori',
            value: controller.bestCategory!.label,
          ),
      ],
      gameOverTitle: 'Üç yanlış oldu',
      gameOverSubtitle:
          'Yolculuk bitmeden üç soruyu kaçırdın. Durağına varmak için '
          'üçten fazla yanlış yapmaman gerekiyor.',
      onRestart: controller.restart,
      onExit: _exitToHome,
      onShare: () => ShareService.shareRun(
        analytics: AppScope.of(context).analytics,
        context: context,
        run: controller,
        journey: controller.journey,
        passedStops: controller.stationsPassed,
        gameName: 'Metro Bilgi',
        store: AppScope.of(context).store,
      ),
      showBackdrop: showBackdrop,
    );
  }
}

/// Soru kartı: süre çubuğu, kategori, soru metni.
///
/// Kart verilen alanın tamamını kaplar ve metni **dikey ortalar**. Kısa
/// soruda metin kartın ortasında durur, uzun soruda kart dolar ve içeriği
/// kendi içinde kayar — iki durumda da şıkların yeri değişmez, başparmak
/// her soruda aynı yeri bulur.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.controller});

  final MetroQuizController controller;

  @override
  Widget build(BuildContext context) {
    final question = controller.question;

    return Container(
      key: MetroQuizScreen.questionCardKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Katman merdiveninin en üst basamağı: okunacak yüzey, dokunulacak
        // yüzeyden açık. Kenarlık yok — üç ton zaten ayırıyor, çerçeve
        // eklemek kartı kutuya çevirirdi.
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Süre çubuğu kartın tepesinde: sayı okumak gerekmeden, göz ucuyla
          // "ne kadar kaldı" görülüyor.
          _TimerBar(
            progress: controller.questionProgress,
            urgent: controller.isUrgent,
          ),
          // Kategori kartın **tepesinde sabit**, metro tabelasındaki künye
          // gibi. Soruyla birlikte ortalanınca ikisi tek blok oluyor ve
          // kartın üstü yine boş kalıyordu.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(child: _CategoryTag(category: question.category)),
                const SizedBox(width: AppSpacing.sm),
                _DifficultyMeter(difficulty: question.difficulty),
              ],
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverFillRemaining(
                  // Kısa soru ortalanır, uzun soru büyür ve kayar.
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        question.prompt,
                        // Satır sayısı serbest: kesilen soru cevaplanamaz.
                        style: AppText.lead.copyWith(
                          fontSize: 21,
                          height: 1.3,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sorunun kategorisi — simge ve tam adı.
///
/// Simge **hat renginde değil**: hat rengi bu oyunda da kimlik taşıyor,
/// kategori ondan bağımsız bir eksen. İkisini aynı renge boyamak "Tarih
/// sorusu M4'e ait" gibi okunurdu.
class _CategoryTag extends StatelessWidget {
  const _CategoryTag({required this.category});

  final TriviaCategory category;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kategori: ${category.label}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CategoryGlyphIcon(category: category, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sorunun süre çubuğu.
///
/// Son [QuizRules.urgentSeconds] saniyede **nabız atar**: renk değişimi
/// tek başına yetmiyordu, hareket eden vagonda göz şıklarda olduğu için
/// çubuğun rengini kimse görmüyor. Hareket çevresel görüşle de fark
/// edilir. Nabız yalnızca opaklığı oynatır, düzeni değil.
class _TimerBar extends StatefulWidget {
  const _TimerBar({required this.progress, required this.urgent});

  final double progress;
  final bool urgent;

  @override
  State<_TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<_TimerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_TimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urgent != widget.urgent) _syncPulse();
  }

  void _syncPulse() {
    // "Hareketi azalt" açıksa nabız atmaz; renk zaten uyarıyor.
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.urgent && !reduced) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Renk **hattan bağımsız**: hat rengi kimliktir, durum değil. M1A'da
    // çubuk hat kırmızısıyla çizilince dolu çubuk "süren bitiyor" gibi
    // okunuyordu. Normalde nötr, son çeyrekte uyarı rengi.
    final base = widget.progress < 0.25
        ? AppColors.danger
        : AppColors.textSecondary;
    final filled = (widget.progress * 1000).round().clamp(0, 1000);

    return SizedBox(
      height: 5,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final color = widget.urgent
              ? Color.lerp(base, AppColors.textPrimary, _pulse.value * 0.7)!
              : base;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: filled,
                child: ColoredBox(color: color),
              ),
              Expanded(
                flex: 1000 - filled,
                child: const ColoredBox(color: AppColors.surface),
              ),
            ],
          );
        },
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
      key: MetroQuizScreen.optionsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < question.options.length; i++) ...<Widget>[
          _OptionButton(
            label: question.options[i],
            // Cevaplandıktan sonra doğru şık her hâlükârda gösterilir:
            // oyuncu yanlış yaptıysa doğrusunu öğrenmeden geçmemeli.
            state: !revealing
                ? (controller.eliminatedOptions.contains(i)
                      ? _OptionState.eliminated
                      : _OptionState.idle)
                : i == question.answerIndex
                ? _OptionState.correct
                : i == controller.chosenIndex
                ? _OptionState.wrong
                : _OptionState.dimmed,
            onTap:
                revealing ||
                    controller.status != GameStatus.playing ||
                    controller.eliminatedOptions.contains(i)
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

enum _OptionState { idle, eliminated, correct, wrong, dimmed }

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
        AppColors.surface,
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
      // Jokerle elenen şık: yerinde durur ama artık bir seçenek değil.
      // Kaldırmak düzeni zıplatır ve oyuncu neyin elendiğini göremez.
      _OptionState.eliminated => (
        AppColors.background,
        AppColors.surface,
        AppColors.textMuted,
      ),
      _OptionState.dimmed => (
        AppColors.background,
        AppColors.surface,
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
        // Uzun şıkta kutu büyür; şık kesilirse doğru cevap seçilemez.
        constraints: const BoxConstraints(minHeight: 56),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Text(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppText.bodyStrong.copyWith(color: text),
        ),
      ),
    );
  }
}

/// Seri satırı: kaç doğru gitti, bir sonraki çarpana kaç kaldı.
///
/// Kartın hemen altında **tek satır**. Eskiden nokta dizisi + iki satır
/// metindi ve düzende kendine ayrılmış esnek bir alanda duruyordu; o alan
/// soruyla şıkları birbirinden koparan boşluğun ta kendisiydi.
class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.controller, required this.accent});

  final MetroQuizController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final streak = controller.streak;
    final remaining = controller.answersToNextMultiplier;
    final multiplier = controller.multiplier;

    final tail = remaining == null
        ? 'en üst basamak'
        : multiplier > 1
        ? '$remaining doğru sonra ×${multiplier + 1}'
        : '$remaining doğru sonra ×2';

    return Semantics(
      label: remaining == null
          ? 'Seri $streak, çarpan $multiplier kat, en üst basamak'
          : 'Seri $streak, $remaining doğru sonra çarpan artıyor',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('SERİ $streak', style: AppText.micro.copyWith(color: accent)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                tail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seri çarpanı — skorun yanında sade bir okuma.
///
/// Kutusuz ve ikonsuz: rozet çerçevesi ile stok şimşek ikonu HUD'u
/// kalabalık gösteriyordu. Blok Metro'daki combo okuması da aynı dilde.
class _MultiplierReadout extends StatelessWidget {
  const _MultiplierReadout({required this.multiplier, required this.accent});

  final int multiplier;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Puan çarpanı $multiplier kat',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: Text(
            '×$multiplier',
            style: AppText.stat.copyWith(
              fontSize: 22,
              letterSpacing: -0.5,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kalan yanlış hakkı — üç metro treni.
///
/// Nokta dizisi yerine trenler: oyunun her yerinde aynı çizim var
/// ([MetroTrain]), yani gösterge oyunun diline ait.
class _LivesIndicator extends StatelessWidget {
  const _LivesIndicator({required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    // Üç basamaklı trafik ışığı: üç hak nötr, iki hak uyarı, tek hak
    // tehlike. Sayıyı okumadan da nerede olduğun görünür ve son hakta
    // renk gerçekten bir şey söyler.
    //
    // `danger` normalde yalnızca gerçekleşmiş hatanın rengi. Burada
    // istisna bilinçli: tek hak kalmışsa bir sonraki yanlış yolculuğu
    // bitiriyor, yani uyarı değil gerçekten tehlike.
    final color = switch (left) {
      <= 1 => AppColors.danger,
      2 => AppColors.warning,
      _ => AppColors.textSecondary,
    };

    return Semantics(
      label: 'Kalan yanlış hakkı $left / ${QuizRules.mistakeAllowance}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < QuizRules.mistakeAllowance; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpacing.xs),
                child: MetroQuizLifeIcon(spent: i >= left, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tek bir yanlış hakkı.
///
/// Harcanan hak **boş konturla** çizilir; ayrım renkle değil doluluk
/// farkıyla kurulur, böylece renk körlüğünde ve küçük ölçekte de okunur.
class MetroQuizLifeIcon extends StatelessWidget {
  const MetroQuizLifeIcon({
    super.key,
    required this.spent,
    required this.color,
  });

  /// Bu hak kullanıldı mı?
  final bool spent;

  /// Dolu trenin gövde rengi.
  final Color color;

  /// Üç tren + aralar ≈ 56 px. HUD'da skoru sıkıştırmayacak kadar dar.
  static const double height = 14;

  @override
  Widget build(BuildContext context) {
    if (!spent) {
      return MetroTrain(color: color, height: height, wagons: 1);
    }
    return SizedBox(
      width: MetroTrain.widthFor(height: height, wagons: 1),
      height: height,
      child: const CustomPaint(
        painter: MetroTrainPainter(
          // Gövde boş: kontur ve pencereler soluk kalır, siluet durur.
          color: Colors.transparent,
          wagons: 1,
          opacity: 0.3,
        ),
      ),
    );
  }
}

/// Joker düğmesi — iki yanlış şıkkı eler.
///
/// Duraklatmanın yanında, HUD'un sağ ucunda. Hak bitince kaybolmaz,
/// soluklaşır: oyuncu jokerini harcadığını görmeli, düğmenin yok olması
/// "böyle bir şey yoktu" hissi veriyordu.
class _JokerButton extends StatelessWidget {
  const _JokerButton({
    required this.left,
    required this.enabled,
    required this.onTap,
  });

  final int left;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      semanticLabel: left > 0
          ? 'Joker: iki yanlış şıkkı ele, $left hak kaldı'
          : 'Joker hakkı kalmadı',
      child: Container(
        // Dokunma hedefi 44'ün altına düşmesin diye kutu geniş tutuldu.
        constraints: const BoxConstraints(minWidth: 46, minHeight: 44),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          border: Border.all(
            color: enabled ? AppColors.outline : AppColors.surface,
            width: 1.4,
          ),
        ),
        // Çizilmiş glif denendi (dört şık, ikisi çizili) ve ne olduğu
        // anlaşılmadı. Bilgi yarışması geleneğinde bu jokerin adı zaten
        // "50:50"; tabela fontu rakamları HUD'daki skordan ayırıyor, yani
        // sayı olarak değil bir işaret olarak okunuyor.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '50:50',
            style: AppText.tileTitle.copyWith(
              fontSize: 12,
              letterSpacing: 0,
              color: enabled ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cevap gösterilirken çıkan tek cümlelik not.
class _ExplanationLine extends StatelessWidget {
  const _ExplanationLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppText.caption.copyWith(fontSize: 12),
    );
  }
}

/// Sorunun zorluğu — üç kademeli küçük gösterge.
///
/// Zor soruya [QuizRules.hardQuestionBonus] kadar ek süre veriliyor ama
/// oyuncu sorunun zor olduğunu bilmiyordu; ek süreyi fark bile
/// etmiyordu. Üç çubuktan kaçının dolu olduğu zorluğu söyler, renk
/// kullanılmaz — kategori zaten renkli, ikinci bir renk ekseni gürültü
/// olurdu.
class _DifficultyMeter extends StatelessWidget {
  const _DifficultyMeter({required this.difficulty});

  final TriviaDifficulty difficulty;

  int get _level => switch (difficulty) {
    TriviaDifficulty.easy => 1,
    TriviaDifficulty.medium => 2,
    TriviaDifficulty.hard => 3,
  };

  String get _label => switch (difficulty) {
    TriviaDifficulty.easy => 'Kolay soru',
    TriviaDifficulty.medium => 'Orta zorlukta soru',
    TriviaDifficulty.hard => 'Zor soru, süre biraz daha uzun',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (var i = 1; i <= 3; i++)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Container(
                  width: 3,
                  // Çubuklar yükselir: dolu olanların sayısı kadar,
                  // boyları da zorluğu ikinci kez söyler.
                  height: 5.0 + i * 3,
                  decoration: BoxDecoration(
                    color: i <= _level
                        ? AppColors.textSecondary
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Oyun başlamadan önceki konu seçimi.
///
/// Havuzda altı kategori var ve oyuncu hepsini istemeyebilir: "bugün
/// yalnız İstanbul" demek, oyunu yeniden açmak için bir sebep. Karışık
/// birincil eylem olarak duruyor, yani seçim yapmak **zorunlu değil**.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.journey,
    required this.onPick,
    required this.onExit,
  });

  final Journey journey;
  final ValueChanged<TriviaCategory?> onPick;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Pressable(
                    onTap: onExit,
                    semanticLabel: 'Geri',
                    borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'KONU SEÇ',
                      textAlign: TextAlign.center,
                      style: AppText.title,
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '${journey.origin.name} → ${journey.destination.name}',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.xl),
              Pressable(
                onTap: () => onPick(null),
                borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
                semanticLabel: 'Karışık: tüm konulardan soru',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.action,
                    borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
                  ),
                  child: Text(
                    'KARIŞIK',
                    style: AppText.tileTitle.copyWith(
                      color: AppColors.onAction,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('YA DA TEK KONU', style: AppText.micro),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView.separated(
                  itemCount: TriviaCategory.values.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final category = TriviaCategory.values[index];
                    return Pressable(
                      onTap: () => onPick(category),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.fieldRadius,
                      ),
                      semanticLabel: 'Yalnız ${category.label}',
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.fieldRadius,
                          ),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Row(
                          children: <Widget>[
                            CategoryGlyphIcon(category: category, size: 20),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                category.label,
                                style: AppText.bodyStrong,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
