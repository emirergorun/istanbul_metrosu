import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../games/catalog/game_cover.dart';
import '../../games/catalog/mini_game.dart';
import '../application/daily_controller.dart';
import '../domain/daily_plan.dart';
import 'widgets/mission_card.dart';
import 'widgets/streak_badge.dart';

/// Günün yolculuğu, görevleri ve serisi.
///
/// Ekran **kendi oyun başlatma yolunu kurmuyor**: BAŞLA, V2'nin oyun tanıtım
/// ekranını açıyor, oyun oradan başlıyor. İkinci bir başlatma hattı olsaydı
/// keşif, rekor ve sonuç akışı iki yerde ayrı ayrı bakım isterdi.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;
    final scope = AppScope.of(context);
    // Ekrana gelmek günü **başlatmaz**: sayaçlar yalnız oynanınca büyür.
    // Buradaki tek yan etki gün dönümünün tazelenmesi.
    scope.daily?.refreshDay();
    scope.analytics.log(AnalyticsEvent.dailyJourneyViewed);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final daily = scope.daily;

    if (daily == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('BUGÜN', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: daily,
          builder: (BuildContext context, _) {
            final plan = daily.plan;
            if (plan == null) return const _NoPlanNotice();

            final line = scope.metro.lineById(plan.journey.lineId);
            final accent = LineTheme.from(
              line?.color ?? AppColors.brandNavy,
            ).accent;
            final game = MiniGames.byId(plan.gameId);

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: <Widget>[
                _DailyHero(
                  plan: plan,
                  game: game,
                  accent: accent,
                  lineColor: line?.color ?? AppColors.brandNavy,
                  complete: daily.isDailyComplete,
                ),
                // Yığındaki her blok arasında **aynı** boşluk;
                // bkz. [AppSpacing.stack].
                const SizedBox(height: AppSpacing.stack),
                _StartBar(
                  plan: plan,
                  game: game,
                  complete: daily.isDailyComplete,
                ),
                // Bölüm başlığı başlıyor: tek istisna burası.
                const SizedBox(height: AppSpacing.sectionGap),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('GÖREVLER', style: AppText.sectionTitle),
                    ),
                    StreakBadge(
                      days: daily.streak,
                      completedToday: daily.streakCompletedToday,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.stack),
                for (final mission in daily.missions) ...<Widget>[
                  MissionCard(
                    mission: mission,
                    progress: daily.progressOf(mission),
                    accent: accent,
                  ),
                  const SizedBox(height: AppSpacing.stack),
                ],
                _StreakFootnote(daily: daily),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Günün kartı: kapak, rota ve oyun tek bakışta.
class _DailyHero extends StatelessWidget {
  const _DailyHero({
    required this.plan,
    required this.game,
    required this.accent,
    required this.lineColor,
    required this.complete,
  });

  final DailyPlan plan;
  final MiniGame? game;
  final Color accent;
  final Color lineColor;
  final bool complete;

  /// Kartın en az yüksekliği; kapağın genişliği de buradan türer.
  ///
  /// Kapak küçültülmüş hâliyle geliyor: ekranı kaplamayan bir poster.
  static const double _coverHeight = 152;

  @override
  Widget build(BuildContext context) {
    final journey = plan.journey;

    return Semantics(
      container: true,
      label:
          'Bugünün yolculuğu. ${journey.lineId} hattı, '
          '${journey.origin.name} durağından ${journey.destination.name} '
          'durağına, yaklaşık ${journey.estimatedMinutes} dakika. '
          'Oyun: ${game?.name ?? 'seçilmedi'}.'
          '${complete ? ' Tamamlandı.' : ''}',
      child: ExcludeSemantics(
        // Hat rengi şeridi **dış kutunun kendisi**.
        //
        // Yuvarlatılmış köşeyle tek kenarı kalın bir kenarlık çizilemiyor
        // (Flutter düzgün olmayan kenarlığı reddediyor), esneyen bir şerit
        // ise `CrossAxisAlignment.stretch` ister — o da satırın yüksekliği
        // serbestken çocuklara sonsuz yükseklik dayatır. İç içe iki kutu
        // ikisini de çözüyor: dıştaki hat renginde, içteki yüzey renginde
        // ve soldan üç piksel içeride.
        child: Container(
          padding: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(AppSpacing.cardRadius),
              ),
              border: Border.all(
                color: complete
                    ? AppColors.success.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            // Kartın yüksekliğini **metin** belirliyor, kapak değil.
            //
            // Kapak kendi içinde `LayoutBuilder` kullanıyor; doğal yükseklik
            // hesabı ondan geçemediği için `IntrinsicHeight` kullanılamıyor
            // ("LayoutBuilder does not support returning intrinsic
            // dimensions"). Kapağa sabit bir kutu veriliyor, satırın
            // yüksekliği ise metinden geliyor: büyük yazı ölçeğinde üç durak
            // adı 152 pikselin içine sığmıyor ve sabit yükseklikte taşardı.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (game != null)
                  SizedBox(
                    width: _coverHeight * GameCoverCard.aspectRatio,
                    height: _coverHeight,
                    // Başlık kapağın dışında: 84 piksellik posterde tabela
                    // fontu satır ortasından bölünüyor ("HAT BİRL / EŞTİR").
                    // Oyunun adı aşağıda, kendi satırında okunuyor.
                    child: GameCover(game: game!, showTitle: false),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            LineBadge(
                              label: journey.lineId,
                              color: lineColor,
                              compact: true,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            if (complete)
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          journey.origin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                        const Icon(
                          Icons.south_rounded,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        Text(
                          journey.destination.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        if (game != null)
                          Text(
                            game!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(color: game!.color),
                          ),
                        Text(
                          '${Formatters.approxMinutes(journey.estimatedMinutes)}'
                          ' · ${journey.stopCount} durak',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.micro.copyWith(
                            color: AppColors.textMuted,
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Günün birincil eylemi.
///
/// Tamamlandıysa düğme kaybolmaz, **ikincilleşir**: aynı gün tekrar
/// oynanabilir, ama artık ekranın en yüksek sesli ögesi değildir.
class _StartBar extends StatelessWidget {
  const _StartBar({
    required this.plan,
    required this.game,
    required this.complete,
  });

  final DailyPlan plan;
  final MiniGame? game;
  final bool complete;

  void _start(BuildContext context) {
    final scope = AppScope.of(context);
    scope.analytics.log(
      AnalyticsEvent.dailyJourneyStarted,
      params: <String, String>{'game_id': plan.gameId},
    );
    AppRoutes.openGameDetail(context, plan.journey, gameId: plan.gameId);
  }

  @override
  Widget build(BuildContext context) {
    if (game == null) return const SizedBox.shrink();

    if (complete) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _CompletedBanner(),
          const SizedBox(height: AppSpacing.stack),
          OutlinedButton(
            onPressed: AppFeedback.onTap(context, () => _start(context)),
            child: const Text('TEKRAR OYNA'),
          ),
        ],
      );
    }

    return FilledButton(
      onPressed: AppFeedback.onTap(context, () => _start(context)),
      child: const Text('BAŞLA'),
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Bugünün yolculuğu tamamlandı',
              style: AppText.bodyStrong.copyWith(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

/// Serinin ne anlama geldiğini bir kez söyleyen satır.
class _StreakFootnote extends StatelessWidget {
  const _StreakFootnote({required this.daily});

  final DailyController daily;

  @override
  Widget build(BuildContext context) {
    final streak = daily.streak;
    final best = daily.bestStreak;

    final text = switch ((streak, daily.streakCompletedToday)) {
      (0, _) => 'Günün yolculuğunu tamamla, seri başlasın.',
      (_, true) => 'Yarın da tamamlarsan seri ${streak + 1} güne çıkar.',
      _ => 'Seri $streak günde. Bugünü de tamamla, sürsün.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Af hakkı yanmadan önce söyleniyor: oyuncu bir gün kaçırmış ve
        // serisi hâlâ ayakta. Bunu görmeden bugünü de kaçırırsa seri
        // gerçekten biter — uyarı tam da o yüzden burada.
        if (daily.isStreakForgivenToday) ...<Widget>[
          _GraceNotice(streak: streak),
          const SizedBox(height: AppSpacing.stack),
        ],
        Text(text, style: AppText.caption),
        if (best > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'En uzun serin $best gün · toplam '
              '${daily.totalDaysCompleted} gün tamamladın.',
              style: AppText.micro.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// Bir gün kaçırıldı ama seri af hakkıyla ayakta.
///
/// Her seri **bir** kaçırılmış gün hakkına sahip: gündelik bir oyunda tek
/// bir yoğun günün otuz günlük seriyi sıfırlaması oyuncuyu geri getirmiyor,
/// kaçırıyor. Hak seri kırıldığında tazeleniyor.
class _GraceNotice extends StatelessWidget {
  const _GraceNotice({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.history_toggle_off_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Dün kaçırdın ama $streak günlük serin duruyor. Bugünü '
              'tamamla, sürsün.',
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Metro verisi günlük rota veremediğinde.
///
/// Kullanıcı hatası değil veri sorunu; suçlayıcı olmayan tek cümle yeter.
class _NoPlanNotice extends StatelessWidget {
  const _NoPlanNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Bugün için yolculuk hazırlanamadı. Rota seçerek oynamaya devam '
          'edebilirsin.',
          textAlign: TextAlign.center,
          style: AppText.body,
        ),
      ),
    );
  }
}
