import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/audio/audio_service.dart';
import '../../../../core/widgets/metro_train.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../journey/models/journey.dart';
import '../../../session/journey_status.dart';
import '../../../session/widgets/arrival_sequence.dart';
import '../../../session/widgets/journey_hud.dart';
import '../../../session/widgets/journey_status_bar.dart';
import '../../../session/widgets/overlay_panel.dart';
import '../../../session/widgets/pause_overlay.dart';
import '../../../session/widgets/result_overlay.dart';
import '../../../session/widgets/sprint_banner.dart';
import '../application/metro_quiz_controller.dart';
import '../application/quiz_pool.dart';
import '../domain/quiz_rules.dart';
import '../domain/trivia_category.dart';

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
      pool: QuizPool(repository: scope.questions),
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
                          _MultiplierReadout(
                            multiplier: controller.multiplier,
                            accent: accent,
                          ),
                        _LivesIndicator(left: controller.livesLeft),
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
                          if (controller.streak > 0) ...<Widget>[
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
          _TimerBar(progress: controller.questionProgress),
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
            child: _CategoryTag(category: question.category),
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

/// Sorunun kategorisi — üç harfli rozet ve tam adı.
///
/// Rozet dili metro hat rozetiyle aynı (`M4`, `TAR`), ama **rengi hat rengi
/// değil**: hat rengi bu oyunda da kimlik taşıyor, kategori ondan bağımsız
/// bir eksen. İkisini aynı renge boyamak "Tarih sorusu M4'e ait" gibi
/// okunurdu.
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                // Kart artık surfaceHigh; rozet bir basamak aşağıdan.
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                category.badge,
                style: AppText.micro.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
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
            child: const ColoredBox(color: AppColors.surface),
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
      key: MetroQuizScreen.optionsKey,
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
    // Tek hak kalınca uyarı rengi: sayıyı okumadan da fark edilsin. Hata
    // rengi (`danger`) bilinçli olarak kullanılmıyor — o renk yalnızca
    // gerçekleşmiş hatanın rengi, burada henüz hata yok.
    final color = left <= 1 ? AppColors.warning : AppColors.textSecondary;

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
