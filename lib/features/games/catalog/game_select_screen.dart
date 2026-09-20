import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../journey/models/journey.dart';
import '../../session/journey_host.dart';
import '../../session/journey_run.dart';
import '../../session/journey_session.dart';
import '../../session/widgets/arrival_sequence.dart';
import '../../session/widgets/journey_status_bar.dart';
import '../../session/widgets/journey_breakdown.dart';
import '../../session/widgets/result_overlay.dart';
import '../../../core/audio/audio_service.dart';
import 'game_glyph.dart';
import 'mini_game.dart';

/// Rota seçildikten sonra gelen oyun seçim ekranı.
///
/// Akış bilinçli olarak **önce rota, sonra oyun**: rota yolculuğun ne kadar
/// süreceğini belirler, oyun ise o süreyi neyle geçireceğini. Bu yüzden
/// yolculuk özeti üstte sabit durur — oyuncu neyi seçtiğini unutmasın.
class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({super.key, required this.journey});

  final Journey journey;

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  JourneySession? _session;

  Journey get journey => widget.journey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Yolculuk burada başlar ve oyunlar arasında **sürer**: oyuncu oyun
    // değiştirince saat sıfırlanmaz, puan sıfırlanmaz. Aynı rota için
    // ikinci kez gelindiğinde var olan yolculuk döner.
    final session = JourneyScope.of(context).start(journey);
    if (identical(session, _session)) return;
    _session?.removeListener(_onSessionChanged);
    _session = session..addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // Süre oyun seçerken de akıyor; burada bitebilir. Kapı sesi bir kez.
    if (_session?.status == GameStatus.arrived && !_playedArrivalSound) {
      _playedArrivalSound = true;
      AppScope.of(context).audio.play(GameSound.arrival);
    }
    setState(() {});
  }

  bool _playedArrivalSound = false;

  /// Yolculuğu kapatır ve başlığa döner.
  void _finishJourney() {
    JourneyScope.of(context).close();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _start(BuildContext context, MiniGame game) async {
    if (!game.isAvailable) return;
    await AppRoutes.openGame(context, journey, gameId: game.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final line = scope.metro.lineById(journey.lineId);
    final lineTheme = LineTheme.from(line?.color ?? AppColors.brandNavy);
    final session = _session;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Oyun seç', style: AppText.title),
      ),
      body: Stack(
        children: <Widget>[
          _buildList(context, scope, lineTheme, session),
          // Süre oyun seçerken dolduysa tören burada oynar: yolculuk nerede
          // biterse orada kutlanır.
          if (session != null && session.status == GameStatus.arrived)
            ArrivalSequence(
              accent: lineTheme.accent,
              lineId: journey.lineId,
              stationName: journey.destination.name,
              onSkipped: () => AppScope.of(context).audio.stopLongForm(),
              child: _buildResult(session, lineTheme.accent),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(JourneySession session, Color accent) {
    return ResultOverlay(
      isArrival: true,
      destinationName: journey.destination.name,
      score: session.score,
      recordToBeat: session.recordToBeat,
      isFirstRun: session.isFirstRun,
      recordBeaten: session.recordBeaten,
      accent: accent,
      isNewBest: session.isNewBest,
      showBackdrop: false,
      extraStats: <Widget>[...journeyBreakdownRows(session)],
      onRestart: _finishJourney,
      onExit: _finishJourney,
    );
  }

  Widget _buildList(
    BuildContext context,
    AppScope scope,
    LineTheme lineTheme,
    JourneySession? session,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        _JourneySummary(journey: journey, lineTheme: lineTheme),
        if (session != null) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          // Yolculuk oyun seçerken de sürüyor; tren, kalan süre ve geçilen
          // duraklar burada da görünmeli. Oyunların içindeki şeridin
          // aynısı: yolculuk ortak olduğu için widget da ortak.
          JourneyStatusBar(
            run: session,
            lineStations: scope.metro.stationsOfLine(journey.lineId),
            accent: lineTheme.accent,
            isMoving: session.status != GameStatus.arrived,
            // Durak şeridi üstteki kartın üzerine taşardı; adı zaten
            // şeridin kendi satırında yazıyor.
            showStationBanner: false,
            // Oyun değiştirirken toplam puan görünsün: skoru gösteren
            // başka bir şey yok bu ekranda.
            showScore: true,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle('OYUNLAR'),
        for (final game in MiniGames.all) ...<Widget>[
          _GameCard(
            game: game,
            // Rekor artık oyunun değil yolculuğun: kartta bu oyunun **bu
            // yolculukta** kazandırdığı puan yazar. Hangi oyunun ne
            // getirdiğini gösterir, ayrı bir rekor yarışı açmaz.
            earnedThisJourney: session?.scoreOf(game.id) ?? 0,
            onTap: () => _start(context, game),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Hangi yolculuk için oyun seçildiğini hatırlatan üst şerit.
class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.journey, required this.lineTheme});

  final Journey journey;
  final LineTheme lineTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                LineBadge(label: journey.lineId, color: lineTheme.color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${journey.origin.name} → ${journey.destination.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.lead.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            // Süre ve açıklama alt alta: yan yana konsaydı ikisi de esnek
            // olmadığı için dar ekranda ve büyük yazı ölçeğinde (uygulama
            // 1.6'ya kadar destekliyor) satır taşardı.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${Formatters.approxMinutes(journey.estimatedMinutes)}'
                        ' · ${journey.stopCount} durak',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Yolculuk ortak: oyun değiştirmek saati de puanı da
                // sıfırlamıyor. Kart bunu söylemezse oyuncu "hangisini
                // seçersem o kadar oynarım" sanıyor.
                Text(
                  'Hangi oyunu seçersen seç, puan aynı yolculuğa yazılır.',
                  style: AppText.caption.copyWith(
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 3, color: lineTheme.accent),
        ],
      ),
    );
  }
}

/// Tek bir oyun kartı. Kilitliyse soluk ve tıklanamaz.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.earnedThisJourney,
    required this.onTap,
  });

  final MiniGame game;

  /// Bu oyunun **bu yolculukta** kazandırdığı puan; 0 ise henüz oynanmadı.
  final int earnedThisJourney;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = !game.isAvailable;
    final foreground = locked ? AppColors.textMuted : AppColors.textPrimary;

    return Semantics(
      button: !locked,
      enabled: !locked,
      label: locked
          ? '${game.name}, yakında eklenecek, henüz oynanamaz'
          : '${game.name}. ${game.tagline}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Pressable(
            // Kilitli kartta `onTap: null` — dokunma geri bildirimi de olmaz,
            // böylece "bozuk mu?" hissi vermez.
            onTap: locked ? null : onTap,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                // Kenarlık nötr: altı kartın da hat renginde çerçevesi
                // olunca hepsi "seçili" gibi görünüyor ve aralarında
                // hiyerarşi kalmıyordu. Hat kimliği yukarıdaki yolculuk
                // şeridinde zaten var; kart burada içeriğiyle ayrışmalı.
                border: Border.all(
                  color: locked ? AppColors.outline : AppColors.surfaceHigh,
                  width: locked ? 1 : 1.6,
                ),
              ),
              child: Row(
                children: <Widget>[
                  // Kutu ve glif **nötr**. Altı oyuna altı ayrı pastel ton
                  // verilmişti; hepsi aynı ağırlıktaydı, hiçbiri bir şey
                  // söylemiyordu ve ekrandaki gerçek renk sistemiyle —
                  // hat kimliğiyle — yarışıyordu. Ayrımı glif ve ad yapar.
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.gameGlyphBox,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GameGlyphIcon(
                      glyph: locked ? GameGlyph.locked : game.glyph,
                      color: locked ? AppColors.gameGlyphLocked : game.color,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                game.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // Oyun adı tabela fontunda: ekran başlığı
                                // ("OYUN SEÇ") ile aynı ses. Kart adı gövde
                                // fontundayken başlıkla aynı hiyerarşide
                                // duruyor ve liste bir ayar ekranı gibi
                                // okunuyordu.
                                style: AppText.tileTitle.copyWith(
                                  color: foreground,
                                ),
                              ),
                            ),
                            if (locked) ...<Widget>[
                              const SizedBox(width: AppSpacing.sm),
                              const _SoonBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          game.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                        // Oyuncu puanını hangi oyundan topladığını görsün:
                        // bu yolculukta kazandırmadıysa kart sessiz kalır.
                        if (!locked && earnedThisJourney > 0) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            'BU YOLCULUKTA  '
                            '${Formatters.score(earnedThisJourney)} PUAN',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.micro.copyWith(
                              fontFeatures: kTabularFigures,
                              color: game.color,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!locked) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    // Oynat oku bir eylem çağrısı, kimlik değil: hattan
                    // bağımsız sabit aksiyon renginde kalır.
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 28,
                      color: AppColors.action,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outline),
      ),
      child: const Text('YAKINDA', style: AppText.micro),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: AppText.micro.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
